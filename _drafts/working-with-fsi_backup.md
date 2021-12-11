---
layout: post
title:  "Working with FSI"
categories: fsharp
tags: f# fsharp fsi ubuntu linux development vscode ionide mono dotnet
---

This post will show how to use FSI for coding F# by request from [@buse1995](https://twitter.com/bluse1995/status/969844613052882944?s=20). We're going to try to parse .fsproj files in the new MSBuild Sdk format and try to inject a tag for importing the multi-targeting setup from the previous post.

# Prerequisites

1. Visual Studio Code
2. Ionide extension
3. F# compiler
4. Dotnet CLI

# Create an F# script file

To get started with F# FSI REPL, we're going to create an F# script file with the `.fsx` extension. Opening this in VSCode+Ionide will give you intellisense, which makes everything much easier. Writing directly into F# interactive is not very intuitive.

Now go ahead and create a new file called `Script.fsx` somewhere (the name doesn't really matter). We're going to try to write some code for navigating a `.fsproj` XML file to look for the multi-targeting import tag from my previous blog post and add it if it's not there.

Now to start writing a parser for a project file, we need an example:

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
    projectNode
    |> Option.map (fun x -> x.Name)
```

Sending this to the FSI should print:

```
val projectNodeName : string option = Some "Project"
```

Awesome! We can now start to move the code to the library project.

# Simple scaffolding

If you haven't already, add the following alias to your `~/.bash_aliases` file:

```bash
alias paket='mono .paket/paket.exe'
```

Then run the following commands to scaffold a library and test project and move your `.fsx` file into the `src/` folder.

```bash
$ mkdir MultiTargeter
$ cd MultiTargeter
$ mkdir .paket
$ wget -O .paket/paket.exe https://github.com/fsprojects/Paket/releases/download/5.155.0/paket.bootstrapper.exe
$ dotnet new classlib -lang F# -o src/MultiTargeter
$ dotnet new console -lang F# -o tests/MultiTargeter.Tests
$ dotnet add tests/MultiTargeter.Tests/MultiTargeter.Tests.fsproj reference src/MultiTargeter/MultiTargeter.fsproj
$ paket add -p tests/MultiTargeter.Tests/MultiTargeter.Tests.fsproj Expecto
$ paket add -p tests/MultiTargeter.Tests/MultiTargeter.Tests.fsproj Microsoft.NET.Test.Sdk
$ paket add -p tests/MultiTargeter.Tests/MultiTargeter.Tests.fsproj YoloDev.Expecto.TestSdk
$ mv {path/toyour/script/file.fsx} src/
$ dotnet new sln -n MultiTargeter
$ dotnet sln add **/**/*.fsproj
$ code .
```

Now replace the contents of `tests/MultiTargeter.Tests/Program.fs` with:

```fsharp
open Expecto

[<EntryPoint>]
let main argv =
    Tests.runTestsInAssembly defaultConfig argv
```

# Start to move code to library

Create a new file called `Xml.fs` in the `src/MultiTargeter` project and move the XML parsing functions there:

```fsharp
module MultiTargeter.Xml

open System.Xml

let [<Literal>] ProjectTag = "Project"

let [<Literal>] ImportTag = "Import"

let loadXml (text : string) =
    let doc = XmlDocument()
    doc.LoadXml text
    doc

let tryGetNode name (node : XmlNode) =
    let xpath = sprintf "%s" name
    match node.SelectSingleNode(xpath) with
    | null -> None
    | n -> Some(n)

let tryGetProjectNode (doc : XmlNode) =
    doc |> tryGetNode ProjectTag

let tryGetImportNode (doc : XmlNode) =
    doc |> tryGetNode ImportTag
```

Now add a tests file to the tests project with the following content:

```fsharp
module MultiTargeter.Tests

open Expecto
open Expecto.Flip
open MultiTargeter.Xml

let fsprojContentsWithoutImportNode = """<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <Compile Include="Library.fs" />
  </ItemGroup>

</Project>"""

let fsprojContentsWithImportNode = """<Project Sdk="Microsoft.NET.Sdk">
  <Import Project="..\..\netfx.props" />
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <Compile Include="Library.fs" />
  </ItemGroup>

</Project>"""


[<Tests>]
let testsWithoutImportNode =

    let doc =
        loadXml fsprojContentsWithoutImportNode

    testList "Project file without the Import node" [
        test "Get Project node returns Some" {
            doc
            |> tryGetProjectNode
            |> Expect.isSome "Expected to find Project node"
        }

        test "Get Import node returns None" {
            doc
            |> tryGetProjectNode
            |> Option.bind tryGetImportNode
            |> Expect.isNone "Expected not to find Import node"
        }
    ]

[<Tests>]
let testsWithImportNode =

    let doc =
        loadXml fsprojContentsWithImportNode

    testList "Project file with the Import node" [
        test "Get Project node returns Some" {
            doc
            |> tryGetProjectNode
            |> Expect.isSome "Expected to find Project node"
        }

        test "Get Import node returns Some" {
            doc
            |> tryGetProjectNode
            |> Option.bind tryGetImportNode
            |> Expect.isSome "Expected to find Import node"
        }
    ]
```

Now you can run

```bash
$ dotnet test
```

to build and run the tests. Now we're all set to continue scripting. At the top of your script file you can now add the following to load the code from the `Xml.fs` file into your `.fsx` file:

```fsharp
#load "MultiTargeter/Xml.fs"

open MultiTargeter.Xml
```

Next we want to get the attributes of an XML node, so we try to create a function for getting that in our `.fsx` file, e.g.:

```fsharp
let tryGetAttribute name (node : XmlNode) =
    let tryFindAttribute attributes =
        attributes 
        |> Seq.cast<XmlAttribute> 
        |> Seq.tryFind (fun a -> a.Name = name && not <| isNull a.Value) 
        |> Option.map (fun a -> a.Value)

    node
    |> Option.ofObj
    |> Option.bind (fun n -> n.Attributes |> Option.ofObj)
    |> Option.bind tryFindAttribute
```

and since the attribute we are looking for in the `Import` tag is `Project`, we can add a convenience function for getting that and combine it with traversing the XML:

```fsharp
let tryGetImportTagAttribute (doc : XmlNode) =
    doc |> tryGetAttribute "Project"

let tryGetProjectImportAttribute : (XmlNode -> string option) =
    tryGetProjectNode
    >> Option.bind tryGetImportNode
    >> Option.bind tryGetImportTagAttribute

let importAttribute =
    fsprojContents
    |> loadXml
    |> tryGetProjectImportAttribute
```

Now you can select all the new code and press `Alt+Enter` and F# interactive should end up with

```
val importAttribute : string option = None
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
let args =
    System.Environment.GetCommandLineArgs().[4..]

#load "MultiTargeter/Xml.fs"

open MultiTargeter.Xml

let importAttribute =
    args.[0]
    |> System.IO.File.ReadAllText
    |> loadXml
    |> tryGetProjectImportAttribute

printfn "Attribute: %A" importAttribute
```

With this `Script.fsx` file (if all the previously defined functions have been moved to `XML.fs`) you can now make it executable and run it with a path to an `.fsproj` file.

```bash
$ chmod +x Script.fsx
$ ./Script.fsx MultiTargeter/MultiTargeter.fsproj
Attribute: <null>
```