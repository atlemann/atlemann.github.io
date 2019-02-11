---
layout: post
title:  "Make FAKE release on git tag"
categories: fsharp
tags: f# fsharp dotnet CI TeamCity git tag release
---

In this post we're going to see how we can make a FAKE script detect when to do only build and test and when to pack and ship using a `SemVer` formatted git tag. Then you can have a single build configuration on your CI server and have FAKE take care of which type of build to run.

In this example our release will be a NuGet package, but this could be a docker image or something else. For public NuGet packages, using FAKE's [Release notes helper](https://fake.build/apidocs/v5/fake-core-releasenotes.html) to define the release version including release notes is an alternative approach.

We're going to create a small sample project with two classlibs and a test project. The code for the post can be found [here](https://github.com/atlemann/MyNuget/tree/master).

## Tools we're going to use

* [FAKE](https://fake.build)
* [Paket](https://fsprojects.github.io/Paket/)
* [dotnet CLI](https://www.microsoft.com/net/learn/get-started/linuxubuntu)

## FAKE and Paket as global .NET Core tools

Now that both FAKE and Paket have dotnet tools we can just install those to avoid all that bootstrapping that was required before. No need for `mono` either, unless we're doing multi-target builds on linux.

```bash
$ dotnet tool install -g fake-cli
$ dotnet tool install -g paket
```

Now you can just write

```bash
$ paket restore
$ fake build
```

in your command line to restore packages and run a FAKE build script.

## Creating a sample solution

```
$ dotnet new classlib -lang F# -o src/MyFsNuget
$ dotnet new classlib -lang C# -o src/MyCsNuget
$ dotnet add src/MyFsNuget/MyFsNuget.fsproj reference src/MyCsNuget/MyCsNuget.csproj
$ dotnet new -i Expecto.Template::*
$ dotnet new expecto -o tests/MyFsNugetTests
$ dotnet add tests/MyFsNugetTests/MyFsNugetTests.fsproj reference src/MyFsNuget/MyFsNuget.fsproj
$ dotnet new sln -n MyNuget
$ dotnet sln add **/**/*.*sproj
```

Now we'll convert to `Paket` by running:

```
$ paket convert-from-nuget
```

This will move the packages specified in the `Expecto` test project into a `paket.dependencies` file which should look something like this:

```
source https://www.nuget.org/api/v2
nuget Expecto >= 8.0
nuget FSharp.Core >= 4.0
nuget Microsoft.NET.Test.Sdk >= 15.0
nuget YoloDev.Expecto.TestSdk
```

It will also add

```xml
<Import Project="..\..\.paket\Paket.Restore.targets" />
```

to all your project files so Paket can hook on to the build.

## Adding the FAKE dependencies

FAKE 5 has split every module into a separate NuGet package, so we're going to need a couple of them:

* `Fake.Core.Environment`: For getting the git tag environment variable
* `Fake.Core.Semver`: For parsing the git tag
* `Fake.Core.Target`: For creating build steps
* `Fake.DotNet.AssemblyInfoFile`: For writing the asssembly info files
* `Fake.DotNet.Cli`: For building, packing and publishing a NuGet package
* `Fake.IO.FileSystem`: For globbing and file system operators

We're going to add the FAKE modules to a `Build` group in `paket.dependencies` so we can easily reference it in the `build.fsx` file.

(`Microsoft.NET.Test.Sdk` and `YoloDev.Expecto.TestSdk` enables running the `Expecto` tests by invoking `dotnet test`)

```bash
source https://www.nuget.org/api/v2

nuget FSharp.Core

nuget Expecto
nuget Microsoft.NET.Test.Sdk
nuget YoloDev.Expecto.TestSdk

group Build
  source https://www.nuget.org/api/v2

  nuget Fake.Core.Environment
  nuget Fake.Core.SemVer
  nuget Fake.Core.Target
  nuget Fake.DotNet.AssemblyInfoFile
  nuget Fake.DotNet.Cli
  nuget Fake.IO.FileSystem
```

Now we can start creating our FAKE script. Create a new file called `build.fsx` and paste the following content into it:

```fsharp
#r "paket: groupref Build //"
#load @".fake/build.fsx/intellisense.fsx"

#if !FAKE
  #r "netstandard"
#endif
```

This will import the dependencies in the `Build` group in our `paket.dependencies` file and enable intellisense. Now we can just open the dependencies we need (after running `fake build` once to download them):

```fsharp
open Fake.Core
open Fake.DotNet
open Fake.IO.Globbing.Operators
open Fake.IO.FileSystemOperators
```

## Detecting the build configuration

To decide if we're going to release or not we need the following steps:

1. Trigger a build when tagging
2. Pass the tag to the build agents
3. Parse the tag using FAKE

### Triggering a build when tagging

In this example we're going to use `TeamCity` as CI server. To build a tag we must edit the branch specification and tick `Enable to use tags in the branch specification` in the `VCS root` settings:

![VCS root settings]({{ "/assets/publish_fake_git_tag/tags_as_branch.png" }})

This will make TeamCity trigger builds when a new tag is pushed, with the tag as the name of the "branch" (e.g. the version numbers seen here):

![VCS root settings]({{ "/assets/publish_fake_git_tag/tc_branch_name.png" }})

### Passing the tag to the build agents

The next step is to pass that information to the build agents by setting the `%teamcity.build.branch%` value in an environment variable in `Administration -> Root project -> Parameters`:

![VCS root settings]({{ "/assets/publish_fake_git_tag/tc_root_params.png" }})

specified here as `BRANCH_NAME`:

![VCS root settings]({{ "/assets/publish_fake_git_tag/tc_env_var.png" }})

### Parsing the tag using FAKE

FAKE has a [SemVer helper](https://fake.build/apidocs/v5/fake-core-semver.html) which can check and parse SemVer strings. Here we'll use that to create a simple active pattern which we can use for deciding what to do for a given `BRANCH_NAME`. 

```fsharp
open Fake.Core

let (|Release|CI|) input =
    if SemVer.isValid input then
        let semVer = SemVer.parse input
        Release semVer
    else
        CI
```

Next we'll use FAKE's [Environment helper](https://fake.build/apidocs/v5/fake-core-environment.html) to read our environment variable containing the branch name. If the variable doesn't exist, say, on your dev environment, we just default to an empty string to run build and test.

```fsharp
let branchName = Environment.environVarOrDefault "BRANCH_NAME" ""
```

Finally, we'll use the active pattern together with the branch name to decide what to do. As you can see, both the `AssemblyInfo` and `Pack` targets requires the version which is conveniently provided by the active pattern.

```fsharp
let projectOrSln = "src" </> "MyFsNuget" </> "MyFsNuget.fsproj"

...
...

open Fake.Core.TargetOperators

let buildTarget =
    match branchName with
    | Release version ->
        createAssemblyInfoTarget version
        createPackTarget version projectOrSln
        Target.create "Release" ignore

        "Clean"
        ==> "AssemblyInfo"
        ==> "Build"
        ==> "Test"
        ==> "Pack"
        ==> "Push"
        ==> "Release"

    | CI ->
        Target.create "CI" ignore

        "Clean"
        ==> "Build"
        ==> "Test"
        ==> "CI"

Target.runOrDefault buildTarget
```

The `buildTarget` value will be either `Release` or `CI` depending on which branch it took, so we can just pass that into `Target.runOrDefault`.

### Updating the assembly info

Here we're passing in the parsed semver info when creating the assembly info target. Assembly info only supports `major.minor.patch` strings without any `-rc.1` or `-beta`, so we extract what we need from the `SemVerInfo` and update the assembly info for both F# and C# projects.

```fsharp
let summary = "Silly NuGet package"
let product = "MySillyNuget"
...
...

let createAssemblyInfoTarget (semverInfo : SemVerInfo) =

    let assemblyVersion =
        sprintf "%d.%d.%d" semverInfo.Major semverInfo.Minor semverInfo.Patch

    let toAssemblyInfoAttributes projectName =
        [ AssemblyInfo.Title projectName
          AssemblyInfo.Product product
          AssemblyInfo.Description summary
          AssemblyInfo.Version assemblyVersion
          AssemblyInfo.FileVersion assemblyVersion ]

    // Helper active pattern for project types
    let (|Fsproj|Csproj|) (projFileName:string) =
        match projFileName with
        | f when f.EndsWith("fsproj") -> Fsproj
        | f when f.EndsWith("csproj") -> Csproj
        | _                           -> failwith (sprintf "Project file %s not supported. Unknown project type." projFileName)

    Target.create "AssemblyInfo" (fun _ ->
        let getProjectDetails projectPath =
            let projectName = System.IO.Path.GetFileNameWithoutExtension projectPath
            let directoryName = System.IO.Path.GetDirectoryName projectPath
            let assemblyInfo = projectName |> toAssemblyInfoAttributes
            (projectPath, directoryName, assemblyInfo)

        !! "src/**/*.??proj"
        |> Seq.map getProjectDetails
        |> Seq.iter (fun (projFileName, folderName, attributes) ->
            match projFileName with
            | Fsproj -> AssemblyInfoFile.createFSharp (folderName </> "AssemblyInfo.fs") attributes
            | Csproj -> AssemblyInfoFile.createCSharp ((folderName </> "Properties") </> "AssemblyInfo.cs") attributes)
    )
```

Since we're manually creating the assembly info file we have to add the following to our project files:

```xml
<GenerateAssemblyInfo>false</GenerateAssemblyInfo>
```

and for F# projects we also need this:

```xml
<Compile Include="AssemblyInfo.fs" />
```

### Packing a NuGet

```fsharp
open Fake.IO.FileSystemOperators

let author = "My Name"
let summary = "Silly NuGet package"

...
...

/// Pass a single project to pack only that one.
/// Pass the .sln to pack all non-test projects.
let createPackTarget (semVerInfo : SemVerInfo) (projectOrSln : string)=
    Target.create "Pack" (fun _ ->

        // MsBuild uses ; and , as properties separator in the cli
        let escapeCommas (input : string) =
            input.Replace(",", "%2C")

        let customParams =
            [ (sprintf "/p:Authors=\"%s\"" author)
              (sprintf "/p:Owners=\"%s\"" author)
              (sprintf "/p:PackageVersion=\"%s\"" (semVerInfo.ToString()))
              (sprintf "/p:Description=\"%s\"" summary |> escapeCommas) ]
            |> String.concat " "

        DotNet.pack (fun p ->
            { p with
                Configuration = DotNet.BuildConfiguration.Release
                Common = DotNet.Options.withCustomParams (Some customParams) p.Common })
            projectOrSln)
```

If we change the default branch name to, say, `1.2.3-beta.4` like so:

```fsharp
let branchName = Environment.environVarOrDefault "BRANCH_NAME" "1.2.3-beta.4"
```

and run the build script we get a `nupkg` which contains a `nuspec` with the following content:

```xml
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>MyFsNuget</id>
    <version>1.2.3-beta.4</version>
    <authors>My Name</authors>
    <owners>My Name</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Silly NuGet package</description>
    <dependencies>
      <group targetFramework=".NETStandard2.0">
        <dependency id="MyCsNuget" version="1.2.3-beta.4" exclude="Build,Analyzers" />
        <dependency id="FSharp.Core" version="4.6.1" exclude="Build,Analyzers" />
      </group>
    </dependencies>
  </metadata>
</package>
```

Here we can see that the referenced C# project is actually added as a NuGet dependency, which means you would have to pack and push that one as well. If you pass a `.sln` file to `dotnet pack` it will pack all non-test projects in the solution as mentioned in the `createPackTarget` function defined above.

However, if you have a multi-project solution where you don't want to expose all the projects as separate NuGets, you can apply the following workaround, as found in the comments in this [github issue](https://github.com/nuget/home/issues/3891), to include the private `.dlls` in the main NuGet package instead.

Create a file in your repository root called e.g. `pack.props` with this content:

```xml
<Project>
  <PropertyGroup>
    <TargetsForTfmSpecificBuildOutput>$(TargetsForTfmSpecificBuildOutput);CopyProjectReferencesToPackage</TargetsForTfmSpecificBuildOutput>
  </PropertyGroup>
  <Target Name="CopyProjectReferencesToPackage" DependsOnTargets="ResolveReferences">
    <ItemGroup>
      <BuildOutputInPackage Include="@(ReferenceCopyLocalPaths-&gt;WithMetadataValue('ReferenceSourceTarget', 'ProjectReference')-&gt;WithMetadataValue('PrivateAssets', 'All'))" />
    </ItemGroup>
  </Target>
</Project>
```

Then in your main project file, in our case `MyFsProject.fs`, add `PrivateAssets="All"` to the project references you want to include in the main NuGet package and import `pack.props`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <Import Project="../../pack.props"/>
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="AssemblyInfo.fs" />
    <Compile Include="Library.fs" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\MyCsNuget\MyCsNuget.csproj" PrivateAssets="All" />
  </ItemGroup>
  <Import Project="..\..\.paket\Paket.Restore.targets" />
</Project>
```

Now when we run `fake build` again, the `MyCsProject` reference is gone in the `.nuspec` file and the `lib` folder in the NuGet package contains the `MyCsProject.dll`.

### Publishing our NuGet

NuGet packages can be pushed using `dotnet nuget push` which we can invoke using FAKE's `DotNet.exec` helper. Here we're getting the NuGet feed URL and API-KEY from environment variables and then we search all `Release` folders for `.nupkg` files to push:

```fsharp
Target.create "Push" (fun _ ->
    let nugetServer = Environment.environVarOrFail "NUGET_WRITE_URL"
    let apiKey = Environment.environVarOrFail "NUGET_WRITE_APIKEY"

    let result =
        !!"**/Release/*.nupkg"
        |> Seq.map (fun nupkg ->
            Trace.trace (sprintf "Publishing nuget package: %s" nupkg)
            (nupkg, DotNet.exec id "nuget" (sprintf "push %s --source %s --api-key %s" nupkg nugetServer apiKey)))
        |> Seq.filter (fun (_, p) -> p.ExitCode <> 0)
        |> List.ofSeq

    match result with
    | [] -> ()
    | failedAssemblies ->
        failedAssemblies
        |> List.map (fun (nuget, proc) -> 
            sprintf "Failed to push NuGet package '%s'. Process finished with exit code %d." nuget proc.ExitCode)
        |> String.concat System.Environment.NewLine
        |> exn
        |> raise)
```
