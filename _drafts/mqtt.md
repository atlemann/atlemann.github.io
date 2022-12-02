---
layout: post
title:  "Smarthome interaction with MQTT"
categories: fsharp
tags: f# fsharp smarthome mqtt
---

# Interacting with a MQTT service

In this post we're going to try to interact with the smart home [MQTT](https://mqtt.org) API for [FutureHome](https://github.com/futurehomeno/fimp-api).

Fortunately for us, someone has already created a MQTT client library for us, available [here](https://www.nuget.org/packages/MQTTnet/). And someone has been so kind as to extend it with observables, instead of having to deal with the utterly useless thing that is vanilla events. That library can be found [here](https://www.nuget.org/packages/MQTTnet.Extensions.External.RxMQTT.Client).

# FIMP

Is the Futurehome IoT Messaging Protocol. The documentation can be found [here](https://github.com/futurehomeno/fimp-api). It's a bit tricky to figure out how it works but we'll give it a shot anyway. Some examples can be found in their Go implementation [here](https://github.com/futurehomeno/fimpgo/blob/master/docs/primefimp/examples) which has been used to figure out what the different request content should be for certain things.

# FIMP message format 

Messages sent using FIMP are JSON messages containing the following properties (see [here](https://github.com/futurehomeno/fimp-api/blob/master/message-format.md) for original docs):

Property | Type                | Required | Description               
---------|---------------------|----------|------------
corid    | String              | No       | Message correlation id. Used for request - response matching.
ctime    | String              | Yes      | Message creation time, e.g. `"2019-05-31 17:36:31 +0200"`
props    | Map<String, String> | Yes      | Map of properties.
resp_to  | String              | No*      | Response topic where requester will expect to receive response.
serv     | String              | Yes      | Service name the interface is part of.
src      | String              | Yes      | Source or of the message, should be set only for commands.
tags     | List<String>        | No       | List of tags.
type     | String              | Yes      | Interface type, defines message format.
uid      | String              | Yes      | Unique message identifier.
val      | dynamic             | Yes      | "payload" - type is defined by `val_t`.
val_t    | String              | Yes      | Data format of `val` field. See below.
ver      | String              | Yes      | Version of the message format, default: `"1"`.

## Value Types

Since `val` can be any type, `val_t` defines what type it is. List of supported `val` types: 

`val_t`     | Sample `val`
------------|-------------
string      | `'Hello world!'`
int         | `3`
float       | `3.1415`
bool        | `true`
null        | `null`
str_array   | `['hello, 'world']`
int_array   | `[0, 1, 1, 2, 3, 5, 8, 13]`
float_array | `[3.14, 2.71]`
int_map     | `{"answer": 42}`
str_map     | `{"ip": "192.168.1.1"}`
float_map   | `{"pi: 3.14"}`
bool_map    | `{"normalityRestored": true}`
object*     | `{"nested": {"objects": "supported"}}`
base64      | `U28gbG9uZywgYW5kIHRoYW5rcyBmb3IgYWxsIHRoZSBmaXNoLg==`

\*A complex object which can't be mapped to primitive types. The structure of an object is defined by interface type and is unique for every interface type. 

## Creating the object type

All the possible types of `val_t` are pretty simple except the `object` type. After some digging around [here](https://github.com/futurehomeno/fimpgo/blob/master/docs/primefimp/examples) it seems it look something like this:

```json
{
    "cmd": "delete",
    "component": "room",
    "id": 1,
    "param": {},
    "requestId": 7294000000006
}
```
where param could look like:

```json
"param": {
    "components": [
        "thing",
        "device",
        "room",
        "mode",
        "shortcut"
    ]
}
```
So let's start off with the possible commands. We're going to use [Thoth.Json.Net](https://www.nuget.org/packages?q=thoth.json.net) to encode our messages, like this:

```fsharp
type Cmd =
    | Get
    | Set
    | Delete
    | Edit

module Cmd =
    let encode (value: Cmd) : JsonValue =
        match value with
        | Get -> Encode.string "get"
        | Set -> Encode.string "set"
        | Delete -> Encode.string "delete"
        | Edit -> Encode.string "edit"
```

Next we have components, which can be any of the following:

```fsharp
type Component =
    | Service
    | Config
    | Room
    | Device
    | Mode
    | Hub
    | House

module Component =
    let encode (value: Component) : JsonValue =
        match value with
        | Service -> Encode.string "service"
        | Config -> Encode.string "config"
        | Room -> Encode.string "room"
        | Device -> Encode.string "device"
        | Mode -> Encode.string "mode"
        | Hub -> Encode.string "hub"
        | House -> Encode.string "house"

```

The id can be things like room-id or house mode (home, sleep etc.):

```fsharp
type ObjectRequestId =
    | DeviceId of int
    | Mode of Mode
    | FireAlarm of Enabled: bool * Supported: bool

module ObjectRequestId =
    let encode (value: ObjectRequestId) : JsonValue =
        match value with
        | DeviceId v -> Encode.int v
        | Mode m -> Mode.encode m
        | FireAlarm (isEnabled, isSupported) ->
            Encode.object [
                "enabled", Encode.bool isEnabled
                "supported", Encode.bool isSupported
            ]
```

And finally we have the `Object` type:

```fsharp
type ObjectVal =
    { Cmd: Cmd
      Component: Component option
      Id: ObjectRequestId option
      Param: JsonValue option }

module ObjectVal =
    let create cmd component' id param =
        { Cmd = cmd
          Component = component'
          Id = id
          Param = param }

    let encode (value: ObjectVal) =
        Encode.object [
            "cmd", Cmd.encode value.Cmd

            match value.Component with
            | Some c ->
                "component", Component.encode c
            | None ->
                "component", Encode.nil

            match value.Id with
            | Some id ->
                "id", ObjectRequestId.encode id
            | None ->
                "id", Encode.nil

            match value.Param with
            | Some p ->
                "param", p
            | None ->
                "param", Encode.nil
        ]
```

## The Val type

Now that we have the `object` type, we can create the `val` type:

```fsharp
type Val =
    | String of string
    | Int of int
    | Float of float
    | Bool of bool
    | Null
    | Str_array of string array
    | Int_array of int array
    | Float_array of float array
    | Int_map of Map<string, int>
    | Str_map of Map<string, string>
    | Float_map of Map<string, float>
    | Bool_map of Map<string, bool>
    | Object of ObjectVal
    | Base64 of string

module Val =

    let encode (value: Val) =
        match value with
        | String x -> ["val_t", Encode.string "string"; "val", Encode.string x]
        | Int x-> ["val_t", Encode.string "int"; "val", Encode.int x]
        | Float x -> ["val_t", Encode.string "float"; "val", Encode.float x]
        | Bool x -> ["val_t", Encode.string "bool"; "val", Encode.bool x]
        | Null -> ["val_t", Encode.string "null"; "val", Encode.string "null"]
        | Str_array xs -> ["val_t", Encode.string "string_array"; "val", xs |> Array.map Encode.string |> Encode.array]
        | Int_array xs -> ["val_t", Encode.string "int_array"; "val", xs |> Array.map Encode.int |> Encode.array]
        | Float_array xs -> ["val_t", Encode.string "float_array"; "val", xs |> Array.map Encode.float |> Encode.array]
        | Int_map x -> ["val_t", Encode.string "int_map"; "val", x |> Map.map (fun _ v -> Encode.int v) |> Encode.dict]
        | Str_map x -> ["val_t", Encode.string "str_map"; "val", x |> Map.map (fun _ v -> Encode.string v) |> Encode.dict]
        | Float_map x -> ["val_t", Encode.string "float_map"; "val", x |> Map.map (fun _ v -> Encode.float v) |> Encode.dict]
        | Bool_map x -> ["val_t", Encode.string "bool_map"; "val", x |> Map.map (fun _ v -> Encode.bool v) |> Encode.dict]
        | Object x -> ["val_t", Encode.string "object"; "val", ObjectVal.encode x]
        | Base64 x -> ["val_t", Encode.string "base64"; "val", Encode.string x]
```

## The message type

Finally we can create the FIMP message type that has to be sent as content to the server.

```fsharp
// Modules not included for brevity
type CorId = CorId of CorrelationId: string
type Ctime = Ctime of CreationTime: DateTime
type Props = Props of Properties: Map<string, string>
type RespTo = RespTo of ResponseTopic: string
type Serv = Serv of ServiceName: string
type Src = Src of string
type TagsList = TagsList of string list
type Type = Type of InterfaceType: string
type Uid = Uid of MessageIdentifier: Guid
type Ver = private Ver of string

type Message =
    { CorId: CorId option
      Ctime: Ctime
      Props: Props
      RespTo: RespTo option
      Serv: Serv
      Src: Src
      Tags: TagsList list option
      Type: Type
      Uid: Uid
      Val: Val
      Ver: Ver }

module Message =

    let create ctime props serv src interfaceType uid value =
        { CorId = None
          Ctime = ctime
          Props = props
          RespTo = None
          Serv = serv
          Src = src
          Tags = None
          Type = interfaceType
          Uid = uid
          Val = value
          Ver = Ver.defaultVer }

    let withCorrelationId corId msg =
        { msg with CorId = Some corId }

    let withResponseTopic topic msg =
        { msg with RespTo = Some topic }

    let withTags tags msg =
        { msg with Tags = Some tags }

    let private encodeOpt (f: 'a -> JsonValue) (value: 'a option) =
        value
        |> Option.map f
        |> Option.defaultValue Encode.nil

    let encode (msg: Message) =
        Encode.object [
            "corid", msg.CorId |> encodeOpt CorId.encode
            "ctime", msg.Ctime |> Ctime.encode
            "props", msg.Props |> Props.encode
            "resp_to", msg.RespTo |> encodeOpt RespTo.encode
            "serv", msg.Serv |> Serv.encode
            "src", msg.Src |> Src.encode
            "tags", msg.Tags |> encodeOpt TagsList.encode
            "type", msg.Type |> Type.encode
            "uid", msg.Uid |> Uid.encode
            yield! msg.Val |> Val.encode
            "ver", msg.Ver |> Ver.encode
        ]
```

## Creating the MQTT client

Here we're using `MQTTnet.Extensions.External.RxMQTT.Client` to create a client we can interact with using observables.

```fsharp
module MqttClient =
    open MQTTnet.Extensions.External.RxMQTT.Client

    type ClientId = ClientId of string
    type Topic = Topic of string

    type TcpServer =
        { Url: string
          Port: int }

    type Credentials =
        { UserName: string
          Password: string }

    // ClientId -> TcpServer -> Credentials -> Task<IRxMqttClient>
    let create (ClientId clientId) (server: TcpServer) (credentials: Credentials) = task {
        let options =
            ManagedMqttClientOptionsBuilder()
                .WithAutoReconnectDelay(TimeSpan.FromSeconds(5))
                .WithClientOptions(MqttClientOptionsBuilder()
                    .WithProtocolVersion(MqttProtocolVersion.V311)
                    .WithClientId(clientId)
                    .WithTcpServer(server.Url, server.Port)
                    .WithCredentials(credentials.UserName, credentials.Password)
                    .Build())
                .Build();

        let mqttClient = MqttFactory().CreateRxMqttClient()
        do! mqttClient.StartAsync options
        return mqttClient
    }

    // IRxMqttClient -> Topic -> IObservable<MqttApplicationMessageReceivedEventArgs>
    let createSubscription (mqttClient: IRxMqttClient) (Topic topic) =
        mqttClient.Connect(topic)
    
    // Topic -> Message -> MqttApplicationMessage
    let createMessage (Topic topic) (message: Message) =
        MqttApplicationMessageBuilder()
            .WithTopic(topic)
            .WithPayload(message |> Message.encode |> Encode.toString 0)
            .WithQualityOfServiceLevel(MQTTnet.Protocol.MqttQualityOfServiceLevel.ExactlyOnce)
            .WithRetainFlag()
            .Build()
```

## Listing all devices

An example request can be seen [here](https://github.com/futurehomeno/fimpgo/blob/f598e137e9fd10205a3361aadc8f94e49cb9f4d9/docs/primefimp/examples#L127). Let's try to create the request message:

```fsharp
module Things =

    let requestTopic = RequestTopic.create "pt:j1/mt:cmd/rt:app/rn:vinculum/ad:1"

    // We can select the `ad` for the response
    let responseTopic = ResponseTopic.create "pt:j1/mt:rsp/rt:app/rn:vinculum/ad:things"

    // Val -> Message
    let private createDefaultMessage =
        Message.create
            (Ctime.create DateTime.Now)
            (Props.create List.empty)
            Serv.Vinculum
            src
            (Type.create "cmd.pd7.request") // Not sure what pd7 is, but copied from their example.
            (Uid.newUid())

    // Val -> Message
    let createMessage value =
        value
        |> createDefaultMessage
        |> Message.withResponseTopic responseTopic

    // string list -> Val
    let private encodeComponents items =
        Encode.object [
            "components",
            items
            |> List.map Encode.string
            |> Encode.list
        ]
        |> Some
        |> ObjectVal.create Cmd.Get None None
        |> Val.Object

    // Message
    let listDevices =
        [
            "device"
        ]
        |> encodeComponents
        |> createMessage
```

## Interacting with the API

The MqttClient we're using returns responses using observables. If we want to get the list of devices in a request/response fashion, we have to [leave the monad](http://introtorx.com/Content/v1.0.10621.0/10_LeavingTheMonad.html) by converting the observable to a Task. 

```fsharp
let getAsync (mqttClient: IRxMqttClient) requestTopic responseTopic message = task {    
    
    let respObs =
        responseTopic // The topic we created above and added to the message as repond topic
        |> MqttClient.createSubscription mqttClient
        // We want the first message returned and the observable to complete
        |> Observable.first

    // Subscribe/start as task before sending the request
    let response = respObs.ToTask()

    do! message
        |> MqttClient.createMessage requestTopic
        |> mqttClient.PublishAsync

    return! response
    }
```

```fsharp
/// Gets all available devices
let getAllDevices (mqttClient: IRxMqttClient) = task {
    let! response = getAsync mqttClient Things.requestTopic Things.responseTopic Things.listDevices
    let devices = response.ApplicationMessage.Payload.ToUTF8String()
    return devices
    }
```
This is an example response for a motion sensor device:

```json
...
{
    "client": {
        "name": "Motion sensor"
    },
    "fimp": {
        "adapter": "zwave-ad",
        "address": "19",
        "group": "ch_0"
    },
    "functionality": null,
    "id": 36,
    "lrn": true,
    "model": "zw_271_2049_4097",
    "param": {
        "alarms": {},
        "batteryLevel": "ok",
        "batteryPercentage": 100,
        "illuminance": 1.0,
        "presence": false,
        "supportedAlarms": {
            "burglar": [
                "inactive",
                "tamper_removed_cover"
            ]
        },
        "temperature": 23.0,
        "timestamp": "2022-11-10 22:20:14 +0100",
        "zwaveConfigParameters": []
    },
    "problem": false,
    "room": 6,
    "services": {
        "alarm_burglar": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:alarm_burglar/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.alarm.get_report",
                "evt.alarm.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true,
                "sup_events": [
                    "inactive",
                    "tamper_removed_cover"
                ]
            }
        },
        "basic": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:basic/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.lvl.get_report",
                "cmd.lvl.set",
                "evt.lvl.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true
            }
        },
        "battery": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:battery/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.lvl.get_report",
                "evt.alarm.report",
                "evt.lvl.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true
            }
        },
        "dev_sys": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:dev_sys/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.config.get_report",
                "cmd.config.set",
                "cmd.group.add_members",
                "cmd.group.delete_members",
                "cmd.group.get_members",
                "cmd.ping.send",
                "evt.config.report",
                "evt.group.members_report",
                "evt.ping.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true
            }
        },
        "sensor_accelx": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:sensor_accelx/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.sensor.get_report",
                "evt.sensor.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true,
                "sup_units": [
                    "m/s2"
                ]
            }
        },
        "sensor_accely": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:sensor_accely/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.sensor.get_report",
                "evt.sensor.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true,
                "sup_units": [
                    "m/s2"
                ]
            }
        },
        "sensor_accelz": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:sensor_accelz/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.sensor.get_report",
                "evt.sensor.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true,
                "sup_units": [
                    "m/s2"
                ]
            }
        },
        "sensor_lumin": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:sensor_lumin/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.sensor.get_report",
                "evt.sensor.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true,
                "sup_units": [
                    "Lux"
                ]
            }
        },
        "sensor_presence": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:sensor_presence/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.presence.get_report",
                "evt.presence.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true
            }
        },
        "sensor_seismicint": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:sensor_seismicint/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.sensor.get_report",
                "evt.sensor.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true,
                "sup_units": [
                    "MERC"
                ]
            }
        },
        "sensor_temp": {
            "addr": "/rt:dev/rn:zw/ad:1/sv:sensor_temp/ad:19_0",
            "enabled": true,
            "intf": [
                "cmd.sensor.get_report",
                "evt.sensor.report"
            ],
            "props": {
                "is_secure": false,
                "is_unsecure": true,
                "sup_units": [
                    "C"
                ],
                "thing_role": "main"
            }
        }
    },
    "supports": [
        "clear",
        "poll"
    ],
    "thing": 13,
    "type": {
        "subtype": "presence",
        "supported": {
            "sensor": [
                "presence"
            ]
        },
        "type": "sensor"
    }
}
...
```

## Interaction between divices

Now that we know which devices we have, their features and topics, we can try to make some interaction between them. We have a Fibaro motion sensor and a Philips Hue Go lamp we can play with. First we need some requests for turning on lights and setting color.


```fsharp
module FsFimp.Commands

open System
open FsFimp.Fimp

let app = "fsfimp"
let src = Src.create app

module Units =
    type [<Measure>] Red
    type [<Measure>] Green
    type [<Measure>] Blue

type Red = int<Units.Red>
type Green = int<Units.Green>
type Blue = int<Units.Blue>

type Toggle = On | Off

let power (toggle: Toggle) =
    match toggle with
    | On -> true
    | Off -> false
    |> Val.Bool
    |> Message.create
        (Ctime.create DateTime.Now)
        Props.empty
        Serv.OutLevelSwitch
        src
        (Type.create "cmd.binary.set")
        (Uid.newUid())

let color (red: Red) (green: Green) (blue: Blue) =
    seq {
        "red", int red
        "green", int green
        "blue", int blue
    }
    |> Map.ofSeq
    |> Val.Int_map
    |> Message.create
        (Ctime.create DateTime.Now)
        Props.empty
        Serv.ColorControl
        src
        (Type.create "cmd.color.set")
        (Uid.newUid())
```

Next we have to listen to events from the motion sensor. We'll turn on the lights when presence is detected and make it red when the burglar event is triggered (e.g. when shaking the sensor):

```fsharp
use! mqttClient = MqttClient.create (ClientId "FsFimp") server credentials
use _ = mqttClient.ConnectingFailedEvent.Subscribe(fun msg -> printfn "%A, %A" msg.ConnectResult msg.Exception.Message)
let send (msg: MQTTnet.MqttApplicationMessage) : Task<unit> =
    task {
        return! mqttClient.PublishAsync msg
    }

let turnOnLightOnPresence =
    "pt:j1/mt:evt/rt:dev/rn:zw/ad:1/sv:sensor_presence/ad:19_0"
    |> ResponseTopic.create
    |> MqttClient.createSubscription mqttClient
    |> Observable.map (fun msg ->
        let requestTopic =
            "pt:j1/mt:cmd/rt:dev/rn:hue/ad:1/sv:out_lvl_switch/ad:l14_0"
            |> RequestTopic.create

        Commands.power Toggle.On
        |> MqttClient.createMessage requestTopic)

let makeLightRedOnBurglar =
    "pt:j1/mt:evt/rt:dev/rn:zw/ad:1/sv:alarm_burglar/ad:19_0"
    |> ResponseTopic.create
    |> MqttClient.createSubscription mqttClient
    |> Observable.map (fun msg ->
        let requestTopic =
            "pt:j1/mt:cmd/rt:dev/rn:hue/ad:1/sv:color_ctrl/ad:l14_0"
            |> RequestTopic.create

        Commands.color 255<Units.Red> 0<Units.Green> 0<Units.Blue>
        |> MqttClient.createMessage requestTopic)

use _ =
    Observable.merge turnOnLightOnPresence makeLightRedOnBurglar
    |> Observable.flatmapTask send
    |> Observable.subscribe id
```

![Movie gif]({{ "/assets/mindstorms_dsl/mindstorms.gif" }})

## Next steps

Decode the features of the devices and add e.g. the lights to a smart house dashboard using Fable. But that's a post for another time.