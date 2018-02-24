---
layout: post
title:  "Getting started with F# in VSCode"
date:   2018-02-22 20:55:44 +0100
categories: fsharp
tags: f# fsharp ubuntu linux development vscode ionide mono dotnet
---

Now that we have set up our development environment, it's about time to get started with the coding. In this post we are going to get to know different ways of creating a new F# project from scratch.

Tools for working with .NET projects:

1. [Forge](http://forge.run) via [Ionide](http://ionide.io)
2. dotnet CLI
3. By hand ;)


## Creating a project

The first thing you'll have to do is to create an F# project.


### With Ionide

The first thing you'll have to do is to create a root folder for your new project and open `VSCode` in that folder:

    $ cd ~/src
    $ mkdir MyProject
    $ code MyProject

Now you're going to see a very emtpy `VSCode` instance without anything in it. Now, to create your project, hit `Ctrl+Shift+P` and start typing `new project`.

![F#: New Project]({{ "/assets/gettingstarted/newproject.png" }})

### With dotnet CLI

Again, create the root folder for your new project and open `VSCode`.

    $ cd ~/src
    $ mkdir MyProject
    $ code MyProject

Now hit ``Ctrl+` `` to open the integrated terminal, which is a great way to keep your CLI and code in the same window. Now check out which templates you have installed by typing:

    $ dotnet new
    ...
    Templates                                         Short Name       Language          Tags
    ----------------------------------------------------------------------------------------------------------------------------
    Console Application                               console          [C#], F#, VB      Common/Console
    Class library                                     classlib         [C#], F#, VB      Common/Library
    SAFE-Stack Web App v0.4.0                         SAFE             F#                F#/Web/Suave/Fable/Elmish/Giraffe/Bulma
    Simple Fable App                                  fable            F#                Fable
    Unit Test Project                                 mstest           [C#], F#, VB      Test/MSTest
    xUnit Test Project                                xunit            [C#], F#, VB      Test/xUnit
    ASP.NET Core Empty                                web              [C#], F#          Web/Empty
    ASP.NET Core Web App (Model-View-Controller)      mvc              [C#], F#          Web/MVC
    ASP.NET Core Web App                              razor            [C#]              Web/MVC/Razor Pages
    ASP.NET Core with Angular                         angular          [C#]              Web/MVC/SPA
    ASP.NET Core with React.js                        react            [C#]              Web/MVC/SPA
    ASP.NET Core with React.js and Redux              reactredux       [C#]              Web/MVC/SPA
    ASP.NET Core Web API                              webapi           [C#], F#          Web/WebAPI
    global.json file                                  globaljson                         Config
    NuGet Config                                      nugetconfig                        Config
    Web Config                                        webconfig                          Config
    Solution File                                     sln                                Solution
    Razor Page                                        page                               Web/ASP.NET
    MVC ViewImports                                   viewimports                        Web/ASP.NET
    MVC ViewStart                                     viewstart                          Web/ASP.NET
    ...

We're going to create an `F# Console Application` by typing:

    $ dotnet new console -lang F# -o src/MyConsoleApp

This will create the following tree of files:

![Console app files]({{ "/assets/gettingstarted/dotnet_new_console_files.png" }})

Now go ahead and run it by typing:

    $ dotnet run --project src/MyConsoleApp/MyConsoleApp.fsproj
    Hello World from F#!

Next we're going to create a library project we can use from our awesome console app.

    $ dotnet new classlib -lang F# -o src/MyLibrary
    The template "Class library" was created successfully.

and your files tree should now look like this:

![Class lib files]({{ "/assets/gettingstarted/with_class_lib_files.png" }})

## Adding project reference

### By hand

With the new MSBuild SDK, it's actually possible to edit `.*proj` files by hand. Now add a `<ProjectReference>` to your `MyLibrary.fsproj` in your `MyConsoleApp.fsproj`, which will now look like this:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
      <OutputType>Exe</OutputType>
      <TargetFramework>netcoreapp2.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
      <Compile Include="Program.fs" />
  </ItemGroup>

  <ItemGroup>
      <ProjectReference Include="..\MyLibrary\MyLibrary.fsproj" />
  </ItemGroup>

</Project>
```

### With Ionide

### With dotnet CLI

To use this library in the console app, we have to reference it. `dotnet CLI` has a command for this which works like this:

    dotnet add <ProjectToAddReferenceTo> reference <ProjectToReference>

So in our case we will run the following from the root directory:

    $ dotnet add src/MyConsoleApp/MyConsoleApp.fsproj reference src/MyLibrary/MyLibrary.fsproj
    Reference `..\MyLibrary\MyLibrary.fsproj` added to the project.

## Adding NuGet reference

Now we're going to add an arguments parser to our console app from NuGet. The goto arguments parser for F# is [Argu](https://fsprojects.github.io/Argu/).

### By hand

Again, with the new MSBuild SDK, adding a NuGet package is as simple as adding a `<PackageReference>` to `Argu` in your `MyConsoleApp.fsproj`, which will now look like this:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>netcoreapp2.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <Compile Include="Program.fs" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\MyLibrary\MyLibrary.fsproj" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="Argu" Version="5.0.1" />
  </ItemGroup>

</Project>
```

Now do a `$ dotnet restore src/MyConsoleApp/MyConsoleApp.fsproj`. If you are getting a warning like `Detected package downgrade: FSharp.Core`, add a `<PackageReference>` to `FSharp.Core` in the same `<ItemGroup>` as `Argu`, matching at least the minumum version required by `Argu`:

```xml
  <ItemGroup>
    <PackageReference Include="FSharp.Core" Version="4.3.2" />
    <PackageReference Include="Argu" Version="5.0.1" />
  </ItemGroup>
```

### With dotnet CLI

`dotnet CLI` has a command for installing NuGet packages which looks like this:

```bash
$ dotnet add <ProjectToAddNuGetTo> package <NuGetPackageId>
```

So to add `Argu` to our console app we just type:

```bash
$ dotnet add src/MyConsoleApp/MyConsoleApp.fsproj package Argu
```

To fix the potential `Detected package downgrade: FSharp.Core` issue, you should in theory just run `$ dotnet add src/MyConsoleApp/MyConsoleApp.fsproj package FSharp.Core`, however, for me it fails with an error. So you'll have to add `FSharp.Core` by hand in the `MyConsoleApp.fsproj` file as mentioned above or switch to `Paket` as explained below.

### With Paket

Paket is an F# community open source package manager which fixes a lot of the issues NuGet has, e.g. global `paket.dependencies` and `paket.lock` files which globally defines which packages and versions are to be used and much more. First, download the [paket.bootstrapper.exe](https://github.com/fsprojects/Paket/releases/latest) and save it as `<SolutionFolder>/.paket/paket.exe` (yes, you are renaming it. See [here](https://fsprojects.github.io/Paket/bootstrapper.html) for more info). To initialize `Paket` type the following:

If you haven't already added any packages, run the following to get started with Paket and add the `Argu` package to the `MyConsoleApp` project:

```bash
$ mono .paket/paket.exe init
$ mono .paket/paket.exe add --project src/MyConsoleApp/MyConsoleApp.fsproj Argu
```

If you're already using NuGet and want to switch to Paket, run the following command and Paket will figure out which NuGet packages you are using and initialize itself accordingly:

```bash
$ mono .paket/paket.exe convert-from-nuget
```

Paket won't give you the `Detected package downgrade: FSharp.Core` issue mentioned above, since it, by default, resolves the higest versions of transient dependencies, unlike `NuGet` which does the opposite. Paket also automatically hooks into `dotnet restore`, so you won't have to do `mono .paket/paket.exe restore` to restore your packages when using Paket with `dotnet CLI`.

## Running your Application

Now that we have added a reference to the class library, we can try to use it. Open `Program.fs` and `Library.fs` and change the code to something like this:

![Class lib files]({{ "/assets/gettingstarted/using_classlib.png" }})

### With Ionide

### With dotnet CLI

    $ dotnet run -p src/MyConsoleApp/MyConsoleApp.fsproj Scott
    Hello Scott

### With VSCode

Press `F5` and you will see the following menu popping up where you should select `.NET Core`:

![Select run environment]({{ "/assets/gettingstarted/select_run_environment.png" }})

This will create a folder called `.vscode` with a file called `launch.json` with the following content (and then some).

```json
"version": "0.2.0",
    "configurations": [
        {
            "name": ".NET Core Launch (console)",
            "type": "coreclr",
            "request": "launch",
            "preLaunchTask": "build",
            "program": "${workspaceFolder}/bin/Debug/<insert-target-framework-here>/<insert-project-name-here>.dll",
            "args": ["Scott"],
            "cwd": "${workspaceFolder}",
            "console": "internalConsole",
            "stopAtEntry": false,
            "internalConsoleOptions": "openOnSessionStart"
        },
```

You'll have to add `/src/MyConsoleApp` and edit the `<insert-target-framework-here>` and `<insert-project-name-here>` to the target framework in the `MyConsoleApp.fsproj` file and the name of the console app dll itself. To get the same output as above, add `Scott` to the `args` entry :

```json
"program": "${workspaceFolder}/src/MyConsoleApp/bin/Debug/netcoreapp2.0/MyConsoleApp.dll",
"args": ["Scott"],
```

Press `F5` again and you will get the following popup:

![Tasks.json step1]({{ "/assets/gettingstarted/tasks_json_step1.png" }})

Choose `Configure Task` and VSCode will show you the following:

![Tasks.json step2]({{ "/assets/gettingstarted/tasks_json_step2.png" }})

Just press enter, since there is only one option, and in the following menu, choose `.NET Core`.

![Tasks.json step3]({{ "/assets/gettingstarted/tasks_json_step3.png" }})

This will create a `tasks.json` file next to the `launch.json` file in the `.vscode` folder, looking like this:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "command": "dotnet build",
            "type": "shell",
            "group": "build",
            "presentation": {
                "reveal": "silent"
            },
            "problemMatcher": "$msCompile"
        }
    ]
}
```

If you try to hit `F5` again now, the build will fail, since there is no project defined. To fix this, add the `MyConsoleApp.fsproj` to the `command`:

```json
"command": "dotnet build src/MyConsoleApp/MyConsoleApp.fsproj",
```

Now you should be able to press `F5` and see the following in the built-in terminal:

![Run with VSCode result]({{ "/assets/gettingstarted/run_with_vscode_result.png" }})

If you like buttons, you could also go to the `Debug` pane in `VSCode` which now will list all configs in the `launch.json` file (which you can open by pressing that cogwheel) and press the green play button:

![Run with VSCode result]({{ "/assets/gettingstarted/debug_by_pressing_play.png" }})

Now you can set breakpoints in your code and debug your (maybe first) .NET Core F# project in VSCode. How cool is that!

![Run with VSCode result]({{ "/assets/gettingstarted/debugging_play_button.png" }})

## Adding tests project

In F#, [Expecto](https://github.com/haf/expecto) is the goto project for unit-testing. There are two ways to set up a testing project using `Expecto`. By hand or by dotnet CLI template.

### With dotnet CLI

First you need to create a console app, since Expecto is just a library that you can run from console. The second thing you'll have to do is to add the `Expecto NuGet` package.

```bash
$ dotnet new console -lang F# -o tests/MyTests
$ dotnet add tests/MyTests/MyTests.fsproj package Expecto
$ dotnet restore tests/MyTests/MyTests.fsproj
```

Replace the contents of `Program.fs` with the following:

```fsharp
open Expecto

