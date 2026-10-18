# Changelog

## 0.5.0

- Four new coins, and every coin comes with its ticker and logo

## 0.4.0

- The customer can change the coin: previousCoins, deposit to, and the widget's Change coin button

## 0.3.1

- React checkout widget: @payitgo/react joins the SDK releases
- Coin notes say how long a payment takes; native coins on their own network

## 0.3.0

- Breaking: `Future<bool> isLive()` in place of the `livemode` field of
  `Payitgo`, because a key does not say its mode. `isLive()` asks payitgo
  (`GET /v1/webhook`'s `livemode`) the first time and keeps the answer for
  the client's life.
- The client takes any non-empty key: an empty one throws `ArgumentError`
  (`payitgo: the API key is required`).

## 0.2.1

- Prices in other currencies: `payments.create` takes `priceAmount` and
  `priceCurrency` (EUR, GBP, NGN…) instead of `amountUsd`, converted at the
  rate of the moment; payments carry `priceAmount`, `priceCurrency` and
  `priceRate`.
- An example: `example/main.dart` creates a test payment and verifies its
  webhook.

## 0.2.0

- Test payments are simulated; dollar values on settlements and payouts
- QR code is the deposit address alone

## 0.1.1

- The source moved to https://github.com/payitgo/dart-sdk. No code changes.

## 0.1.0

- First release: payments (create, selectToken, list with its `storeId`
  filter, get), tokens (for an amount given as a String or a num), and the
  webhook (IPN): `webhooks.get`, `set`, `remove`, `test` and
  `constructEvent`, with the client's `webhookSecret` and default
  `webhookUrl`; a key-less `PayitgoCheckout` for Flutter apps, whose `watch`
  follows a payment through a late payment; `Deposit` getters for every field
  the gateway sends; `close()` for the http.Client the library makes.
