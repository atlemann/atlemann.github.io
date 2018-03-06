---
layout: post
title:  "Setting up multi targeting build with mono"
categories: fsharp
tags: f# fsharp ubuntu linux development vscode ionide mono dotnet
---

In this post I'm going to show how I did my first PR to an open-source project, adding support for multi-target builds using Mono for [FSUnit](https://github.com/fsprojects/FsUnit).

## Finding an issue

I have always wanted to contribute to an open-source project. I've found myself many times looking at the issues list for tools I have used, unfortunately I never managed to actually do it. Then a tweet from Sergey Thion where he asked if anyone would try Don Syme's suggestion for how to do multi-target builds using dotnet CLI and Mono. I thought why not, I'm coding F# on Linux and find it much simpler to maintain Linux dockers instead of Windows VMs for CI build agents.

Sergey had already created an issue in his project `FSUnit`, which I said I was willing to try to fix for him. He was very greatful and I was feeling ... semi confident :)

![FSUnit issue]({{ "/assets/multi_targeting_mono/fsunit_issues.png" }})

## Step 1: Forking the project

Since you don't have write access to someone elses repository, the first thing you'll have to do is fork the repository to you own account. So, first I logged on to GitHub with my own account, then I moved to the `fsprojects/FsUnit` repository and pressed the `Fork` button in the top right corner.

![Forking]({{ "/assets/multi_targeting_mono/fsunit_fork.png" }})

This created a copy of FSUnit to my account, `atlemann/FSUnit`.

![atlemann/FSUnit]({{ "/assets/multi_targeting_mono/atlemann_fsunit_title.png" }})

## Step 2: Cloning the fork

Next I cloned __my copy__ of `FSUnit` (Note the path containing my username) to my machine.

![Clone]({{ "/assets/multi_targeting_mono/atlemann_fsunit_clone.png" }})

Here I'm cloning the repository and opening it in VSCode:

```bash
~src$ git clone git@github.com:atlemann/FsUnit.git
Cloning into 'FsUnit'...
remote: Counting objects: 9766, done.
remote: Compressing objects: 100% (57/57), done.
remote: Total 9766 (delta 61), reused 83 (delta 53), pack-reused 9655
Receiving objects: 100% (9766/9766), 72.63 MiB | 4.85 MiB/s, done.
Resolving deltas: 100% (4796/4796), done.
Checking connectivity... done.
~src$ code FsUnit
```

This is how it looks:

![VSCode]({{ "/assets/multi_targeting_mono/opened_vscode.png" }})

The integrated terminal in VSCode is great. At least when combined with git branch annotations so you always know which branch you're in.

## Step 3: How do I build this thing?

Nothing is as depressing as wanting to contribute to something and not being able to easily compile the thing. Fortunately, Sergey is following one of the most common conventions in the F# world: build using `FAKE`, handle dependencies using `Paket`. In the tree we find the usual `build.sh/build.cmd` files which can be used to build on Linux and Windows respectivey. So here goes `build.sh`:

![First build]({{ "/assets/multi_targeting_mono/first_build.png" }})

Success! However, wasn't the task to add multi-target build on Mono? Let's check what it built:

![Only netstandard]({{ "/assets/multi_targeting_mono/only_netstandard_in_bin.png" }})

Here we'll have to check the `FsUnit.NUnit.fsproj` file to see what's going on.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>netstandard2.0;net46</TargetFrameworks>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(OS)' != 'Windows_NT' ">
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>
  <PropertyGroup>
    <AssemblyName>FsUnit.NUnit</AssemblyName>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="AssemblyInfo.fs" />
    <Compile Include="FsUnit.fs" />
    <Compile Include="FsUnitTyped.fs" />
    <Compile Include="GenericAssert.fs" />
    <None Include="paket.references" />
    <None Include="paket.template" />
    <None Include="FsUnitSample.fs.pp">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
    <None Include="sample.paket.template" />
  </ItemGroup>
  <ItemGroup Condition=" '$(TargetFramework)' != 'netstandard1.6' ">
    <Reference Include="System" />
  </ItemGroup>
  <Import Project="..\..\.paket\Paket.Restore.targets" />
