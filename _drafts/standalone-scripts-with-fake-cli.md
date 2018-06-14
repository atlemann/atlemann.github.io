---
layout: post
title:  "Stand alone scripts with FAKE CLI"
categories: fsharp
tags: f# fsharp fsi ubuntu linux development vscode ionide mono dotnet fake
---

Is your bash-fu not cutting it? Why not create executable F# script files instead? In this post we will go through how to make executable `.fsx` scripts and how to include NuGet dependencies. We'll also be using F# interactive during development.

# Prerequisites

1. Visual Studio Code
2. Ionide extension
3. Mono
4. F# compiler
5. Paket
6. FAKE 5 CLI

# Create an F# script file

To get started with F# FSI REPL, we're going to create an F# script file with the `.fsx` extension. Opening this in VSCode+Ionide will give you intellisense, which makes everything much easier. Writing directly into F# interactive is not very intuitive.

Now go ahead and create a new file called `Script.fsx` somewhere (the name doesn't really matter). We're going to try to write some code for navigating a `.fsproj` XML file to look for e.g. which target frameworks are defined. Maybe we'll try to edit as well.

Now to start writing a parser for a project file, we need an example. Put the following example into your script file:

```fsharp
let fsprojContents = """<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <Compile Include="Library.fs" />
  </ItemGroup>

</Project>"""
```

Now you can press `Ctrl+Shift+P` and choose `FSI: Send File`. This will open an `F# interactive` pane at the bottom with something like this:

```
val fsprojContents : string =
  "<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <Tar"+[143 chars]
```

When sending things to the `FSI`, it usually cuts long values like this and writes the number of chars left, e.g. `+[143 chars]`, instead. To view the full value write the name of the variable in the FSI window followed by `;;`.

```fsharp
> fsprojContents;;
val it : string =
  "<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <Compile Include="Library.fs" />
  </ItemGroup>

</Project>"
```

## Let's code

To parse the XML we're going to use the .NET XML parser located in `System.Xml`. To make that available, simply open it at the top of your `fsx` file like any other source file. Now add something like this to create an `XmlDocument` from the `fsprojContents`.

```fsharp
open System.Xml

let fsprojContents = ...

let loadXml (text : string) =
    let doc = XmlDocument()
    doc.LoadXml text
    doc

let xml =
    loadXml fsprojContents
```

Now you can mark all the text using `Ctrl+A` and press `Alt+Enter` to send all selected text to the FSI. Now we have to try to find some XML nodes to see if we can navigate the XML.

```fsharp
let tryGetNode name (node : XmlNode) =
    let xpath = sprintf "%s" name
    match node.SelectSingleNode(xpath) with
    | null -> None
    | n -> Some(n)

let projectNode =
    xml
    |> tryGetNode "Project"

let projectNodeName =
    tryGetProjectNode
    |> Option.map (fun x -> x.Name)
```

Sending this to the FSI should print:

```
val projectNodeName : string option = Some "Project"
```

Allright! Now we'll just have to add some navigation functions to find the `TargetFramework` and/or `TargetFrameworks` nodes. It's actually supported to have them both at the same time, but then `TargetFramework` overrides the plural form.

Now we'll just add some functions for getting those nodes:

```fsharp
let tryGetNodeInPropertyGroup nodeName (node : XmlNode) =
    node
    |> tryGetNode "Project"
    |> Option.bind (tryGetNode "PropertyGroup")
    |> Option.bind (tryGetNode nodeName)

let tryGetTargetFramework (node : XmlNode) =
    node
    |> tryGetNodeInPropertyGroup "TargetFramework"

let tryGetTargetFrameworks (node : XmlNode) =
    node
    |> tryGetNodeInPropertyGroup "TargetFrameworks"

let getNodeValue (node : XmlNode) =
    node.InnerText
```

## Making the script executable

Now we're going to do something cool. We're going to make the script executable to make it into an F# bash script. This way we can test the code using the CLI. Add the following `shebang` at the top of your `.fsx` and file and the following code to get a hold of the arguments passed to the script:

```fsharp
#!/bin/sh
#if run_with_bin_sh
  exec fsharpi --exec $0 $*
#endif

/// Skip the 4 first arguments, since they are just the script file name etc.
/// [|"/usr/lib/mono/fsharp/fsi.exe"; "--exename:fsharpi"; "--exec"; "./Script.fsx"|]
let argv =
    System.Environment.GetCommandLineArgs().[4..]

// ... all the previous code goes here ...

let targetFramework =
    argv.[0]
    |> System.IO.File.ReadAllText
    |> loadXml
    |> tryGetTargetFramework
    |> Option.map getNodeValue

printfn "TargetFramework: %A" targetFramework
```

You can now make this script file executable and run it with a path to an `.fsproj` file.

```bash
$ chmod +x Script.fsx
$ ./Script.fsx some/project.fsproj
TargetFramework: netstandard2.0
```

## Changing the target frameworks

To change the target framework we need some code for updating the XML and saving it to file. We also need to take the new target framework as argument:

```fsharp
let setNodeValue value (node : XmlNode)=
    node.InnerText <- value

let readXmlDocument path =
    path
    |> System.IO.File.ReadAllText
    |> loadXml

let xmlDocument =
    readXmlDocument argv.[0]

let targetFrameworkNode =
    xmlDocument
    |> tryGetTargetFramework
    |> function
        | Some node ->
            setNodeValue argv.[1] node
            xmlDocument.Save argv.[0]
            printfn "'TargetFramework' for project '%s' changed to '%s'" argv.[0] argv.[1]
        | None ->
            printfn "Unable to find 'TargetFramework' tag"
```

The following command will now change the target framework of `project.fsproj` to `netstandard2.1`. Success!

```bash
$ ./Script.fsx some/project.fsproj netstandard2.1
'TargetFramework' for project 'some/project.fsproj' changed to 'netstandard2.1'
```

## Adding dependencies

If we want to be more fancy on the input arguments we can use [Argu](http://fsprojects.github.io/Argu/), but how can you do that in a script?

1. With the help from vanilla [Paket](https://fsprojects.github.io/Paket/)
2. With the help from [FAKE5 CLI](https://fake.build)

### Paket

If you haven't already, add the following alias to your `~/.bash_aliases` file:

```bash
alias paket='mono .paket/paket.exe'
```

Then run the following commands to get a hold of `Paket` and make it download `Argu` to a packages folder next to your script.

```bash
$ mkdir .paket
$ wget -O .paket/paket.exe https://github.com/fsprojects/Paket/releases/download/5.172.2/paket.bootstrapper.exe
$ paket init
$ paket add Argu
```

Then below the `shebang` in your script add the following to reference the library:

```fsharp
#I __SOURCE_DIRECTORY__ // Makes sure relative paths in #r statements starts from here.
#r "packages/Argu/lib/netstandard2.0/Argu.dll"

open Argu
```

This, however, is a little brittle, since it requires you to have the packages folder follow your script and all paths to be correct, so now I will show you how to make a stand alone script using `FAKE CLI` instead.

### FAKE CLI

First you have to install `FAKE CLI` as a global dotnet tool:

```bash
$ dotnet tool install fake-cli -g
```

Now you have `fake` as a command line tool which has a special `Paket` integration using some special `#r` statements. Now we'll change two things, first the `shebang` to invoke `fake cli` instead of `fsi` and add `Argu` via the special `#r` syntax. So replace the top of your script file from

```fsharp
#!/bin/sh
#if run_with_bin_sh
  exec fsharpi --exec $0 $*
#endif

#I __SOURCE_DIRECTORY__
#r "packages/Argu/lib/netstandard2.0/Argu.dll"

open Argu

let argv =
    Environment.GetCommandLineArgs().[4..]
```

to

```fsharp
#!/bin/sh
#if run_with_bin_sh
  exec fake run $0 $*
#endif

#r "paket:
nuget Argu
//"

// Make sure to match the name of your script file, since
// FAKE CLI creates a .fake/{script_name}.fsx folder next to this script
#load "./.fake/Script.fsx/intellisense.fsx"

open Argu

let argv =
    Environment.GetCommandLineArgs().[3..]
```

Now we can use `Argu` to parse our command line arguments by adding something like this at the bottom of our script:

```fsharp
type Arguments =
    | [<Mandatory;CustomCommandLine("change")>] ProjectPath of ProjectPath:string
    | [<Mandatory;CustomCommandLine("targetframework")>] TargetFramework of TargetFramework:string
with
    interface IArgParserTemplate with
        member s.Usage =
            match s with
            | ProjectPath _ -> "specify the project file to update"
            | TargetFramework _ -> "specify the target framework to set"

let errorHandler =
        ProcessExiter(colorizer =
            function
            | ErrorCode.HelpText -> None
            | _ -> Some System.ConsoleColor.Red)

let argsParser =
    ArgumentParser.Create<Arguments>(programName = "./Script.fsx", errorHandler = errorHandler)

let args =
    argsParser.Parse argv

if args.GetAllResults() |> List.length <> 2 then
    argsParser.PrintUsage()
    |> printfn "%s"
    1
else
    let projectPath =
        args.GetResult (<@ ProjectPath @>)

    let targetFramework =
        args.GetResult (<@ TargetFramework @>)

    let xmlDocument =
        projectPath
        |> readXmlDocument

    xmlDocument
    |> tryGetTargetFramework
    |> function
        | Some n ->
            setNodeValue targetFramework n
            xmlDocument.Save projectPath
            printfn "'TargetFramework' for project '%s' changed to '%s'" projectPath targetFramework
            0
        | None ->
            printfn "Unable to find 'TargetFramework' tag"
            1
```

Now we have an argument list that resembles `dotnet CLI` and has a nice help:

```bash
$ ./Script.fsx
ERROR: missing parameter 'change'.
USAGE: ./Script.fsx [--help] change <ProjectPath> targetframework <TargetFramework>

OPTIONS:

    change <ProjectPath>  specify the project file to update
    targetframework <TargetFramework>
                          specify the target framework to set
    --help                display this list of options.
```

So we try again with proper arguments:

```bash
$ ./Script.fsx change some/Project.fsproj targetframework net461
'TargetFramework' for project 'some/project.fsproj' changed to 'netstandard2.1'
```

And if you have a bunch of project files you want to update you can leverage bash like this:

```bash
$ find . -name "*.fsproj" -type f -exec ./Script.fsx change {} targetframework net461 \;
```

where `{}` is the placeholder for the `find` command's results and `\;` means it invokes the script with a single result at a time.