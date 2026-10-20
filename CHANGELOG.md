# Changelog

## 0.6.0

- Mass payouts: pay your own clients from your payout wallet.
  - `payitgo.payouts`: payout requests sent one by one as your clients ask
    (`request`, safe to retry on its `reference`), your open list with what
    sending it needs of the wallet (`inbox`), `send` (all valid requests, or
    some `ids`), `retrieve`, `retrieveByReference`, `cancel`, and `quote`
    (prices up to 100 payments, nothing kept).
  - `payitgo.payoutBatches`: `create`, `list`, `retrieve`, `items`,
    `addItems`, `quote`, `submit` and `cancel`.
  - `payitgo.payoutWallets`: `list`, and `simulateTopUp` for test keys.
  - Typed models: `PayoutItemInput`, `PayoutItem`, `PayoutBatch`,
    `PayoutInbox`, `PayoutQuoteResult`, `PayoutWallet`, `PayoutWithdrawal`
    and their parts; amounts are decimal strings, as everywhere.
  - Claim links: with `claim: true` or `claimAssets` (other coins to offer)
    and no address, the recipient chooses the coin and the address; an
    `email` gets the link. Payments carry `claim` (`PayoutClaim`: `url`, `expiresAt`,
    `claimedAt`, …), statuses `claimable` and `expired`, and batch counts
    of both.
  - Converted payments: `convert` and `convertFrom` on
    `payoutBatches.create` and `payouts.quote` pay every payment in another
    coin from the wallet's coin, converted on its way. Payments carry
    `convert` (`PayoutConversion`: `to`, `toAmount`, `estimate`,
    `amountOut`) and `conversionFee`; batches `convert` and `convertFrom`.
  - Schedules (set up in the dashboard): `PayoutSchedule` and
    `PayoutScheduleFunding` for their webhooks; batch `source` `schedule`.
  - `payouts.remove(ids)` takes up to 1000 payout requests out of the
    list at once: a `PayoutRemoveResult` per id, its `item` or its `error`
    (a `PayitgoException`). An empty `ids` throws an `ArgumentError`.
  - `payouts.list(status:, updatedSince:, cursor:, limit:)` lists every
    payment of the mode by last change, oldest first, to resync: a
    `PayoutPage` (`items`, `hasMore`, `nextCursor`).
  - `payouts.cancel` is safe to retry: a payment canceled already comes
    back as it is. A removed request keeps its record, without a batch.
    `payouts.retrieveByReference` falls back to the latest payment that
    gave the reference back; an empty reference throws an `ArgumentError`.
  - Payments carry `cancelReason` (`removed`, `canceled`,
    `batch_canceled`, `rejected`, `invalid`), `cancelNote`, `canceledBy`,
    `canceledAt`, `members` and `webhookUrl`; `batchId` is null for a
    request removed from the list. Withdrawals carry `failReason`.
  - `webhookUrl` on `payouts.request` and `PayoutItemInput`: a payment's
    events go there, before its batch's `webhookUrl` and the webhook's URL.
- `payitgo.events.list(types:, after:, createdAfter:, limit:)` replays the
  mode's events as their webhooks carried them: an `EventPage` of
  `WebhookEvent`s and `hasMore`.
- `Webhooks.events` adds the `payout_batch.*`, `payout_item.*` (with
  `payout_item.processing`, `payout_item.returned`, `payout_item.claimed`
  and `payout_item.claim_expired`), `payout_wallet.withdrawn`,
  `payout_wallet.withdrawal_failed`, `payout_schedule.run` and
  `payout_schedule.funding_needed` events.
- `example/payouts.dart` pays a client in test mode.

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
