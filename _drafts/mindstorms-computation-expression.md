---
layout: post
title:  "Mindstorms F# DSL over gRPC"
categories: fsharp
tags: f# fsharp linux lego mindstorms development dotnet
---

This is part of [F# Advent calendar 2019](https://sergeytihon.com/2019/11/05/f-advent-calendar-in-english-2019/).

We're going to play around with some gPRC streaming and Lego Mindstorms, because why not.

First off is communicating with the Mindstorms brick. There is already a .NET API for this [here](https://github.com/BrianPeek/legoev3). However, it seems to be dead and we want .NET Core and new SDK project files. So I forked it,  patched it a bit slapped some Observables in there, since events are terrible. It can be found [here](https://github.com/atlemann/RxMindstorms). It is C# though and too much to rewrite the whole thing, so we're going to put some F# on top of it instead. It's using [HidSharp](https://www.nuget.org/packages/HidSharp) to communicate over Bluetooth to the Mindstorms brick on Ubuntu.

## Making a Mindstorms DSL in F#

We're now going to take a look at how to create an F# DSL on top of the existing C# API. For this we're going to use customized computation expressions for the different devices to try to replicate some of the device controls in the Mindstorms drag'n drop programming interface.

## Motors

Let's define what the different motor actions are by picking a subset of the available C# commands and their arguments. We also need to define the port somewhere, hence the BrickActions type.

```fsharp
type BrickAction =
    | MotorAction of OutputPort list * MotorAction
and MotorAction =
    | StartMotor
    | StopMotor
    | StepMotorAtPower of {| Power:int; Steps:uint32; Break:bool |}
    | TurnMotorAtPower of {| Power:int |}
    | TurnMotorAtPowerForTime of {| Power:int; Time:uint32; Break:bool |}
    | StepMotorSync of {| Speed:int; TurnRatio:int16; Steps:uint32; Break:bool |}
```

Now we need a nice way to define which of these actions to perform. What we would like is something like this:

```fsharp
let commands = mindstorms {
    Turn (Motor OutputPort.A) With Power 50
    Turn (Motors [ OutputPort.A; OutputPort.B ]) With Power 50
    TurnForTime 1000u (Motors [ OutputPort.A; OutputPort.B ]) With Power 50 Then Break
    Step (Motors [ OutputPort.A; OutputPort.B ]) For 180u Steps With Power 50 Then NoBreak
    StepSync (Motors [ OutputPort.A; OutputPort.B ]) For 180u Steps With Power 50 And TurnRatio 42s Then NoBreak
    Start (Motor OutputPort.A)
    Stop (Motor OutputPort.A)
    }
```

## Creating the builder

Our builder's state will be a list of `BrickActions` and we'll start with the required `Yield` member of the builder. It should just return an empty sequence.

```fsharp
type MindstormsBuilder() =
        member __.Yield(_) = Seq.empty
```

Let's look at the 1st line in the `commands` definition. Here we have some words we have to define, `Motor`, `With` and `Power`. A single command can also combine multiple ports, hence we have to support defining a list of ports as well. Hence the `Motor` type has to look something like this:

```fsharp
type MotorPorts =
    | Motor of OutputPort
    | Motors of OutputPort list

module MotorPorts =
    let get = function
        | Motor m -> [ m ]
        | Motors ms -> ms
```

Next is the `With` and `Power` keywords. We can simply make a single case union type without any content, since it's just a word.

```fsharp
type With = With
type Power = Power
```

Now we can add the first method of the builder:

```fsharp
[<CustomOperation("Turn")>]
member __.Turn(currentState, motor:MotorPorts, _:With, _:Power, power:int) =
    seq {
        yield! currentState
        yield MotorAction (MotorPorts.get motor, TurnMotorAtPower {| Power = power |})
    }
```

Here `_:With` and `_:Power` are just used as place holders make it look like a proper sentence.

Now if we look at the 3rd line we have this:

```fsharp
TurnForTime 1000u (Motors [ OutputPort.A; OutputPort.B ]) With Power 50 Then Break
```

The `Motors` keyword is already defined, but we need `Then` and `Break` as well. We can see from the 4th that there is a `NoBreak` keyword as well, so we get this:

```
type Then = Then

type BreakMode =
    | Break
    | NoBreak
```

Now we can define the `TurnForTime` operation like this:

```fsharp
[<CustomOperation("TurnForTime")>]
member __.TurnForTime(currentState, time:uint32, motor:MotorPorts, _:With, _:Power, power:int, _:Then, breakMode:BreakMode) =
    seq {
        yield! currentState
        yield MotorAction (MotorPorts.get motor, TurnMotorAtPowerForTime {| Power = power; Time = time; Break = breakMode |})
    }
```

The 4th and 5th lines require the `Steps` `And` and `TurnRatio` keywords:

```fsharp
Step (Motors [ OutputPort.A; OutputPort.B ]) For 180u Steps With Power 50 Then NoBreak
StepSync (Motors [ OutputPort.A; OutputPort.B ]) For 180u Steps With Power 50 And TurnRatio 42s Then NoBreak
```

```fsharp
type And = And
type Steps = Steps
type TurnRatio = TurnRatio
```

and now we can define the operations like this:

```fsharp
[<CustomOperation("Step")>]
member __.Step(currentState, motor:MotorPorts, _:For, steps:uint32, _:Steps, _:With, _:Power, power:int, _:Then, breakMode:BreakMode) =
    seq {
        yield! currentState
        yield MotorAction (MotorPorts.get motor, StepMotorAtPower {| Power = power; Steps = steps; Break = breakMode |})
    }

[<CustomOperation("StepSync")>]
member __.StepSync(currentState, motor:MotorPorts, _:For, steps:uint32, _:Steps, _:With, _:Power, power:int, _:And, _:TurnRatio, turnRatio:int16, _:Then, breakMode:BreakMode) =
    seq {
        yield! currentState
        yield MotorAction (MotorPorts.get motor, StepMotorSync {| Power= power; TurnRatio = turnRatio; Steps = steps; Break = breakMode |})
    }
```

And then we have `Start` and `Stop` which are a lot simpler:

```fsharp
[<CustomOperation("Start")>]
member __.Start(currentState, motor:MotorPorts) =
    seq {
        yield! currentState
        yield MotorAction (MotorPorts.get motor, StartMotor)
    }

[<CustomOperation("Stop")>]
member __.Stop(currentState, motor:MotorPorts) =
    seq {
        yield! currentState
        yield MotorAction (MotorPorts.get motor, StopMotor)
    }
```

Last but not least, we have to create an instance of the builder like this:

```fsharp
let mindstorms = MindstormsBuilder()
```











First we'll need a state for the computation expression. It must be a record type, since we want to specify a set of parameters to pass to the command.

```fsharp
type MotorState =
    { OutputPort : OutputPort list
      TurnRatio : int16 option
      Power : int option
      Step : uint32 option
      Ms : uint32 option
      Break : bool option }

module MotorState =

    let empty =
        { OutputPort = []
          TurnRatio = None
          Power = None
          Step = None
          Ms = None
          Break = None }
```

Since a motor action can be performed on multiple motors simultaneously, the `OutputPort` has to be a list. The rest of the parameters are optional depending on the action we want to perform. The `empty` function is needed to initialize the state of the builder in the `Yield` member.

We're going to use the [CustomOperation](https://docs.microsoft.com/en-us/dotnet/fsharp/language-reference/computation-expressions#custom-operations) attribute to define the different parameters we can set on a motor. Here are the different operations we can use to update the `MotorState` record:

```fsharp
type MotorBuilder (motorType:MotorType) =
    member __.Yield(_) = MotorState.empty

    [<CustomOperation("port")>]
    member __.SetPort(state:MotorState, value) =
        { state with OutputPort = [ value ] }

    [<CustomOperation("ports")>]
    member __.SetPorts(state:MotorState, value) =
        { state with OutputPort = value }

    [<CustomOperation("turn_ratio")>]
    member __.SetTurnRatio(state:MotorState, value) =
        { state with TurnRatio = Some value }

    [<CustomOperation("power")>]
    member __.SetPower(state:MotorState, value) =
        { state with Power = Some value }

    [<CustomOperation("step")>]
    member __.SetStep(state:MotorState, value) =
        { state with Step = Some value }

    [<CustomOperation("time")>]
    member __.SetTime(state:MotorState, value) =
        { state with Ms = Some value }

    [<CustomOperation("should_break")>]
    member __.ShouldBreak(state:MotorState, value) =
        { state with Break = Some value }
```

But how do we go from a `MotorState` to a `BrickAction`? We can implement the `Run` method on the builder, which will convert the state on return. Here we're using `active patterns` to try do deduce the different actions to perform according to which parameters are set on the `MotorState`.

```fsharp
    member __.Run(state:MotorState) =

        let (|TurnMotorAtPower|_|) (state:MotorState) =
            match state with
            | { OutputPort = [ port ]; TurnRatio = None; Power = Some power; Step = None; Ms = None; Break = None } ->
                Some (MotorAction ([port], MotorAction.TurnMotorAtPower {| Power = power |}))
            | _ ->
                None

        let (|TurnMotorAtPowerForTime|_|) (state:MotorState) =
            match state with
            | { OutputPort = [ port ]; TurnRatio = None; Power = Some power; Step = None; Ms = Some time; Break = doBreak } ->
                let doBreak = doBreak |> Option.defaultValue false
                Some (MotorAction ([port], MotorAction.TurnMotorAtPowerForTime {| Power = power; Time = time; Break = doBreak |}))
            | _ ->
                None

        let (|StepMotorAtPower|_|) (state:MotorState) =
            match state with
            | { OutputPort = [ port ]; TurnRatio = None; Power = Some power; Step = Some step; Ms = None; Break = doBreak } ->
                let doBreak = doBreak |> Option.defaultValue false
                Some (MotorAction ([port], MotorAction.StepMotorAtPower {| Power = power; Steps = step; Break = doBreak |}))
            | _ ->
                None

        let (|StepMotorSync|_|) (state:MotorState) =
            match state with
            | { OutputPort = ports; TurnRatio = Some turnRatio; Power = Some power; Step = Some step; Ms = None; Break = doBreak } ->
                let doBreak = doBreak |> Option.defaultValue false
                Some (MotorAction (ports, MotorAction.StepMotorSync {| Power = power; TurnRatio = turnRatio; Steps = step; Break = doBreak |}))
            | _ ->
                None

        match state with
        | TurnMotorAtPower x -> Ok x
        | TurnMotorAtPowerForTime x -> Ok x
        | StepMotorAtPower x -> Ok x
        | StepMotorSync x -> Ok x
        | _ -> Error (sprintf "Unrecognized motor instruction %A" state)
```

## Configuring the brick command

Now that we have a `BrickAction` instance, we can apply it to a command before sending it to the brick. Here we have a function which updates the given command with the given action. 

```fsharp
let updateCommand (command:Command) (actions:BrickAction) =
    match actions with
    | MotorAction (port, action) ->
        let ports =
            port
            |> List.map OutputPort.toEnum
            |> List.reduce (|||)

        match action with
        | StartMotor -> command.StartMotor(ports)
        | StopMotor -> command.StopMotor(ports, true)
        | TurnMotorAtPower x -> command.TurnMotorAtPower(ports, x.Power)
        | TurnMotorAtPowerForTime x -> command.TurnMotorAtPowerForTime(ports, x.Power, x.Time, x.Break)
        | StepMotorAtPower x -> command.StepMotorAtPower(ports, x.Power, x.Steps, x.Break)
        | StepMotorSync x -> command.StepMotorSync(ports, x.Power, x.TurnRatio, x.Steps, x.Break)

    command
```

Since the `Command` can be updated with multiple `BrickActions` to do multiple actions in a series, we are returning the edited command at the end of the function. By doing this, the `updateCommand` function matches the signature required for `List.fold`.

```fsharp
// Result<BrickAction, string>
let motorAction1 =
    motor {
        ports [ OutputPort.A; OutputPort.B ]
        power 42
        turn_ratio 45s
        step 180u
        should_break false
    }

// Result<BrickAction, string>
let motorAction2 =
    motor {
        ports [ OutputPort.A; OutputPort.B ]
        power 42
        step 4u
        time 1000u
        should_break true
    }

let cmd = brick.CreateCommand(CommandType.DirectNoReply)

// Result<BrickAction, string> list <-- We need to turn this around a bit
let actions =
    [ motorAction1
      motorAction2 ]
    |> List.fold updateCommand cmd // This doesn't take a list of Results
```

As you can see we have a list of Results, which doesn't fit into List.fold with our `updateCommand`. We have to turn it inside out like this:

```fsharp
module Result =
    /// Turn a "Result<'a, 'b> list" into a "Result<'a list, 'b>" using *monadic* style.
    /// Only the first error is returned. The error type does NOT need to be a list.
    /// See http://fsharpforfunandprofit.com/posts/elevated-world-3/#validation
    let sequenceM resultList =
        let folder result state =
            state |> Result.bind (fun list ->
            result |> Result.bind (fun element ->
                Ok (element :: list)
                ))
        let initState = Ok []
        Seq.foldBack folder resultList initState
```

Now we can use this new function to solve our problem:

```fsharp
// Result<Command, string>
let updatedCommand =
    [ motorAction1
      motorAction2 ]
    |> Result.sequenceM
    |> Result.map (List.fold updateCommand cmd)
```






----------------------

Ok, we now have a way to communicate with a Mindstorms brick over Bluetooth. Let's for arguments sake you don't have a Bluetooth adapter on your desktop, but your laptop does. For whatever reason you still want to sit on your desktop. Let's communicate over WiFi instead. So we're going to create a simple gRPC server which will communicate with the Lego for you.

## Add some simple gRPC instructions

Let's start adding things to a proto file. We will keep this simple, with just a couple of actions. But first we need to add some types:

```proto
syntax = "proto3";

package Mindstorms;

option csharp_namespace = "Mindstorms.Grpc";

service MindstormsService {
    rpc TurnMotor(TurnMotorRequest) returns (TurnMotorReply);
}

message OutputPort {
    enum Port {
        A = 0;
        B = 1;
        C = 2;
        D = 3;
        ALL = 4;
    }
}

message StartMotor {
}

message StopMotor {
}

message TurnAtSpeed {
    int32 speed = 1;
}

message TurnAtSpeedForTime {
    int32 speed = 1;
    uint32 ms = 2;
    bool break = 3;
}

message StepAtSpeed {
    int32 speed = 1;
    uint32 steps = 2;
    bool break = 3;
}

// Motor command
message TurnMotorRequest {
    OutputPort port = 1;
    oneof move_type {
        StartMotor start_motor = 2;
        StopMotor stop_motor = 3;
        TurnAtSpeed turn_at_speed = 4;
        TurnAtSpeedForTime turn_at_speed_for_time = 5;
        StepAtSpeed step_at_speed = 6;
   }
}

message TurnMotorReply {
}
```

## Bootstrapping a gRPC server

### The included dotnet templates

Let's do a `dotnet new` to list the available templates:

```
...

ASP.NET Core Empty                                web                      [C#], F#          Web/Empty                            
ASP.NET Core Web App (Model-View-Controller)      mvc                      [C#], F#          Web/MVC                              
ASP.NET Core Web App                              webapp                   [C#]              Web/MVC/Razor Pages                  
ASP.NET Core with Angular                         angular                  [C#]              Web/MVC/SPA                          
ASP.NET Core with React.js                        react                    [C#]              Web/MVC/SPA                          
ASP.NET Core with React.js and Redux              reactredux               [C#]              Web/MVC/SPA                          
Razor Class Library                               razorclasslib            [C#]              Web/Razor/Library/Razor Class Library
ASP.NET Core Web API                              webapi                   [C#], F#          Web/WebAPI                           
ASP.NET Core gRPC Service                         grpc                     [C#]              Web/gRPC                

...

```

Here we see there's no F# option for the `grpc` template. So, let's just start with an empty `web` template instead.

```
$ mkdir MindstormsServer
$ cd MindstormsServer
$ dotnet new web -lang F#
```

Now we need to add the dotnet gRPC packages:

```
$ dotnet add package Grpc.AspNetCore
```

And then try to build it:

```
$ dotnet build
...
...
/home/atle/.nuget/packages/grpc.tools/2.25.0/build/_protobuf/Google.Protobuf.Tools.targets(51,5): error : Google.Protobuf.Tools proto compilation is only supported by default in a C# project (extension .csproj) [/home/atle/src/fsadvent2019/MindstormsServer/src/MindstormsServer/MindstormsServer.fsproj]
```

So the only made C# generators for gRPC. Big surprise. Let's make a C# project to generate the protobuf bits.

```
$ dotnet new classlib -o src/Proto
$ dotnet add src/Proto package Grpc.AspNetCore
$ dotnet sln add src/Proto/*.csproj
$ dotnet add src/MindstormsServer/MindstormsServer.fsproj reference src/Proto/Proto.csproj
```

and then store the proto content above to `mindstorms.proto` next to the .csproj add the following to the .csproj file:

```xml
<ItemGroup>
  <Protobuf Include="mindstorms.proto" GrpcServices="Both" />
</ItemGroup>
```

And then try to build it again:

```
$ dotnet build
...
...
/home/atle/.nuget/packages/grpc.tools/2.25.0/build/_protobuf/Google.Protobuf.Tools.targets(51,5): error : Google.Protobuf.Tools proto compilation is only supported by default in a C# project (extension .csproj) [/home/atle/src/fsadvent2019/MindstormsServer/src/MindstormsServer/MindstormsServer.fsproj]
```

FFS! So for some reason it complains even when referencing a C# project with protobufs. Let's just work around that by adding the `<Protobuf_Generator>CSharp</Protobuf_Generator>` to the .fsproj file like this:

```xml
<PropertyGroup>
  <TargetFramework>netcoreapp3.0</TargetFramework>
  <Protobuf_Generator>CSharp</Protobuf_Generator>
</PropertyGroup>
```

And call `dotnet build` again and it should work.

