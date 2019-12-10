---
layout: post
title:  "Creating a Lego Mindstorms DSL in F#"
categories: fsharp
tags: f# fsharp linux lego mindstorms development dotnet
---

This is part of [F# Advent calendar 2019](https://sergeytihon.com/2019/11/05/f-advent-calendar-in-english-2019/). Go and check out all the other great posts and thank you Sergey Tihon for organizing!

We're going to play around with some Lego Mindstorms. Luckily, there's already a .NET API for this made by [Brian Peek](https://github.com/BrianPeek/legoev3). Sadly, it's no longer under active development and haven't been for quite some time. Since I'm on linux, I would like to use .NET Core and new SDK project files, so I made a fork where I patched it a bit and replaced the events with Observables, because why not. It's using [HidSharp](https://www.nuget.org/packages/HidSharp) to connect to the Mindstorms brick via the USB port. It can be found [here](https://github.com/atlemann/RxMindstorms).

In this post we're going try to make a DSL in F# on top of the existing C# code.

## Lego Mindstorms

The Lego Mindstorms brick has eight ports, four marked A-D and four marked 1-4. The A-D ports can both send and receive input data. 1-4 can only receive. The C# API defines a `Command` which can be configured with multiple actions before sending it to the Brick to be executed in order. There's also an observable which pushes responses from the Brick's devices, e.g. push sensor button presses or color sensor data. We're going to try to make a DSL to configure the actions to apply to a `Command`, but first we'll define the ports:

```fsharp
type OutputPort =
    | A
    | B
    | C
    | D
    | All

type InputPort =
    | One
    | Two
    | Three
    | Four
    | A
    | B
    | C
    | D
```

### Motor actions

Let's define what the different motor actions are by picking a subset of the available C# commands and their arguments.

```fsharp
/// Should the break be applied at the end of the action?
type BreakMode =
    | Break
    | Coast

/// A sub-set of motor actions that can be added to a command
type MotorAction =
    | StartMotor
    | StopMotor
    | StepMotorAtPower of {| Power:int; Steps:uint32; Break:BreakMode |}
    | TurnMotorAtPower of {| Power:int |}
    | TurnMotorAtPowerForTime of {| Power:int; Time:uint32; Break:BreakMode |}
    | StepMotorSync of {| Power:int; TurnRatio:int16; Steps:uint32; Break:BreakMode |}
```

We also need to define the port somewhere. Since we can have different devices connected to the ports, we'll make a top level `BrickActions` type.

```fsharp
type BrickAction =
    // Output port is a list, since an action can be applied to multiple motors simultaneously
    | MotorAction of OutputPort list * MotorAction
```

We need a nice way to define which of these actions to perform. What we're aiming for is something like this:

```fsharp
let commands = mindstorms {
    Turn (Motor OutputPort.A) With Power 50
    Turn (Motors [ OutputPort.A; OutputPort.B ]) With Power 50
    TurnForTime 1000u (Motors [ OutputPort.A; OutputPort.B ]) With Power 50 Then Break
    Step (Motors [ OutputPort.A; OutputPort.B ]) For 180u Steps With Power 50 Then Coast
    StepSync (Motors [ OutputPort.A; OutputPort.B ]) For 180u Steps With Power 50 And TurnRatio 42s Then Coast
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

Here `_:With` and `_:Power` are just used as placeholders make it look like a proper sentence.

Now if we look at the 3rd line we have this:

```fsharp
TurnForTime 1000u (Motors [ OutputPort.A; OutputPort.B ]) With Power 50 Then Break
```

The `Motors` keyword is already defined, but we need `Then` and `Break` as well. We can see from the 4th that there is a `Coast` keyword as well, so we get this:

```
type Then = Then

type BreakMode =
    | Break
    | Coast
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

## Creating the command

Now that we have a way to creat a list of `BricActions`, we need a way to update a command with them. This is done by first creating a command from the Brick and then mutating it by invoking different methods on it. Below we have an update function which translates from `BricAction` to the correct method on the `Command` instance.

```fsharp
let updateCommand : Command -> BrickAction -> Command =
    fun command actions ->
    match actions with
    | MotorAction (ports, action) ->
        let ports =
            ports
            |> List.map OutputPort.toEnum // Map to the C# enum flags
            |> List.reduce (|||) // Bitwise OR

        match action with
        | StartMotor -> command.StartMotor(ports)
        | StopMotor -> command.StopMotor(ports, true)
        | TurnMotorAtPower x -> command.TurnMotorAtPower(ports, x.Power)
        | TurnMotorAtPowerForTime x -> command.TurnMotorAtPowerForTime(ports, x.Power, x.Time, x.Break |> BreakMode.asBool)
        | StepMotorAtPower x -> command.StepMotorAtPower(ports, x.Power, x.Steps, x.Break |> BreakMode.asBool)
        | StepMotorSync x -> command.StepMotorSync(ports, x.Power, x.TurnRatio, x.Steps, x.Break |> BreakMode.asBool)

    command
```

And we can simply `fold` the list of `BricActions` over the `Command` like this:

```fsharp
let createCommand : Brick -> BrickAction seq -> Command =
    fun brick actions ->
    let cmd = brick.CreateCommand(CommandType.DirectReply)
    Seq.fold updateCommand cmd actions
```

which we then can send to the brick:

```fsharp
let invokeCommand : Brick -> BrickAction seq -> Task<System.Reactive.Unit> =
    fun brick actions ->
    createCommand brick actions
    |> brick.SendCommandAsync
```

## Creating a simple program

Now we'll try to create a simple program where we turn the engines when the push button is pressed and stop the engines when it's released.

First we have to connect to the brick:

```fsharp
    let comm = UsbCommunication("MyLegoEV3");
    let responseManager = ResponseManager();
    let brick = Brick(comm, responseManager);

    let connection =
       brick.Connect()
       |> Observable.subscribe ignore
```

Then we must listen to port changes and create two observables which trigger according to the button state, which is connected to port three:

```fsharp
let (pressed, released) = 
    brick.Ports.[RxMindstorms.InputPort.Three].Changes()
    |> Observable.map (fun struct (p, _) -> p.SIValue)
    |> Observable.distinctUntilChanged
    |> Observable.partition (fun x -> x = 1.0f)
```

Next we define what happens when you press and release the button:

```fsharp
use __ =
    pressed
    |> Observable.iter (fun x -> printfn "Pressed: %A" x)
    |> Observable.map (fun _ ->
        mindstorms {
            Turn (Motors [ OutputPort.B; OutputPort.C ] ) With Power 100
            Start (Motors [ OutputPort.B; OutputPort.C ])
        }
    )
    |> Observable.flatmapTask (invokeCommand brick)
    |> Observable.subscribe ignore

use __ =
    released
    |> Observable.iter (fun x -> printfn "Released: %A" x)
    |> Observable.map (fun _ ->
        mindstorms {
            Stop (Motors [ OutputPort.B; OutputPort.C ])
        }
    )
    |> Observable.flatmapTask (invokeCommand brick)
    |> Observable.subscribe ignore
```

## Creating programs with state

Here we try to make a program with different states.

1. Wait for push sensor before moving
2. When button is pressed, jump to `driveForwards` state
3. Then jump to `waitForLightSensor` and wait for light sensor pass a threshold
4. If the light sensor hits the threshold, jump to `turn()` state
5. Then jump back to `driveForwards` state

```fsharp
let rec waitUntilPushButton () = async {
    printfn "waitUntilPushButton"
    if brick.Ports.[RxMindstorms.InputPort.Three].SIValue = 1.0f then
        return! driveForwards ()
    else
        do! Async.Sleep 100
        return! waitUntilPushButton()        
    }
and driveForwards () = async {
    printfn "driveForwards"
    do! mindstorms {
            Turn (Motors [ OutputPort.B; OutputPort.C ] ) With Power 100
            Start (Motors [ OutputPort.B; OutputPort.C ] )
        }
        |> invokeCommand brick
        |> Async.AwaitTask
        |> Async.Ignore

    return! waitForLightSensor ()        
    }
and waitForLightSensor () = async {
    printfn "waitForLightSensor"
    if brick.Ports.[RxMindstorms.InputPort.Four].SIValue > 60.0f then
        return! turn ()
    else
        do! Async.Sleep 100
        return! waitForLightSensor ()
    }
and turn () = async {
    printfn "turn"
    do! mindstorms {
           TurnForTime 1000u (Motors [ OutputPort.B ]) With Power 80 Then Coast
           TurnForTime 1000u (Motors [ OutputPort.C ]) With Power -80 Then Coast
        }
        |> invokeCommand brick
        |> Async.AwaitTask
        |> Async.Ignore

    return! driveForwards ()        
    }

waitUntilPushButton ()
|> Async.RunSynchronously
```

## Adding the 'Run' method

The computation expressions also have a `Run` member that can be implemented to change the state before returning it. Say we have the following code:

```fsharp
let snippet : BrickActions seq =
    mindstorms {
        TurnForTime 1000u (Motors [ OutputPort.A; OutputPort.B ]) With Power 50 Then Break
        Start (Motor OutputPort.A)
    }
```

`snippet` is of type `BrickActions seq`.

If we implement `Run` like this:

```fsharp
member __.Run(actions:BrickActions seq) =

    fun (brick:Brick) ->
        let emptyCommand = brick.CreateCommand(CommandType.DirectReply)

        actions
        |> Seq.fold updateCommand emptyCommand
        |> brick.SendCommandAsync
        |> Async.AwaitTask
```

`snippet` would be of type `Brick -> Async<unit>` instead and we could run them like this:

```fsharp
async {
    do! brick
        |> mindstorms {
            TurnForTime 5000u (Motors [ OutputPort.A; OutputPort.B ]) With Power 50 Then Break
            Start (Motor OutputPort.A)
            }

    do! brick
        |> mindstorms {
            TurnForTime 2000u (Motors [ OutputPort.A; OutputPort.B ]) With Power 50 Then Break
            TurnForTime 2000u (Motors [ OutputPort.A; OutputPort.B ]) With Power -50 Then Break
            Stop (Motor OutputPort.A)
            }
}
|> Async.RunSynchronously
```


## Conclusion

We've seen how to make a DSL in F# using custom computation expressions, which are quite flexible and powerful. This was just a silly example, but it shows we could almost write plain english to configure the commands. It did get a bit more complicated when wiring it all up though.

This is all I had time for unfortunately. Hope you learned something. Thanks for reading!