[<EntryPoint>]
let main argv =
    Tests.runTestsInAssembly defaultConfig argv
```

### With dotnet CLI template

As you saw earlier, `dotnet new` did not show any template for `Expecto`, however, someone has created this for us. To install it type the following:

```bash
$ dotnet new -i Expecto.Template::*
...
...
Templates                                         Short Name       Language          Tags
----------------------------------------------------------------------------------------------------------------------------
Console Application                               console          [C#], F#, VB      Common/Console
Class library                                     classlib         [C#], F#, VB      Common/Library
SAFE-Stack Web App v0.4.0                         SAFE             F#                F#/Web/Suave/Fable/Elmish/Giraffe/Bulma
Simple Fable App                                  fable            F#                Fable
Expecto .net core Template                        expecto          F#                Test
Unit Test Project                                 mstest           [C#], F#, VB      Test/MSTest
xUnit Test Project                                xunit            [C#], F#, VB      Test/xUnit
ASP.NET Core Empty                                web              [C#], F#          Web/Empty
ASP.NET Core Web App (Model-View-Controller)      mvc              [C#], F#          Web/MVC
ASP.NET Core Web App                              razor            [C#]              Web/MVC/Razor Pages
ASP.NET Core with Angular                         angular          [C#]              Web/MVC/SPA
ASP.NET Core with React.js                        react            [C#]              Web/MVC/SPA
ASP.NET Core with React.js and Redux              reactredux       [C#]              Web/MVC/SPA
ASP.NET Core Web API                              webapi           [C#], F#          Web/WebAPI
global.json file                                  globaljson                         Config
NuGet Config                                      nugetconfig                        Config
Web Config                                        webconfig                          Config
Solution File                                     sln                                Solution
Razor Page                                        page                               Web/ASP.NET
MVC ViewImports                                   viewimports                        Web/ASP.NET
MVC ViewStart
```

Now you'll se a new template called `Expecto .net core Template` that we will create by typing:

```bash
$ dotnet new expecto -o tests/MyTests
```

Your tree will now look like this:

![Run with VSCode result]({{ "/assets/gettingstarted/file_tree_with_expecto.png" }})

## Running tests

### Dotnet CLI

### Ionide

# Step 3: Creating a solution file

# Step 4: Adding F# files

# Step 5: Adding NuGet references 

## Now go read this

* [Argu command line parser](https://fsprojects.github.io/Argu/)
* [Expecto F# unit-test library](https://github.com/haf/expecto)
* [Paket package manager](https://fsprojects.github.io/Paket/)
* [Paket intro](https://forki.github.io/PaketIntro/#/)
* [Getting started with Paket](https://cockneycoder.wordpress.com/2017/08/07/getting-started-with-paket-part-1/)
* [FAKE - Build scripting in F#](http://fake.build)