</Project>
```

Here we see `<PropertyGroup Condition=" '$(OS)' != 'Windows_NT' ">` makes sure only `netstandard2.0` target is build if not on windows, which explains it. Lets try to remove it and see what happens:

```bash
/usr/share/dotnet/sdk/2.1.4/Microsoft.Common.CurrentVersion.targets(1124,5):
error MSB3644: The reference assemblies for framework
".NETFramework,Version=v4.6" were not found. To resolve this, install the SDK
or Targeting Pack for this framework version or retarget your application to
a version of the framework for which you have the SDK or Targeting Pack
installed. Note that assemblies will be resolved from the Global Assembly
Cache (GAC) and will be used in place of reference assemblies. Therefore
your assembly may not be correctly targeted for the framework you intend.
[/home/atle/src/FsUnit/src/FsUnit.NUnit/FsUnit.NUnit.fsproj]
    28 Warning(s)
    1 Error(s)

Time Elapsed 00:00:59.80
Running build failed.
```

This fails, as expected.

## Step 4: Fixing the issue

There are three projects in the solution that have to be fixed:

1. FsUnit.NUnit
2. FsUnit.MsTestUnit
3. FsUnit.Xunit

First things first, now I will create a local branch to apply this fix:

```bash
atle@latle:~/src/FsUnit (master)$ checkout -b make.multitarget.build.on.linux
Branch make.multitarget.build.on.linux set up to track remote branch make.multitarget.build.on.linux from origin.
Switched to a new branch 'make.multitarget.build.on.linux'
atle@latle:~/src/FsUnit (make.multitarget.build.on.linux)$
```

In the issue posted by Sergey he [links](https://github.com/dotnet/sdk/issues/335#issuecomment-368669050) to a solution proposed by Don Syme, the creator of F#, so he probably knows what he's talking about. The fix is to add the following content to a file in your repository, called e.g. `netfx.props`, and import it to the relevant `.fsproj` files.

```xml
<PropertyGroup>
  <!-- When compiling .NET SDK 2.0 projects targeting .NET 4.x on Mono using 'dotnet build' you -->
  <!-- have to teach MSBuild where the Mono copy of the reference asssemblies is -->
  <TargetIsMono Condition="$(TargetFramework.StartsWith('net4')) and '$(OS)' == 'Unix'">true</TargetIsMono>
    
  <!-- Look in the standard install locations -->
  <BaseFrameworkPathOverrideForMono Condition="'$(BaseFrameworkPathOverrideForMono)' == '' AND '$(TargetIsMono)' == 'true' AND EXISTS('/Library/Frameworks/Mono.framework/Versions/Current/lib/mono')">/Library/Frameworks/Mono.framework/Versions/Current/lib/mono</BaseFrameworkPathOverrideForMono>
  <BaseFrameworkPathOverrideForMono Condition="'$(BaseFrameworkPathOverrideForMono)' == '' AND '$(TargetIsMono)' == 'true' AND EXISTS('/usr/lib/mono')">/usr/lib/mono</BaseFrameworkPathOverrideForMono>
  <BaseFrameworkPathOverrideForMono Condition="'$(BaseFrameworkPathOverrideForMono)' == '' AND '$(TargetIsMono)' == 'true' AND EXISTS('/usr/local/lib/mono')">/usr/local/lib/mono</BaseFrameworkPathOverrideForMono>

  <!-- If we found Mono reference assemblies, then use them -->
  <FrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != '' AND '$(TargetFramework)' == 'net45'">$(BaseFrameworkPathOverrideForMono)/4.5-api</FrameworkPathOverride>
  <FrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != '' AND '$(TargetFramework)' == 'net451'">$(BaseFrameworkPathOverrideForMono)/4.5.1-api</FrameworkPathOverride>
  <FrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != '' AND '$(TargetFramework)' == 'net452'">$(BaseFrameworkPathOverrideForMono)/4.5.2-api</FrameworkPathOverride>
  <FrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != '' AND '$(TargetFramework)' == 'net46'">$(BaseFrameworkPathOverrideForMono)/4.6-api</FrameworkPathOverride>
  <FrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != '' AND '$(TargetFramework)' == 'net461'">$(BaseFrameworkPathOverrideForMono)/4.6.1-api</FrameworkPathOverride>
  <FrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != '' AND '$(TargetFramework)' == 'net462'">$(BaseFrameworkPathOverrideForMono)/4.6.2-api</FrameworkPathOverride>
  <FrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != '' AND '$(TargetFramework)' == 'net47'">$(BaseFrameworkPathOverrideForMono)/4.7-api</FrameworkPathOverride>
  <FrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != '' AND '$(TargetFramework)' == 'net471'">$(BaseFrameworkPathOverrideForMono)/4.7.1-api</FrameworkPathOverride>
  <EnableFrameworkPathOverride Condition="'$(BaseFrameworkPathOverrideForMono)' != ''">true</EnableFrameworkPathOverride>

    <!-- Add the Facades directory.  Not sure how else to do this. Necessary at least for .NET 4.5 -->
  <AssemblySearchPaths Condition="'$(BaseFrameworkPathOverrideForMono)' != ''">$(FrameworkPathOverride)/Facades;$(AssemblySearchPaths)</AssemblySearchPaths>
