---
layout: post
title:  "Exploring your crypto with F#"
categories: fsharp
tags: f# fsharp linux crypto cryptocurrency
---

This is part of [F# Advent calendar 2021](). Go and check out all the other great posts and thank you Sergey Tihon for organizing!

In this post we're going to create a console application for exploring your crypto assets.

## Exploring the APIs

Let's start off by exploring the API of a crypto exchanges using .NET interactive notebooks in VSCode. If you haven't already, install the VSCode extension now:

![Install .NET interactive]({{ "/assets/fscrypto/net_interactive_extension.png" }})

To create a new notebook, press `Ctrl + Shift + p` and choose the following:

![Create new notebook]({{ "/assets/fscrypto/new_notebook.png" }})

![Choose dib]({{ "/assets/fscrypto/choose_dib.png" }})

![Choose F#]({{ "/assets/fscrypto/choose_fsharp.png" }})

In the first cell we want to include some NuGet packages to work with:

```fsharp
#r "nuget: Plotly.NET, 2.0.0-preview.11"
#r "nuget: Plotly.NET.Interactive, 2.0.0-preview.11"
#r "nuget: Thoth.Json.NET"
#r "nuget: FsToolkit.ErrorHandling"
#r "nuget: FSharp.Data"
```

With the cell in focus, press `Shift + Enter` to run it and create a new cell below. Here we we open some namespaces/modules:

```fsharp
open FSharp.Data
open FsToolkit.ErrorHandling
open Plotly.NET
open System.Net.Http
open Thoth.Json.Net
```

## Exploring the FIRI exchange's API

Let's look at a Norwegian exchange with a pretty simple API, [Firi](https://firi.com/) (previously known as MiraiEx). The API documentation can be found [here](https://developers.firi.com).

There are some public API's we could easily check using the JSON provider. Put the following into a cell in the notebook:

```fsharp
let [<Literal>] FiriUri = "https://api.miraiex.com/v2/markets"
type FiriMarkets = JsonProvider<FiriUri>
let markets = FiriMarkets.Load FiriUri

markets
|> Array.map (fun m -> (m.Id, m.Low, m.Last, m.High))
```

It will display something like this:

![Firi markets]({{ "/assets/fscrypto/firi_markets.png" }})

Next we could create a plot of some historic prices by choosing one of the market Ids loaded above.

```fsharp
let [<Literal>] HistoryUri = "https://api.miraiex.com/v2/markets/ETHNOK/history"
type FiriMarkets = JsonProvider<HistoryUri>
let history = FiriMarkets.Load $"https://api.miraiex.com/v2/markets/{markets.[0].Id}/history"

Chart.Line(
    history |> Array.map (fun h -> h.CreatedAt.UtcDateTime),
    history |> Array.map (fun h -> h.Price),
    ShowMarkers=true)
|> Chart.withTitle $"Price history {markets.[0].Id}"
|> Chart.withXAxisStyle ("Date")
|> Chart.withYAxisStyle ("Price")
```

![Firi price chart]({{ "/assets/fscrypto/price_chart.png" }})

## What about private endpoints?

To access private endpoints we need a ClientId and a secret from the Firi settings page:

![Get Firi secrets]({{ "/assets/fscrypto/get_firi_secrets.png" }})

Then we have to compute the signature as specified [here](https://developers.firi.com/#/authentication):

![Compute hash]({{ "/assets/fscrypto/HMAC_howto.png" }})

Now that you have the secrets, let's add some types for the endpoints:

```fsharp
type FiriSecrets =
    { ClientId: string
      Secret: string }
    static member Create clientId secret =
        { ClientId = clientId
          Secret = secret }

[<RequireQualifiedAccess>]
type Endpoint =
    | ListMarkets
    | ListBalances
    | ListTransactions
    | ListTrades
    | ListOrders
    | ListDepositHistory
with
    member this.Uri =
        match this with
        | ListMarkets -> "markets"
        | ListBalances -> "balances"
        | ListTransactions -> "history/transactions"
        | ListTrades -> "history/trades"
        | ListOrders -> "history/orders"
        | ListDepositHistory -> "deposit/history"
    member this.HttpMethod =
        match this with
        | ListMarkets
        | ListBalances
        | ListTransactions
        | ListTrades
        | ListDepositHistory
        | ListOrders -> HttpMethod.Get
```

We need a function for computing the `hmac` hash and return it as lower-case hex:

```fsharp
open System
open System.Text
open System.Security.Cryptography

let computeHash (secret:string) (data:string) =
    use hmacsha256 =
        secret
        |> Encoding.UTF8.GetBytes
        |> fun bs -> new HMACSHA256(bs)

    data
    |> Encoding.UTF8.GetBytes
    |> hmacsha256.ComputeHash
    |> Array.map (fun (x : byte) -> sprintf "%02x" x)
    |> String.concat String.Empty
```

Now we can use this hashing function to compute the Firi signature:

```fsharp
let computeSignature secret =
    // Oh-noes! Side-effect! Pass it in instead if you want a pure function
    let timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds() |> string
    let validity = "2000"

    // Use Thoth.Json.Net to encode the JSON content
    let body =
        Encode.object
            [
                "timestamp", Encode.string timestamp
                "validity", Encode.string validity
            ]
        |> Encode.toString 0

    let signature = computeHash secret body
    let queryParams = $"?timestamp={timestamp}&validity={validity}"
    (signature, queryParams)
```

For each message we have to compute this hash and add the query parameters:

```fsharp
let createRequestMessage (secrets:FiriSecrets) (endpoint:Endpoint) =
    let (signature, queryParams) = computeSignature secrets.Secret
    let requestUri = $"/v2/{endpoint.Uri}{queryParams}"

    let requestMessage = new HttpRequestMessage(endpoint.HttpMethod, requestUri)
    requestMessage.Headers.Add("miraiex-user-clientid", secrets.ClientId);
    requestMessage.Headers.Add("miraiex-user-signature", signature);

    requestMessage

let send (httpClient:HttpClient) (secrets:FiriSecrets) (endpoint:Endpoint) =
    async {
        let requestMessage = createRequestMessage secrets endpoint
        let! response = httpClient.SendAsync(requestMessage) |> Async.AwaitTask
        let! responseString = response.Content.ReadAsStringAsync() |> Async.AwaitTask
        return responseString
    }
```

TODO: Show JsonProvider for private endpoint


And now we can make a type for the API:

```fsharp
type FiriApi(secrets:FiriSecrets) =

    let httpClient = newHttpClient()
    let sendRequest = send httpClient secrets

    interface System.IDisposable with
        member this.Dispose() =
            httpClient.Dispose()

    member this.GetMarkets () =
        Endpoint.ListMarkets
        |> sendRequest
        |> Async.map (Decode.fromString (Decode.list Market.Decoder))

    member this.GetBalances () =
        Endpoint.ListBalances
        |> sendRequest
        |> Async.map (Decode.fromString (Decode.list Balance.Decoder))

    member this.GetAllTransactions () =
        Endpoint.ListTransactions
        |> sendRequest
        |> Async.map (Decode.fromString (Decode.list Transaction.Decoder))

    member this.GetAllTrades () =
        Endpoint.ListTrades
        |> sendRequest
        |> Async.map (Decode.fromString (Decode.list Trade.Decoder))

    member this.GetAllOrders () =
        Endpoint.ListOrders
        |> sendRequest
        |> Async.map (Decode.fromString (Decode.list Order.Decoder))

    member this.GetDepositHistory () =
        Endpoint.ListDepositHistory
        |> sendRequest
        |> Async.map (Decode.fromString DepositHistory.Decoder)
```
