# Changelog

## 0.1.0

- First release: payments (create, selectToken, list with its `storeId`
  filter, get), tokens (for an amount given as a String or a num), and the
  webhook (IPN): `webhooks.get`, `set`, `remove`, `test` and
  `constructEvent`, with the client's `webhookSecret` and default
  `webhookUrl`; a key-less `PayitgoCheckout` for Flutter apps, whose `watch`
  follows a payment through a late payment; `Deposit` getters for every field
  the gateway sends; `close()` for the http.Client the library makes.
