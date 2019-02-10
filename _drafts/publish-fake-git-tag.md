---
layout: post
title:  "Triggering release with git tag using FAKE"
categories: fsharp
tags: f# fsharp dotnet CI TeamCity
---

In this post we're going to see how we can make a FAKE script detect when to do only build and test and when to pack and ship using a semver formatted git tag.

In this example our release will be a NuGet package, but this could be a docker image or something else. For public NuGet packages, using FAKE's [Release notes helper](https://fake.build/apidocs/v5/fake-core-releasenotes.html) to define the release version might be preferable if you want to include release notes.

We're going to create a small sample project with two classlibs and a test project.

## Tools

* [FAKE](https://fake.build)
* [Paket](https://fsprojects.github.io/Paket/)
* [dotnet CLI](https://www.microsoft.com/net/learn/get-started/linuxubuntu)
* [TeamCity](https://www.jetbrains.com/teamcity/)

## FAKE and Paket as global .NET Core tools

Now that both FAKE and Paket have dotnet tools we can just install those to avoid all that bootstrapping that was required before. No need for mono either, unless we're doing multi-target builds on linux.

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

## Required FAKE tools

* `Fake.Core.Environment`: For getting the git tag environment variable
* `Fake.Core.Semver`: For parsing the git tag
* `Fake.DotNet.Cli`: For building, packing and publishing a NuGet package
* `Fake.DotNet.AssemblyInfoFile`: For writing the asssembly info files

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

to all your project files.

## Specifying the FAKE dependencies

We're going to add the FAKE modules we require to a `Build` group in `paket.dependencies` so we can easily reference it in the `build.fsx` file.

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

This will import the dependencies in the `Build` group in our `paket.dependencies` file and enable intellisense. Now we can just open the dependencies we need:

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

In this example we're going to use `TeamCity` as CI server. To build a tag we must `Enable to use tags in the branch specification` in the `VCS root` settings:

![VCS root settings]({{ "/assets/publish_fake_git_tag/tags_as_branch.png" }})

This will give you builds with the tag as the name of the "branch", e.g. like the version numbers here:

![VCS root settings]({{ "/assets/publish_fake_git_tag/tc_branch_name.png" }})

### Passing the tag to the build agents

The next step is to pass that information to the build agents by setting the `%teamcity.build.branch%` value in an environment variable in `Administration -> Root project -> Parameters`:

![VCS root settings]({{ "/assets/publish_fake_git_tag/tc_root_params.png" }})

specified here as `BRANCH_NAME`:

![VCS root settings]({{ "/assets/publish_fake_git_tag/tc_env_var.png" }})

### Parsing the tag using FAKE

FAKE has a [SemVer helper](https://fake.build/apidocs/v5/fake-core-semver.html) which can check and parse SemVer strings into a record type. Here we'll use that to create a simple active pattern which we can use for deciding what to do for a given `BRANCH_NAME`. 

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
open Fake.Core.TargetOperators

let buildTarget =
    match branchName with
    | Release version ->
        createAssemblyInfoTarget version
        createPackTarget version nugetProject
        Target.create "Release" ignore

        "Clean"
        ==> "AssemblyInfo"
        ==> "Restore"
        ==> "Build"
        ==> "Test"
        ==> "Pack"
        ==> "Push"
        ==> "Release"

    | CI ->
        Target.create "CI" ignore

        "Clean"
        ==> "Restore"
        ==> "Build"
        ==> "Test"
        ==> "CI"

Target.runOrDefault buildTarget
```

The `buildTarget` value will be either `Release` or `CI` depending on which branch it took, so we can just pass that into `Target.runOrDefault`.

### Updating the assembly info

Here we're passing in the parsed semver info when creating the assembly info target. Assembly info only supports `major.minor.patch` strings without any `-rc.1 or -beta`, so we extract what we need from the `SemVerInfo` and update the assembly info for both F# and C# projects.

```fsharp
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
let author = "My Name"
let summary = "Silly NuGet package"

...

let createPackTarget (semVerInfo : SemVerInfo) (project : string)=
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
            project)
```