</PropertyGroup>
```

### FsUnit.NUnit

Now I changed the `FsUnit.NUnit.fsproj` to look like this:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <Import Project="..\..\netfx.props" />
  <PropertyGroup>
    <TargetFrameworks>netstandard2.0;net46</TargetFrameworks>
  </PropertyGroup>
  <PropertyGroup>
    <AssemblyName>FsUnit.NUnit</AssemblyName>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="AssemblyInfo.fs" />
    <Compile Include="FsUnit.fs" />
    <Compile Include="FsUnitTyped.fs" />
    <Compile Include="GenericAssert.fs" />
    <None Include="paket.references" />
    <None Include="paket.template" />
    <None Include="FsUnitSample.fs.pp">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
    <None Include="sample.paket.template" />
  </ItemGroup>
  <Import Project="..\..\.paket\Paket.Restore.targets" />
</Project>
```

I basically removed that condition for `Windows_NT` and added an import for the `netfx.props` in the second line:

```xml
<Import Project="..\..\netfx.props" />
```

Now we'll try to build this project only, since it's the only one that has been fixed:

```bash
$ dotnet build src/FsUnit.NUnit/FsUnit.NUnit.fsproj
...
Build succeeded
...
```

Success! For real this time:

![Both targets built]({{ "/assets/multi_targeting_mono/both_targets_in_bin.png" }})

### FsUnit.MsTestUnit

I added the same fix there, but got the following error when trying to build:

```bash
$ dotnet build src/FsUnit.MsTestUnit/FsUnit.MsTest.fsproj
...
...
/home/atle/src/FsUnit/src/FsUnit.MsTestUnit/FsUnit.fs(14,20):
error FS1108: The type 'Exception' is required here and is
unavailable. You must add a reference to assembly 'System.Runtime,
Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'.
[/home/atle/src/FsUnit/src/FsUnit.MsTestUnit/FsUnit.MsTest.fsproj]
```

As Don Syme mentions in his comment, he had to add explicit references to some facade assemblies, `System.Runtime` is one of those, so we'll add it to `FsUnit.MsTest.fsproj` and see what happens:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <Import Project="..\..\netfx.props" />
  <PropertyGroup>
    <TargetFrameworks>netstandard2.0;net46</TargetFrameworks>
  </PropertyGroup>
  <PropertyGroup>
    <AssemblyName>FsUnit.MsTest</AssemblyName>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="AssemblyInfo.fs" />
    <Compile Include="..\FsUnit.Xunit\CustomMatchers.fs">
      <Link>CustomMatchers.fs</Link>
    </Compile>
    <Compile Include="FsUnit.fs" />
    <None Include="paket.references" />
    <None Include="paket.template" />
    <None Include="FsUnitSample.fs.pp">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
    <None Include="sample.paket.template" />
  </ItemGroup>
  <ItemGroup>
    <Reference Include="System.Runtime" />
  </ItemGroup>
  <Import Project="..\..\.paket\Paket.Restore.targets" />
