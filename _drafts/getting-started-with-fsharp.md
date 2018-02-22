---
layout: post
title:  "Getting started with F#"
date:   2018-02-22 20:55:44 +0100
categories: fsharp
tags: f# fsharp ubuntu linux development vscode ionide mono dotnet
---

Now that we have set up our development environment, it's about time to get started with the coding. In this post we are going to get to know different ways of creating a new F# project from scratch.

# Step 1: Creating a project

The first thing you'll have to do is to create an F# project. We're doing to look at two different ways to do this:

1. [Forge](http://forge.run) via [Ionide](http://ionide.io)
2. dotnet CLI

## Ionide

The first thing you'll have to do is to create a root folder for your new project and open `VSCode` in that folder:

    $ cd ~/src
    $ mkdir MyProject
    $ code MyProject

Now you're going to see a very emtpy `VSCode` instance without anything in it. Now, to create your project, hit `Ctrl+Shift+P` and start typing `new project`.

![F#: New Project]({{ "/assets/gettingstarted/newproject.png" }})


## Dotnet CLI

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

# Step 2: Adding tests project

# Step 3: Creating a solution file

# Step 4: Adding F# files

# Step 5: Adding NuGet references 

