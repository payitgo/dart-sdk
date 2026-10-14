# Changelog

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