</Project>
```

```bash
$ dotnet build src/FsUnit.MsTestUnit/FsUnit.MsTest.fsproj
...
Build succeeded
```

Success again!

### FsUnit.Xunit

Adding `netfx.props` and building gives a similar error message:

```bash
$ dotnet build src/FsUnit.Xunit/FsUnit.Xunit.fsproj
...
...
The type 'Exception' is required here and is unavailable. You must add a reference to assembly 'System.Runtime...'
The type 'Object' is required here and is unavailable. You must add a reference to assembly 'System.Runtime...'
```

We add the same reference as for `MsTestUnit` and build again:

```bash
$ dotnet build src/FsUnit.Xunit/FsUnit.Xunit.fsproj
...
...
The type 'TypeInfo' is required here and is unavailable. You must add a reference to assembly 'System.Reflection
```

Now we add the a reference to `System.Reflection` and build again:

```bash
$ dotnet build src/FsUnit.Xunit/FsUnit.Xunit.fsproj
...
...
Build succeeded
```

The `FsUnit.Xunit.fsproj` now looks like this:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <Import Project="..\..\netfx.props" />
  <PropertyGroup>
    <TargetFrameworks>netstandard2.0;net46</TargetFrameworks>
  </PropertyGroup>
  <PropertyGroup>
    <AssemblyName>FsUnit.Xunit</AssemblyName>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="AssemblyInfo.fs" />
    <Compile Include="CustomMatchers.fs" />
    <Compile Include="FsUnit.fs" />
    <None Include="paket.references" />
    <None Include="paket.template" />
    <None Include="FsUnitSample.fs.pp">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
    <None Include="sample.paket.template" />
  </ItemGroup>
  <ItemGroup>
    <Reference Include="System.Runtime" />
    <Reference Include="System.Reflection" />
  </ItemGroup>
  <Import Project="..\..\.paket\Paket.Restore.targets" />
</Project>
```

Finally we should run `build.sh` again, since it will build all projects and run all tests, just to make sure everything works.

```bash
Finished Target: All

---------------------------------------------------------------------
Build Time Report
---------------------------------------------------------------------
Target              Duration
------              --------
Clean               00:00:00.0449729
AssemblyInfo        00:00:00.0276845
InstallDotNetCore   00:00:00.1632733
Build               00:01:02.8727158
CopyBinaries        00:00:00.0349621
NUnit               00:00:11.8522380
xUnit               00:00:12.2566259
RunTests            00:00:00.0001697
All                 00:00:00.0000695
Total:              00:01:27.3429696
---------------------------------------------------------------------
Status:             Ok
---------------------------------------------------------------------
```

## Step 4: Submitting a PR

Now that we have made the changes to resolve the issue, we have to open a pull request to the original repository for the owner to merge. First I'll commit my changes and push my local branch to __my__ remote repository, also known as `origin`.

I find `VSCode's` git integration to be pretty good, so I usually stage files and write commit messages using it. (This shows my second commit, by the way)

![Commit]({{ "/assets/multi_targeting_mono/commit.png" }})

Then we need to push it:

```bash
$ git push origin make.multitarget.build.on.linux
```

and then you'll get a pull request button in your `fork`:

![PR button on origin]({{ "/assets/multi_targeting_mono/github_pr_button.png" }})

When pressing the `Compare & pull request` button, you will be sent to the __original repository__ for opening a PR, where you can write some details on what is done. By adding `Fixes: #IssueNr`, GitHub will automatically close the issue when the PR is closed, which is convenient.

![Commit]({{ "/assets/multi_targeting_mono/pr_on_upstream.png" }})

Now press the `Create pull request` button and your contribution is given to the owner of the repository.

And that's it! My first PR to an open source project. And you should now be able to do multi-target builds using Mono for your own projects as well.