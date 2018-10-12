---
layout: post
title:  "SAFE stack on Ubuntu 18.04 from scratch"
categories: fsharp
tags: f# fsharp ubuntu linux development vscode ionide mono dotnet safe saturn giraffe suave elmish yarn nodejs code
---

Now that a new Ubuntu LTS has been available for a while, it's about time to set it up for F# and this time some [SAFE stack](https://safe-stack.github.io) development as well.

# Requirements

For F#, we need:

* [Mono](http://www.mono-project.com/download/#download-lin) (required by [Paket](https://fsprojects.github.io/Paket/) and F# interactive [FSI/REPL](https://repl.it/site/languages/fsharp))
* [F# compiler](http://fsharp.org/use/linux/)
* [dotnet CLI](https://www.microsoft.com/net/learn/get-started/linuxubuntu)
* [Visual Studio Code](https://code.visualstudio.com)
* [Ionide](http://ionide.io) VSCode extension
* [A cool font](https://github.com/tonsky/FiraCode) to make the F# pipe operator `|>` look like a triangle

For working with [Fable](http://fable.io) we also need:

* [Yarn](https://yarnpkg.com/en/docs/install#debian-stable)
* [Node](https://nodejs.org/en/download/)

## Adding repositories

Since `curl` is not installed by default, we start with that:

```bash
sudo apt-get -y install curl
```

Then we can add all the required repositories:

```bash
# dotnet core sdk
wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb

# VSCode
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'

# Mono
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
echo "deb https://download.mono-project.com/repo/ubuntu stable-bionic main" | sudo tee /etc/apt/sources.list.d/mono-official-stable.list

# Yarn
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

# Node
curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
```

## Installing everything

Due to [this issue](https://github.com/yarnpkg/yarn/issues/2821) with `Yarn`, we first have to remove the `cmdtest` package before installing `Yarn`:

```bash
sudo apt-get remove cmdtest
```

Then we can install all the things!

```bash
sudo apt-get -y install apt-transport-https
sudo apt-get update
sudo apt-get -y install fsharp dotnet-sdk-2.1 code fonts-firacode yarn nodejs
```

If you want to keep your `dotnet CLI` up to date, install the `dotnet-sdk-2.1` package, since it installs the newest available `dotnet-sdk-2.1.xxx` version when running `apt-get upgrade`. To only install specific versions (which can be installed side-by-side) install the specific `dotnet-sdk-2.1.xxx` package you want instead.

You can check which versions of the SDK you have installed by running:

```text
$ dotnet --info
.NET Core SDK (reflecting any global.json):
 Version:   2.1.403
 Commit:    04e15494b6

Runtime Environment:
 OS Name:     ubuntu
 OS Version:  18.04
 OS Platform: Linux
 RID:         ubuntu.18.04-x64
 Base Path:   /usr/share/dotnet/sdk/2.1.403/

Host (useful for support):
  Version: 2.1.5
  Commit:  290303f510

.NET Core SDKs installed:
  2.1.105 [/usr/share/dotnet/sdk]
  2.1.200 [/usr/share/dotnet/sdk]
  2.1.403 [/usr/share/dotnet/sdk]

.NET Core runtimes installed:
  Microsoft.AspNetCore.All 2.1.5 [/usr/share/dotnet/shared/Microsoft.AspNetCore.All]
  Microsoft.AspNetCore.App 2.1.5 [/usr/share/dotnet/shared/Microsoft.AspNetCore.App]
  Microsoft.NETCore.App 2.0.7 [/usr/share/dotnet/shared/Microsoft.NETCore.App]
  Microsoft.NETCore.App 2.1.5 [/usr/share/dotnet/shared/Microsoft.NETCore.App]

To install additional .NET Core runtimes or SDKs:
  https://aka.ms/dotnet-download
```

## Setting up VSCode

First we want to install some extensions for F# development:

```bash
code --install-extension Ionide.ionide-fsharp
code --install-extension Ionide.ionide-Paket
code --install-extension Ionide.ionide-FAKE
code --install-extension ms-vscode.csharp
code --install-extension donjayamanne.githistory
code --install-extension github.vscode-pull-request-github
```

The `ms-vscode.csharp` extension is to add debugging support when working in VSCode. `donjayamanne.githistory` gives you a nice view of the Git log and visual commit graph among other things. `github.vscode-pull-request-github` gives you a list of PRs straight into VSCode. It is still in preview, but already has a lot of useful stuff it can do.

Next we want to enable the `Fira code font` and make `Ionide` use `netcore` instead of `mono`. You might want to add this to a file and execute it or you can try to copy/paste into a terminal. Or just open `VSCode` and press `Ctrl+,` and paste the settings in there.

```bash
folder="$HOME/.config/Code/User"
file="$folder/settings.json"

mkdir -p $folder
cat >> $file <<EOF
{
    "editor.fontLigatures": true,
    "editor.fontFamily": "Fira Code",
    "editor.fontSize": 14,
    "FSharp.fsacRuntime": "netcore"
}
EOF
```

## Setting up Git branch info in terminal

I still like to have the Git branch and status shown in the bash prompt when I'm inside folder with a git repository. The current branch appears inside parentheses like this:

```bash
me@mycomputer:~/src/mygitrepo (my-feature-branch)$
```

The Git source code contains a script which can be used to show this information. To set it up, first fetch the [git-prompt.sh](https://github.com/git/git/blob/master/contrib/completion/git-prompt.sh) script:

```bash
curl -fsSL https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh -o .git-prompt.sh
```

Then open `~/.bashrc` in your favorite editor and add the following at the bottom:

```bash
# Git branch info in terminal prompt
. ~/.git-prompt.sh
export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWCOLORHINTS=true
export PROMPT_COMMAND='__git_ps1 "\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]" "\\\$ "'
```

There are some additional environment variables that can be set which are explained in `.git-prompt.sh`

## Adding some Git aliases for less typing

It can become a bit cumbersome to write the whole Git commands all the time, so adding a few aliases for the most common ones is a good idea. Write the following in a shell:

```bash
git config --global alias.co checkout
git config --global alias.cob "checkout -b"
git config --global alias.ci commit
git config --global alias.cm '!git add -A && git commit -m'
git config --global alias.st status
git config --global alias.br branch
git config --global alias.bra "branch -a"
```

Now you can write things like:

* `git co` instead of `git checkout`
* `git st` instead of `git status`
* `git br` instead of `git branch`
* `git cm "My change"` instead of `git add -A && git commit -m "My change"`

## Start coding

There is a [SAFE dojo](https://github.com/CompositionalIT/SAFE-Dojo) repository you can clone to get started.

```bash
cd ~/src
git clone https://github.com/CompositionalIT/SAFE-Dojo.git
cd SAFE-Dojo
./build.sh run
```

Now just wait for the build to finish and your browser will open automatically to show the page in all its glory. Now you can go to the [instructions](https://github.com/CompositionalIT/SAFE-Dojo/blob/master/Instructions.md) to work your way through the dojo.

## Resources

* [SAFE](https://safe-stack.github.io)
* S:
  * [Suave](https://suave.io)
  * [Giraffe](https://github.com/giraffe-fsharp/Giraffe)
  * [Saturn](https://saturnframework.org)
* A:
  * [Azure](https://compositional-it.com/blog/2017/09-19-safe-cloud/index.html)
* F:
  * [Fable](http://fable.io)
  * [Fable REPL](http://fable.io/repl2/)
* E:
  * [Elmish](https://elmish.github.io)
* [F# for fun and profit](https://fsharpforfunandprofit.com)
* [VSCode distributed via apt](https://github.com/Microsoft/vscode/issues/2973)
* [Installing Yarn](https://yarnpkg.com/lang/en/docs/install/#debian-stable)
* [Installing Node](https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions)
