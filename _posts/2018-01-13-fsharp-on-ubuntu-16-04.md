---
layout: post
title:  "F# on Ubuntu 16.04 from scratch"
date:   2018-01-13 20:55:44 +0100
categories: fsharp
tags: f# fsharp ubuntu linux development vscode ionide mono dotnet
---

I am a little late to the party, but here is how you can set up a full development environment for F# on .NET Core.

# TL;DR

    $ git clone https://github.com/atlemann/installscripts.git
    $ cd installscripts
    $ ./install-fsharp-devenv.sh

Go hack!

## Requirements

* [Mono](http://www.mono-project.com/download/#download-lin) (for tooling and multi targeting)
* [FSharp compiler](http://fsharp.org/use/linux/)
* [.NET Core CLI](https://www.microsoft.com/net/learn/get-started/linuxubuntu)
* [Visual Studio Code](https://code.visualstudio.com/Download)
* [Ionide](http://ionide.io) VSCode extension

## Installing the FSharp compiler and Mono

    $ sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys $ 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
    $ echo "deb http://download.mono-project.com/repo/ubuntu xenial main" | sudo tee $ /etc/apt/sources.list.d/mono-official.list
    $ sudo apt-get update
    $ sudo apt-get install fsharp

## Installing .NET Core on the system

    $ curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    $ sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
    $ sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-xenial-prod xenial main" > /etc/apt/sources.list.d/dotnetdev.list'
    $ sudo apt-get update
    $ sudo apt-get install dotnet-sdk-2.1.4

Make sure to install a dotnet SDK version > `2.0.0` to support resolving NuGet pre-release packages, which use SemVer v2, e.g. `1.2.3-beta.4`.

## Now test the CLI

To get started with .NET Core, simply use a dotnet CLI provided template. To list the available templates, simply write

    $ dotnet new

and to create an F# console app and start coding, write

    $ dotnet new console -lang F# -o ~/src/FSharpConsole
    $ cd ~/src/FSharpConsole
    $ dotnet run
    Hello World from F#!

Now you can check the .fsproj file and see it targeting `netcoreapp2.0`.

## Installing Visual Studio Code

Since we have already added the microsoft gpg key when installing the `dotnet sdk`, we only have to add the vscode repository to our sources list before installing the package:

    $ sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
    $ sudo apt-get update
    $ sudo apt-get install code

## Adding the Ionide-fsharp extension

The Ionide-fsharp extension to VSCode gives you a better experience when working with F#. Install it like this:

    $ code --install-extension Ionide.Ionide-fsharp

## Font ligatures

Since programming in F# uses a lot of multi character symbols, many people like to use fonts with programming ligatures to make those symbols a single symbol instead. E.g. [FiraCode](https://github.com/tonsky/FiraCode).

    $ curl -fsSL https://github.com/tonsky/FiraCode/releases/download/1.204/FiraCode_1.204.zip -o firacode.zip
    $ unzip firacode.zip -d firacode
    $ mkdir -p /usr/local/share/fonts/firacode
    $ sudo cp firacode/ttf/*.ttf /usr/local/share/fonts/firacode
    $ sudo fc-cache -fv

Now open VSCode and edit the `settings.json` file by hitting `Ctrl+,` and paste the following content:

    "editor.fontFamily": "Fira Code",
    "editor.fontSize": 14,
    "editor.fontLigatures": true

## Setting up Git branch info in terminal

One helpful trick when using Git is to show the current branch and status in the bash prompt whenever you are inside a folder with a git repository. The Git source code contains a script which can be used to show this information. To set it up, first fetch the [git-prompt.sh](https://github.com/git/git/blob/master/contrib/completion/git-prompt.sh) script:

    $ curl -fsSL https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh -o .git-prompt.sh

Then open `~/.bashrc` in your favorite editor and add the following at the bottom:

    # Git branch info in terminal prompt
    . ~/.git-prompt.sh
    export GIT_PS1_SHOWDIRTYSTATE=1
    export GIT_PS1_SHOWCOLORHINTS=true
    export PROMPT_COMMAND='__git_ps1 "\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]" "\\\$ "'

There are some additional environment variables that can be set which are explained in `.git-prompt.sh`

## Use .NET Core from a docker

The .NET Core SDK has been coming out in previews before the final release of a new version. To try out a new preview without removing a stable version, .NET Core supports different versions installed side-by-side. However, you now have to do some trickery to choose which version to use. [Fanie Reynders](https://reynders.co/use-this-helper-cli-for-switching-net-core-sdk-versions/) has created some nice scripts to do this and Scott Hansleman has [elaborated](https://www.hanselman.com/blog/dotnetSdkListAndDotnetSdkLatest.aspx) on how to use it.

Another approach is to use docker containers for running our dotnet CLI commands. This way, new previews can be tried out without installing them on your machine. We actually don't have to install .NET Core on our machine at all. And as an added bonus, you will be making sure your code will work inside a Docker container.

First install [docker](https://github.com/docker/docker-install) by running the following commands:

    $ sudo apt-get install curl
    $ curl -fsSL get.docker.com -o get-docker.sh
    $ sh get-docker.sh

Then pull the latest .NET Core image from [docker hub](https://hub.docker.com/r/microsoft/dotnet/). Now we can pull the `latest` tag to get the most up to date dotnet SDK. We will also pull the v.1 SDK just to show how this will work.

    $ docker pull microsoft/dotnet:1-sdk
    $ docker pull microsoft/dotnet:latest

Now, since aliases are too old-school, we are going to set up some bash functions to be able to work with the .NET Core dockers from the CLI. Add the following content to `~/.bash_aliases`:

    dotnet2() {
        docker run --rm -it -v $(pwd):/src -w /src microsoft/dotnet:latest dotnet "$@"
    }
    dotnet1() {
        docker run --rm -it -v $(pwd):/src -w /src microsoft/dotnet:1-sdk dotnet "$@"
    }

Dockers require sudo access unless the current user is a member of the `docker` group. There are some security implications doing this described [here](https://askubuntu.com/questions/477551/how-can-i-use-docker-without-sudo#477554).

To add a user to the docker group (and refreshing the groups without logging out and in again), type

    $ sudo usermod -aG docker $USER
    $ newgrp docker

Now from the command line we can just write this:

    $ dotnet2 --version
    2.1.4
    $ dotnet1 --version
    1.0.4

So, if a `3.0-preview` will be released at some point, we could pull this image by its tag and try it out without installing it on our system.

## Other resources

* [Use F# on Linux](http://fsharp.org/use/linux/)
* [Cross-Platform Development with F#](http://fsharp.org/guides/mac-linux-cross-platform/)
* [From A to F#](https://dotnetcoretutorials.com/2017/07/08/from-a-to-f-part-i/)