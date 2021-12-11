---
layout: post
title:  "Exploring your crypto with F#"
categories: fsharp
tags: f# fsharp linux crypto cryptocurrency
---

This is part of [F# Advent calendar 2021](https://sergeytihon.com/2021/10/18/f-advent-calendar-2021/). Go and check out all the other great posts and thank you Sergey Tihon for organizing!

In this post we're going to create a console application for exploring your crypto assets. The code can be found [here](https://github.com/atlemann/FsCrypto).

## Exploring the APIs

Let's start off by exploring the API of a crypto exchange using .NET interactive notebooks in VSCode. If you haven't already, install the VSCode extension now:

![Install .NET interactive]({{ "/assets/fscrypto/net_interactive_extension.png" }})

To create a new notebook, press `Ctrl + Shift + p` and choose the following:

![Create new notebook]({{ "/assets/fscrypto/new_notebook.png" }})

![Choose dib]({{ "/assets/fscrypto/choose_dib.png" }})

![Choose F#]({{ "/assets/fscrypto/choose_fsharp.png" }})

In the first cell we want to include some NuGet packages to work with:

```fsharp
#r "nuget: Plotly.NET, 2.0.0-preview.11"
#r "nuget: Plotly.NET.Interactive, 2.0.0-preview.11"
#r "nuget: FSharp.Data"
```

With the cell in focus, press `Shift + Enter` to run it and create a new cell below. Here we we open some namespaces/modules:

```fsharp
open FSharp.Data
open Plotly.NET
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

That's all fine for the public API's, but the interesting ones are the private. For that we have to work a bit harder.

## Let's try to make a typed API

First, let's define a list of some of their endpoints:

```fsharp
type OrderType =
    | Bid
    | Ask
    member this.AsString =
        match this with
        | Ask -> "Ask"
        | Bid -> "Bid"

type Order =
    { Market: string
      Type: OrderType
      Price: double
      Amount: double }
    static member Create market orderType price amount =
        { Market = market
          Type = orderType
          Price = price
          Amount = amount }

[<RequireQualifiedAccess>]
type Endpoint =
    | ListMarkets
    | ListBalances
    | ListTransactions
    | ListTrades
    | ListDepositHistory
    | ListOrders
    | CreateOrder of Order
    | DeleteAllOrders
with
    member this.Uri =
        match this with
        | ListMarkets -> "markets"
        | ListBalances -> "balances"
        | ListTransactions -> "history/transactions"
        | ListTrades -> "history/trades"
        | ListDepositHistory -> "deposit/history"
        | ListOrders -> "history/orders"
        | CreateOrder _
        | DeleteAllOrders -> "orders"
    member this.HttpMethod =
        match this with
        | ListMarkets
        | ListBalances
        | ListTransactions
        | ListTrades
        | ListDepositHistory
        | ListOrders ->
            HttpMethod.Get
        | CreateOrder _ ->
            HttpMethod.Post
        | DeleteAllOrders ->
            HttpMethod.Delete
    member this.Body =
        match this with
        | ListMarkets
        | ListBalances
        | ListTransactions
        | ListTrades
        | ListDepositHistory
        | ListOrders
        | DeleteAllOrders ->
            None
        | CreateOrder order ->
            Encode.object
                [
                    "market", Encode.string order.Market
                    "type", Encode.string order.Type.AsString
                    "price", Encode.string (string order.Price)
                    "amount", Encode.string (string order.Amount)
                ]
            |> Encode.toString 0
            |> Some
```

We also need some types to deserialize the responses into, using Thoth.Json:

```fsharp
open Thoth.Json.Net

type Balance =
    { Currency: string
      Balance: float
      Hold: float
      Available: float }
    static member Decoder : Decoder<Balance> =
        Decode.object
            (fun get ->
                { Currency = get.Required.Field "currency" Decode.string
                  Balance = get.Required.Field "balance" Decode.string |> float
                  Hold = get.Required.Field "hold" Decode.string |> float
                  Available = get.Required.Field "available" Decode.string |> float })

type Transaction =
    { Id: Guid
      Amount: decimal
      Currency: string
      Type: string
      Date: DateTimeOffset
      Details: TransactionDetails }
    static member Decoder : Decoder<Transaction> =
        Decode.object
            (fun get ->
                { Id = get.Required.Field "id" Decode.guid
                  Amount = get.Required.Field "amount" Decode.string |> decimal
                  Currency = get.Required.Field "currency" Decode.string
                  Type = get.Required.Field "type" Decode.string
                  Date = get.Required.Field "date" Decode.datetimeOffset
                  Details = get.Required.Field "details" TransactionDetails.Decoder })
and TransactionDetails =
    { MatchId: string option
      DepositId: string option
      DepositAddress: string option
      DepositTxid: string option
      WithdrawId: string option
      WithdrawAddress: string option
      WithdrawTxid: string option }
    static member Decoder : Decoder<TransactionDetails> =
        Decode.object
            (fun get ->
                { MatchId = get.Optional.Field "match_id" Decode.string
                  DepositId = get.Optional.Field "deposit_id" Decode.string
                  DepositAddress = get.Optional.Field "deposit_address" Decode.string
                  DepositTxid = get.Optional.Field "deposit_txid" Decode.string
                  WithdrawId = get.Optional.Field "withdraw_id" Decode.string
                  WithdrawAddress = get.Optional.Field "withdraw_address" Decode.string
                  WithdrawTxid = get.Optional.Field "withdraw_txid" Decode.string })

//...not listing them all here
```

## What about private endpoints?

To access private endpoints we need to create a ClientId and Secret in the Firi settings page and store them in a safe place. Then we have to compute the signature as specified [here](https://developers.firi.com/#/authentication):

![Compute hash]({{ "/assets/fscrypto/HMAC_howto.png" }})

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
type FiriSecrets =
    { ClientId: string
      Secret: string }
    static member Create clientId secret =
        { ClientId = clientId
          Secret = secret }

let private createRequestMessage (secrets:FiriSecrets) (endpoint:Endpoint) =

    let (signature, queryParams) = getSignature secrets.Secret
    let requestUri = $"{endpoint.Uri}{queryParams}"

    let requestMessage = new HttpRequestMessage(endpoint.HttpMethod, requestUri)
    requestMessage.Headers.Add("miraiex-user-clientid", secrets.ClientId);
    requestMessage.Headers.Add("miraiex-user-signature", signature);

    endpoint.Body
    |> Option.iter (fun body ->
        let content = new StringContent(body, Text.Encoding.UTF8, "application/json")
        requestMessage.Content <- content)

    requestMessage

let send (httpClient:HttpClient) (secrets:FiriSecrets) (endpoint:Endpoint) =
    task { // Let's try the new task CE in F# 6
        use requestMessage = createRequestMessage secrets endpoint
        use! response = httpClient.SendAsync(requestMessage)
        let! responseString = response.Content.ReadAsStringAsync()
        return responseString
    }
    |> Async.AwaitTask
```

And now we can make a type for the API which holds the secrets and can dispose the internal HttpClient:

```fsharp
type FiriApi(secrets:FiriSecrets) =

    let httpClient = new HttpClient(BaseAddress = Uri "https://api.miraiex.com/v2/")
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

    member this.GetDepositHistory () =
        Endpoint.ListDepositHistory
        |> sendRequest
        |> Async.map (Decode.fromString DepositHistory.Decoder)

    member this.GetAllOrders () =
        Endpoint.ListOrders
        |> sendRequest
        |> Async.map (Decode.fromString (Decode.list Order.Decoder))

    member this.CreateOrder (order:Order) =
        order
        |> Endpoint.CreateOrder
        |> sendRequest
        |> Async.map (Decode.fromString CreateOrderResponse.Decoder)

    member this.DeleteAllOrders () =
        Endpoint.DeleteAllOrders
        |> sendRequest
        |> Async.Ignore
```

## What if you're using multiple crypto exchanges?

For e.g. Coinbase, if not using OAuth, we could reuse that same hashing function for the secrets headers and make something similar to the Firi implementation we did above:

```fsharp
type CoinbaseSecrets =
    { ApiKey : string
      ApiSecret : string }
with
    static member Create (apiKey, apiSecret) =
        { ApiKey = apiKey
          ApiSecret = apiSecret }

let getSignature (secret:string) (timestamp:string) (method:HttpMethod) (url:string) (body:string) =
    let body = timestamp + method.Method + url + body
    computeSignature secret body

let createMessage (secrets:CoinbaseSecrets) (endpoint:Endpoint) =
    let timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds() |> string
    let requestUri = $"/v2/{endpoint.Url}"
    let signature =
        endpoint.Body
        |> Option.defaultValue ""
        |> Signature.Coinbase.getSignature secrets.ApiSecret timestamp endpoint.HttpMethod requestUri

    let requestMessage = new HttpRequestMessage(endpoint.HttpMethod, requestUri)
    requestMessage.Headers.Add("CB-VERSION", "2021-12-11") // Some recent date
    requestMessage.Headers.Add("CB-ACCESS-KEY", secrets.ApiKey)
    requestMessage.Headers.Add("CB-ACCESS-SIGN", signature)
    requestMessage.Headers.Add("CB-ACCESS-TIMESTAMP", timestamp)

    endpoint.Body
    |> Option.iter (fun body ->
        let content = new StringContent(body, Text.Encoding.UTF8, "application/json")
        requestMessage.Content <- content)

    requestMessage
```

The Coinbase responses are a bit more verbose than the Firi ones. For example look at the [transactions](https://developers.coinbase.com/api/v2#list-transactions) response. It's quite big, but we can use [Json2FSharp](https://json2fsharp.com) to create the types for us. Just copy the example into the left side of `Json2FSharp` and it will create the matching F# types for you. You might have to modify them a bit though. Fortunately, there's a .NET implementation already available [here](https://github.com/bchavez/Coinbase) and we can see if we can use that one instead of rolling our own.

## Separating the instructions from the side-effects

Now we have two different crypto clients with different ways of getting the data we're after. We want to make some common  instruction set hiding the specific implementations, but how? F# supports interfaces, so why not use that and create one implementation per exchange? Because, MONAAAADS! More specifically a Free Monad with one interpreter per client.

### Creating a Free Monad

A Free Monad follows a very specific recipie which can be more or less copy/pasted every time, except for the actual instructions you want it to have. The different instructions are added to a discriminated union type and will look like this:

```fsharp
type MyInstructions<'a>
    | DoSomething of (Args1 * (Out1 -> 'a))
    | DoSomethingElse of (Args2 * (Out2 -> 'a))
    ...
```

Now let's make one for showing your total balance and your transaction history. First we start by making some output types for the instructions:

```fsharp
type InstructionBalance =
    { Crypto: string
      Amount: double }
    static member Create crypto amount =
        { Crypto = crypto
          Amount = amount }

type InstructionAmount =
    { Amount: double
      Currency: string }
    static member Create amount currency =
        { Amount = amount
          Currency = currency }

[<RequireQualifiedAccess>]
type TransactionType =
    | Deposit of Amount:InstructionAmount
    | Transaction of Bought:InstructionAmount * Sold:InstructionAmount * Fee:InstructionAmount
    | Withdrawal of Amount:InstructionAmount * Fee:InstructionAmount

type InstructionTransaction =
    { Exchange: string
      TimeStamp: DateTimeOffset
      Type: TransactionType }
    static member Create exchange timeStamp transactionType =
        { Exchange = exchange
          TimeStamp = timeStamp
          Type = transactionType }

type InstructionMarket =
    { MarketPair: string
      Last: decimal
      High: decimal
      Low: decimal }
    static member Create marketPair last high low =
        { MarketPair = marketPair
          Last = last
          High = high
          Low = low }
```

Then we create the different instructions and the required Free Monad functions:

```fsharp
// The avaiable instructions.
// First item in tuple is `unit`, since there are no arguments.
type CryptoInstruction<'a> =
    | GetBalances of (unit * (InstructionBalance list -> 'a))
    | GetTransactions of (unit * (InstructionTransaction list -> 'a))
    | GetMarkets of unit * (InstructionMarket list -> 'a)

// Free Monad recipie below

// The instructions type has to be a functor, so we add a map function.
module CryptoInstruction =
    let map f = function
        | GetBalances (x, next) -> GetBalances (x, next >> f)
        | GetTransactions (x, next) -> GetTransactions (x, next >> f)
        | GetMarkets (x, next) -> GetMarkets (x, next >> f)

// This will always have this shape.
type CryptoProgram<'a> =
    | Free of CryptoInstruction<CryptoProgram<'a>>
    | Pure of 'a

// And it requires a bind function
module CryptoProgram =
    let rec bind f = function
    | Free x -> x |> CryptoInstruction.map (bind f) |> Free
    | Pure x -> f x

// Computation expression to make it convenient to use
type CryptoBuilder () =
    member this.Bind (x, f) = CryptoProgram.bind f x
    member this.Return x = Pure x
    member this.ReturnFrom x = x
    member this.Zero () = Pure ()

let crypto = CryptoBuilder()

// Convenience functions for creating the instructions
let getBalances () = Free (GetBalances ((), Pure))
let getTransactions () = Free (GetTransactions ((), Pure))
let getMarkets () = Free (GetMarkets ((), Pure))
```

This lets us create a simple program for getting balances:

```fsharp
let getBalancesProgram = crypto {
    let! markets = getMarkets ()
    let! balances = getBalances ()

    let result = // Combine them somehow...

    return result
}
```

### But the Free Monad follows a recipie you said

True that, and for that we can use [FSharpPlus](http://fsprojects.github.io/FSharpPlus/reference/fsharpplus-data-free.html) which has Free Monad helper functions. Using this library, all you need is the instructions functor with the map function as a static member (FSharpPlus uses [SRTPs](https://docs.microsoft.com/en-us/dotnet/fsharp/language-reference/generics/statically-resolved-type-parameters)) and use `Free.liftF` for the convenience functions:

```fsharp
open FSharpPlus.Data

type CryptoInstruction<'a> =
    | GetBalances of (unit * (InstructionBalance list -> 'a))
    | GetTransactions of (unit * (InstructionTransaction list -> 'a))
    | GetMarkets of unit * (InstructionMarket list -> 'a)
    static member Map (instruction, f) = // FSharpPlus expects static member 'Map'
        match instruction with
        | GetBalances (x, next) -> GetBalances (x, next >> f)
        | GetTransactions (x, next) -> GetTransactions (x, next >> f)
        | GetMarkets (x, next) -> GetMarkets (x, next >> f)

// Convenience functions for creating the instructions
let getBalances () = GetBalances ((), id) |> Free.liftF
let getTransactions () = GetTransactions ((), id) |> Free.liftF
let getMarkets () = GetMarkets ((), id) |> Free.liftF
```

And we can replace our `crypto` computation expression with FSharpPlus' `monad`:

```fsharp
open FSharpPlus

let getBalancesProgram = monad {
    let! markets = getMarkets ()
    let! balances = getBalances ()

    let result = // Combine them somehow...

    return result
}
```

### Now for some interpretation


The second part of a Free Monad is the interpreter, which is where the side-effects happen. First, we need functions for getting the API types into the instruction types, e.g. getting the `Balance` response from the Firi API into the `InstructionBalance` type:

```fsharp
// Calling the API is Async and Thoth.Json's decoders return Result,
// so we end up with a nested type.

open FsToolkit.ErrorHandling // Has convenient asyncResult CE

// FiriApi -> Async<Result<InstructionBalance list, string>>
let getBalancesApi firiApi =
    asyncResult {
        let! balances = firiApi.GetBalances()
        return
            balances
            |> List.map (fun b ->
                InstructionBalance.Create b.Currency b.Balance)
    }

// FiriApi -> Async<Result<InstructionTransaction list, string>>
let getTransactionsApi firiApi =
    asyncResult {
        let! transactions = firiApi.GetTransactions ()
        let instructionTransactions =
            transactions
            |> // Create InstructionTransactions from the response (see GitHub repo)
        return instructionTransactions
    }

let private getMarketsApi (firiApi:FiriApi) =
    asyncResult {
        let! markets = firiApi.GetMarkets()
        return
            markets
            |> List.map (fun m ->
                InstructionMarket.Create m.Id m.Last m.High m.Low)
    }
```

then we make the actual interpret function:

```fsharp
// FiriApi -> CryptoInstruction<'a> -> Async<Result<'a, string>>
let interpret firiApi instruction =
    match instruction with
    | GetBalances (_, next) ->
        asyncResult {
            let! balances = getBalancesApi firiApi
            return balances |> next
        }
    | GetTransactions (_, next) ->
        asyncResult {
            let! transactions = getTransactionsApi firiApi
            return transactions |> next
        }
    | GetMarkets (_, next) ->
        asyncResult {
            let! markets = getMarketsApi firiApi
            return markets |> next
        }
```

To interpret a program, which might contain multiple instructions, we can use FSharpPlus `Free.fold` and pass in our interpret function:

```fsharp
let balances =
    getBalancesProgram
    |> Free.fold (interpret firiApi) // Doesn't compile, since Async<Result<'a, 'b>> doesn't have static member (>>=)
```

`Free.fold` requires the returned type to have two static members, `bind (>>=)` and `return`, but we have a nested type. What now?

#### Option 1: Make a wrapper type

```fsharp
// Has Async.bind, Async.singleton and Result.either
open FsToolkit.ErrorHandling

type AsyncResult<'a, 'b> =
    AsyncResult of Async<Result<'a, 'b>>
with
    static member (>>=) (AsyncResult x, f:'a -> AsyncResult<'c, 'b>) =
        let f' a =
            let (AsyncResult r) = f a
            r

        x
        |> Async.bind (Result.either f' (Error >> Async.singleton))
        |> AsyncResult

    static member Return x = Ok x |> Async.singleton |> AsyncResult
```

And now we can do this:

```fsharp
let balances =
    getBalancesProgram
    |> Free.fold (interpret firiApi >> AsyncResult) // Wrap nested type
    |> fun (AsyncResult ar) -> ar // Unwrap the final result
    |> Async.RunSynchronously
    |> function
        | Ok bs ->
            //...
        | Error err ->
            //...
```

#### Option 2: Monad transformers

Nested monads can be handled by Monad Transformers. Our inner monad is `Result` so we need a transformer for that. Conveniently `FSharpPlus` has one called `ResultT` and we don't have to make any wrapper types anymore:

```fsharp
let balances =
    getBalancesProgram
    |> Free.fold (interpret firiApi >> ResultT)
    |> ResultT.run
    |> Async.RunSynchronously
    |> function
        | Ok bs ->
            //...
        | Error err ->
            //...
```

### Let's add an interpreter for Coinbase

We're going to use an [existing .NET client](https://github.com/bchavez/Coinbase) in the interpreter, since someone already did the hard work there. Now, let's try to get our balances using this client.

First of all, the Coinbase API uses pagination, so we have to be able follow the links to the next pages to extract all the data. The API returns a PagedResponse\<'a\> with a link to the next page and the data for the current page. Hence, we're going to need an async loop, since we're going to have to call the API multiple times until there are no pages left. To help us with this we're going to use the [FSharp.Control.AsyncSeq](https://github.com/fsprojects/FSharp.Control.AsyncSeq) library.

```fsharp
open FSharp.Control
open Coinbase
open Coinbase.Models

/// Gets all the following pages for the given initial response
let getPages (client:CoinbaseClient) (initialResponse:PagedResponse<'a>) : AsyncSeq<'a array> =
    initialResponse
    |> AsyncSeq.unfoldAsync (fun x -> async {
        if x.Pagination.NextUri |> isNull then
            return None
        else
            let! nextPage = client.GetNextPageAsync x |> Async.AwaitTask
            return Some (nextPage.Data, nextPage)
    })
```

Now that we have a generic function to get all pages of a certain response, we can fetch all accounts where the amount is greater than zero quite conveniently using `AsyncSeq`:

```fsharp
let getBalancesApi (client:CoinbaseClient) : Async<InstructionBalance list> =
    asyncSeq {
        let! response = client.Accounts.ListAccountsAsync() |> Async.AwaitTask
        yield response.Data // Yield the initial response's data
        yield! getPages client response // Yield all the following pages
    }
    |> AsyncSeq.concatSeq
    |> AsyncSeq.filter (fun a -> a.Balance.Amount > 0.0M)
    |> AsyncSeq.map (fun a ->
        InstructionBalance.Create a.Balance.Currency a.Balance.Amount)
    |> AsyncSeq.toListAsync

let getTransactionsApi (client:CoinbaseClient) =
    // ... skipped for brevity (see GitHub repo)

// Could take currency as parameter if we change the instruction to this:
// | GetMarkets of (currency:string) * (InstructionMarket list -> 'a)
//
// and convenience function to this:
//
// let getMarkets (currency:string) = GetMarkets (currency, id) |> Free.liftF
let getMarketsApi (client:CoinbaseClient) =
    async {
        let! response =
            client.Data.GetExchangeRatesAsync("NOK") |> Async.AwaitTask

        return
            response.Data.Rates
            |> Seq.map (fun kvp ->
                let rate = 1.0m / kvp.Value
                InstructionMarket.Create kvp.Key rate rate rate)
            |> Seq.toList
    }
```

and we can create the interpret function:

```fsharp
// CoinbaseClient -> CryptoInstruction<'a> -> Async<'a>
let interpret coinbaseClient instruction =
    match instruction with
    | GetBalances (_, next) ->
        async {
            let! balances = getBalancesApi coinbaseClient
            return balances |> next
        }
    | GetTransactions (_, next) ->
        async {
            let buys = getTransactionsApi coinbaseClient
            return buys |> next
        }
    | GetMarkets (_, next) ->
        async {
            let! markets = getMarketsApi coinbaseClient
            return markets |> next
        }

let balances =
    getBalancesProgram
    |> Free.fold (interpret coinbaseClient) // No nested type here
```

### We can also make a testing interpreter

Here we add some test data which we could use for testing our instructions:

```fsharp
let [<Literal>] private ExchangeName = "Testing"

let interpret instruction =
    match instruction with
    | GetBalances (_, next) -> async {
        do! Async.Sleep 2000 // Pretend it takes time

        let balances =
            [
                InstructionBalance.Create ExchangeName "BTC" 0.0175m
                InstructionBalance.Create ExchangeName "ETH" 0.03m
                InstructionBalance.Create ExchangeName "ADA" 200.123m
                InstructionBalance.Create ExchangeName "ALU" 123.123m
                InstructionBalance.Create ExchangeName "SHIB" 123456789.0m
            ]
        return balances |> next
        }

    | GetTransactions (_, next) -> async {
        do! Async.Sleep 4000 // Pretend it takes time

        let transactions =
            [
                let startDate = DateTimeOffset(DateTime(2021, 1, 1, 12, 00, 00))
                InstructionTransaction.Create ExchangeName (startDate.AddDays 1) (TransactionType.Deposit (InstructionAmount.Create 1000m "USD"))
                InstructionTransaction.Create ExchangeName (startDate.AddDays 2) (TransactionType.Transaction ((InstructionAmount.Create 0.0348m "BTC"), (InstructionAmount.Create 1000m "USD"), (InstructionAmount.Create 0.5m "USD")))
                InstructionTransaction.Create ExchangeName (startDate.AddDays 3) (TransactionType.Deposit (InstructionAmount.Create 1000m "USD"))
                InstructionTransaction.Create ExchangeName (startDate.AddDays 4) (TransactionType.Transaction ((InstructionAmount.Create 0.03m "ETH"), (InstructionAmount.Create 1000m "USD"), (InstructionAmount.Create 1m "USD")))
                InstructionTransaction.Create ExchangeName (startDate.AddMonths 11) (TransactionType.Transaction ((InstructionAmount.Create 932.4663m "USD"), (InstructionAmount.Create 0.0174m "BTC"), (InstructionAmount.Create 0.5m "USD")))
                InstructionTransaction.Create ExchangeName (startDate.AddMonths 12) (TransactionType.Withdrawal ((InstructionAmount.Create 932.4663m "USD"), (InstructionAmount.Create 1m "USD")))


            ]
        return transactions |> next

    | GetMarkets (_, next) -> async {
        do! Async.Sleep 1000 // Pretend it takes time

        let markets =
            [
                InstructionMarket.Create "BTC" 500000m 500000m 500000m
                InstructionMarket.Create "ETH" 35000m 35000m 35000m
                InstructionMarket.Create "ADA" 8.25m 8.25m 8.25m
                InstructionMarket.Create "ALU" 1.34m 1.34m 1.34m
                InstructionMarket.Create "SHIB" 0.0003m 0.0003m 0.0003m
            ]
        return markets |> next
    }

let run (instructions:Free<CryptoInstruction<'a>, 'a>) =
    instructions
    |> Free.fold interpret
```

## Aggregating the response from multiple interpreters

We have to somehow invoke both Firi and Coinbase when we want to interpret our programs. Say we have the following functions:

```fsharp
module Firi =
    // let interpret ...
    // ...

    let run firiApi (instructions:Free<CryptoInstruction<'a>, 'a>) : Async<Result<'a, string>> =
        instructions
        |> Free.fold (interpret firiApi >> ResultT)
        |> ResultT.run

module Coinbase =
    // let interpret ...
    // ...

    let run coinbaseClient (instructions:Free<CryptoInstruction<'a>, 'a>) : Async<'a> =
        instructions
        |> Free.fold (interpret coinbaseClient)
```

Then we can run our program for both interpreters and concatenate the result using `AsyncSeq` like this:

```fsharp
module Program =

    open FSharp.Control
    open FsToolkit.ErrorHandling

    // Runs a program on both interpreteres and returns the concatenated result
    // FiriApi -> CoinbaseClient -> Free<CryptoInstruction<'a list>, 'a list> -> Async<Result<'a list, string list>>
    let run firiApi coinbaseClient program =
        asyncSeq {
            // yield (Testing.run >> Async.map Ok)
            yield Firi.run firiApi
            yield (Coinbase.run coinbaseClient >> Async.map Ok) // Must match return type from Firi.run
        }
        |> AsyncSeq.mapAsyncParallel (fun run -> run program)
        |> AsyncSeq.toListAsync // Async<Result<'a list, string> list>
        |> Async.map (List.sequenceResultA >> Result.map (List.collect id))

let getBalancesProgram = monad {
    let! balances = getBalances ()
    return balances
}

let balances =
    getBalancesProgram
    |> Program.run firiApi coinbaseClient
    |> Async.RunSynchronously
```

## I want to see the results in pretty tables

For this we can create a CLI and use [Spectre.Console](https://spectreconsole.net) library to make it awesome.

First we make a function which combines the balances and current values in NOK in a table:

```fsharp
let spinner =
    let spinner = AnsiConsole.Status()
    spinner.Spinner <- Spinner.Known.Dots
    spinner.SpinnerStyle <- Style.Parse("green bold")
    spinner

let showBalances (firiApi:FiriApi) (coinbaseClient:CoinbaseClient) = async {

    let getBalancesProgram = monad {
        let! balances = getBalances ()
        let! markets = getMarkets ()

        let marketLookup =
            ("NOK", 1.0m) ::
            (markets |> List.map (fun m -> (m.MarketPair, m.Last)))
            |> Map.ofList

        let nokPerCoin =
            balances
            |> List.map (fun b ->
                let value =
                    marketLookup
                    |> Map.find b.Crypto

                (b.Crypto, b.Amount * value))
            |> Map.ofList

        return
            balances
            |> List.map (fun b ->
                {|
                    b with
                        Value = nokPerCoin.[b.Crypto]
                        Currency = "NOK"
                |})
        }

    let! balances =
        spinner.StartAsync(
            "[green]Getting balances...[/]",
            fun _ -> run getBalancesProgram |> Async.StartAsTask)
        |> Async.AwaitTask

    match balances with
    | Ok xs ->
        let table =
            Table()
                .AddColumn("[blue]Crypto[/]")
                .AddColumn("[blue]Amount[/]")
                .AddColumn("[blue]Value[/]")
                .AddColumn("[blue]Currency[/]")
                .AddColumn("[blue]Exchange[/]")
        table.Border <- TableBorder.Rounded
        table.Title <- TableTitle("[purple_1]Balances[/]")
        table.Columns.[1].Alignment <- Justify.Right
        table.Columns.[2].Alignment <- Justify.Right

        xs
        |> List.filter (fun t -> t.Amount > 0.0m)
        |> List.iter (fun t ->
            table.AddRow(
                $"[orange1]{t.Crypto}[/]",
                $"[green]%.4f{t.Amount}[/]",
                $"[green]%.2f{t.Value}[/]",
                $"[blue]{t.Currency}[/]",
                $"[deepskyblue1]{t.Exchange}[/]")
            |> ignore)

        let sum = xs |> List.sumBy (fun t -> t.Value)
        table.AddRow("[lightgreen]Sum[/]", "", $"[lightgreen]%.2f{sum}[/]", "[blue]NOK[/]") |> ignore

        AnsiConsole.Write (table)

    | Error err ->
        AnsiConsole.MarkupLine($"[Red]Failed to get balances. Details: {err}[/]")
    }

```

```fsharp
open Coinbase
open Spectre.Console
open ...

[<RequireQualifiedAccess>]
type Selection =
    | Transactions
    | Balances
    | Quit

[<EntryPoint>]
let main argv =

    // Get from environment var or args
    let firiClientId = ""
    let firiSecret = ""
    let coinbaseApiKey = ""
    let coinbaseSecret = ""

    use firiApi = new FiriApi(FiriSecrets.Create clientId secret)
    use coinbaseClient =
        new CoinbaseClient(new ApiKeyConfig(ApiKey=coinbaseApiKey,
                                            ApiSecret=coinbaseSecret))

    let selectionPrompt =
        let prompt = new SelectionPrompt<Selection>()
        prompt.Title <- "[blue]What do you want to see?[/]"
        prompt.AddChoices(
            [|
                Selection.Transactions
                Selection.Balances
                Selection.Quit
            |]) |> ignore
        prompt

    let rec loop () = async {
        let choice = AnsiConsole.Prompt(selectionPrompt)

        match choice with
        | Selection.Transactions ->
            do! showTransactions firiApi coinbaseClient
            return! loop ()

        | Selection.Balances ->
            do! showBalances firiApi coinbaseClient
            return! loop ()

        | Selection.Quit ->
            ()
        }

    loop ()
    |> Async.RunSynchronously

    0 // return an integer exit code
```

Now let's try it out using our testing interpreter:

![Choose dib]({{ "/assets/fscrypto/fscrypto_progress.gif" }})

## Profit!

Using the aggregated transaction history from multiple exchanges, we could calculate our gains and losses for, say, tax purposes, but that's a task for another day.