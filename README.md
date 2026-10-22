# payitgo for Dart and Flutter

Accept crypto payments, and pay your own clients, with [payitgo](https://api.payitgo.co/docs) from Dart 3.

Full reference, with every method, option, type and error: [api.payitgo.co/docs/sdk-dart](https://api.payitgo.co/docs/sdk-dart).

```bash
dart pub add payitgo      # or: flutter pub add payitgo
```

The library has two clients:

- **`Payitgo`** uses your secret API key, for **your server** (a Dart backend, Cloud
  Functions, …). Never put a secret key in a Flutter app: anyone can extract it.
- **`PayitgoCheckout`** needs no key, for **Flutter apps**. Your backend creates the payment
  and hands the app its `checkout_token`; the app shows the payment and follows it.

## On your server: accept a payment in three steps

```dart
import 'dart:io';
import 'package:payitgo/payitgo.dart';

final payitgo = Payitgo(
  Platform.environment['PAYITGO_KEY']!,
  webhookSecret: Platform.environment['PAYITGO_WEBHOOK_SECRET'], // the signing secret: see Webhooks (IPN) below
);

// 1. Create a payment and send the customer to the checkout page (or return the
//    checkout_token to your Flutter app).
final payment = await payitgo.payments.create(
  orderId: 'ORD-1001',   // your order id: safe to retry
  amountUsd: 19.99,
  // token: 'USDT_TRC20',   // optional: without it the customer picks the coin
  successUrl: 'https://yourdomain.com/thanks',
);
print(payment.checkoutUrl);

// 2. Receive the notification (shelf shown; the complete handler is under Webhooks (IPN) below).
//    Use the raw body: the signature covers its exact bytes.
Future<Response> ipn(Request request) async {
  final body = await request.readAsString();
  final WebhookEvent event;
  try {
    event = payitgo.webhooks.constructEvent(body, request.headers['x-webhook-signature']);
  } on SignatureVerificationException {
    return Response(400);
  }
  // 3. Fulfil the order once the payment is final.
  if (event.type == 'payment.confirmed') {
    await markOrderPaid(event.data['order_id'] as String); // idempotent: events can arrive twice
  }
  return Response.ok('');
}
```

A key is a test key or a live key, and does not say which (the dashboard shows a Test or
Live badge next to it): `await payitgo.isLive()` asks payitgo, once.

## On your server: prices in other currencies

To price a payment in your own currency, give `priceAmount` and `priceCurrency` (an ISO
4217 code such as `EUR`, `GBP` or `NGN`) instead of `amountUsd`. payitgo converts the price
into dollars at the rate of the moment, and the payment keeps both:

```dart
final payment = await payitgo.payments.create(
  orderId: 'ORD-1002',
  priceAmount: '45.50',   // sent as priceAmount.toString(): prefer a String to a double
  priceCurrency: 'EUR',   // any case
);
// payment.priceAmount '45.5', payment.priceCurrency 'EUR',
// payment.priceRate '1.082' (dollars per euro), payment.usdAmount '49.23'
```

Everything else (`usdAmount`, `cryptoAmount`, fees, minimums) stays in dollars; a payment
priced in dollars has `null` price getters. Give `amountUsd` or the pair, not both (`400`).
When no exchange rate can be had, `create` throws a `PayitgoException` with status `503`
(`exchange rate unavailable for price_currency: try again shortly`) once the client's retries
are spent: try again shortly. `PayitgoCheckout` reads the same fields, so a Flutter app can
show the price in your currency next to the dollar amount.

## On your server: your own payment page

`checkoutUrl` is only for payitgo's hosted page. To show the payment on your own page,
render the payment your server gets back (`depositAddress`, `cryptoAmount`,
`destinationTag` for XRP, a QR code of `qrPayload`, `expiresAt`); no `checkout` calls are
needed.

- **You know the coin:** create the payment with `token` and render the payment it returns.
- **The customer chooses it:** create the payment without `token`, show
  `payment.tokenOptions` on your page, then call
  `payitgo.payments.selectToken(payment.id, chosen)` from your server and render the payment
  it returns: it now has its coin, address, amount, locked rate and a deadline 15 minutes
  away.

```dart
final payment = await payitgo.payments.create(orderId: 'ORD-1', amountUsd: 10);
// your page shows payment.tokenOptions; the customer picks one
final chosen = await payitgo.payments.selectToken(payment.id, 'USDT_TRC20'); // or your order id
// render chosen.depositAddress, chosen.cryptoAmount, chosen.qrPayload, chosen.expiresAt
```

The customer can change the coin while the payment still has `tokenOptions` (nothing has
arrived yet): call `payments.selectToken` again with another. Once it can no longer change, it is a `409`
(`payments.retrieve` then returns the payment with its coin). A coin outside `tokenOptions`, or a
payment that can no longer be paid, is a `400`.

## On your server: test mode

A test payment gets an address like a live one, but no coins are involved: you choose an
outcome and payitgo plays its deposits, status changes and webhooks a few seconds apart
([Test mode](https://api.payitgo.co/docs/testing)).

```dart
// Choose the outcome when you create the payment (with token it starts at once,
// without it once the coin is chosen)…
await payitgo.payments.create(orderId: 'TEST-1', amountUsd: 10, token: 'USDT_TRC20', simulate: 'confirmed');

// …or later, on a payment you already have (its id or your order id).
final payment = await payitgo.payments.simulate('TEST-2', 'partially_paid');
// payment.simulation: outcome 'partially_paid', state 'running'
```

Outcomes (`Payments.simulationOutcomes`): `confirmed`, `overpaid`, `partially_paid`,
`underpaid`, `expired`, `failed`, `wrong_asset`, `paid_late`. Simulated deposits have
`simulated` true; their `txId` names no transaction on any chain. A live key gets `400`; a
payment whose simulation is still running, `409`.

## On your server: Webhooks (IPN)

payitgo POSTs a signed notification for every change of a payment (`payment.confirmed`,
`payment.expired`, …), of a direct settlement, of a payout, and of a payout batch and its
payments ([below](#on-your-server-payouts)). Each mode has one webhook: a test key manages
the test one, a live key the live one.

**Where the notifications go.** Set the URL once per mode (https:// on a public host,
accepting POST requests), or give a payment its own when you create it:

```dart
// Once per mode (safe to repeat):
await payitgo.webhooks.set('https://api.yourdomain.com/payitgo/ipn');

// Or per payment: its events go there instead of the webhook's URL.
await payitgo.payments.create(orderId: 'ORD-1', amountUsd: 10, webhookUrl: 'https://api.yourdomain.com/orders/ipn');

// Or as the client's default for every payment it creates (a payment's own webhookUrl wins):
final shop = Payitgo(key, webhookUrl: 'https://api.yourdomain.com/orders/ipn');
```

A storefront's key cannot set the account's URL (`403`): pass `webhookUrl` on its payments
instead. Payout events (`payout.*`) go to the webhook's URL. A payout request or batch row
made with its own `webhookUrl` sends its events there, else to its batch's `webhookUrl`, else
to the webhook's URL.

**Missed some?** Every event is kept: `payitgo.events.list(after: lastId)` replays them,
oldest first, each exactly as its notification carried it (the same `id`).

**The signing secret.** Every notification of a mode is signed with that mode's secret,
whichever URL it goes to. Copy it from the dashboard or read it with
`(await payitgo.webhooks.get()).secret`, and give it to the client once:

```dart
final payitgo = Payitgo(key, webhookSecret: Platform.environment['PAYITGO_WEBHOOK_SECRET']);
```

**Receiving them** (shelf). Verify the raw body, handle each event once, and answer `2xx`
within 10 seconds; otherwise payitgo retries after 1 min, 5 min, 30 min, 2 h, 6 h and 24 h.

```dart
import 'package:shelf/shelf.dart';

Future<Response> ipn(Request request) async {
  final WebhookEvent event;
  try {
    // Checks the signature with the client's webhookSecret and refuses anything older than 5 minutes.
    event = payitgo.webhooks.constructEvent(
        await request.read().expand((chunk) => chunk).toList(), // the raw body
        request.headers['x-webhook-signature']);
  } on SignatureVerificationException {
    return Response(400);
  }
  // The same event can arrive more than once: handle each event id once,
  // e.g. by inserting it into a table with a unique key.
  if (!await recordEventOnce(event.id)) return Response.ok('');

  switch (event.type) {
    case 'payment.confirmed':
      await jobs.enqueue('fulfil', event.data['order_id'] as String); // slow work off the request
    case 'payment.expired':
      await jobs.enqueue('release-stock', event.data['order_id'] as String);
  }
  return Response.ok('');
}
```

**Testing it.** `await payitgo.webhooks.test()` queues a signed `ping` event to the
webhook's URL and returns its delivery (`400` when no URL is set).

## On your server: payouts

Pay your own clients (withdrawals from your platform, payroll, prizes) from your **payout
wallet**: one address per network that you top up, paying in the payout coins (`USDT_TRC20`,
`USDT_BEP20`, `TRX`, `BNB`, …). payitgo checks and prices every payment before anything leaves
the wallet ([Mass payouts](https://api.payitgo.co/docs/payouts)).
Reading works with any key; the rest needs a key with **payouts** turned on in the dashboard
(`403` otherwise).

**Payout requests, one by one.** Send each client's request as it comes in. payitgo checks
and prices it at once and keeps it in your open list with its costs; you send the list when
you want, or let auto-send in your payout settings send it by itself.

```dart
// A client asks for a withdrawal. Your id for it is the reference: sending it
// again returns the same payment (200 instead of 201), so a retry never pays twice.
final request = await payitgo.payouts.request(
  reference: 'wd-7731',
  asset: 'USDT_TRC20',
  address: 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
  amount: '120',       // a String or a num: prefer a String
  name: 'Ana Silva',   // optional, like email and note
);
if (request.status == 'invalid') {
  // Kept, but never sent: request.errors say why (code, message, hint). Cancel it
  // (payouts.cancel) to free its reference for a corrected request.
  print(request.errors.map((e) => e.message).join('; '));
} else {
  print('fee ${request.fee} ${request.ticker}, the wallet gives ${request.debit}');
}

// The open list: what sending it takes of each coin, and the top-up to send first.
final inbox = await payitgo.payouts.inbox();
for (final c in inbox.coverage) {
  if (c.topUp != '0') print('send ${c.topUp} ${c.asset} to ${c.address}');
}

// Send every valid request (or some: ids: [...]) as a batch: approved when your
// payout settings ask for it, then funded and sent.
final batch = await payitgo.payouts.send();

await payitgo.payouts.retrieve(request.id!);          // or retrieveByReference('wd-7731')
await payitgo.payouts.cancel(request.id!);            // out of the list, or canceled before it goes
await payitgo.payouts.remove(['…', '…']);             // up to 1000 out of the list: a result per id
```

`payouts.quote(items: [...])` prices up to 100 payments without keeping anything: show a
client their fee before they ask.

**Batches: a whole list at once.**

```dart
final batch = await payitgo.payoutBatches.create(
  reference: 'payroll-2026-10',   // safe to retry: the same reference returns this batch
  name: 'October payroll',
  feePaidBy: 'merchant',          // or 'recipient': the fees come out of each amount
  items: [
    PayoutItemInput(reference: 'payroll-2026-10-ana', asset: 'USDT_TRC20',
        address: 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi', amount: '1500', name: 'Ana Silva'),
    PayoutItemInput(reference: 'payroll-2026-10-ben', asset: 'USDT_BEP20',
        address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed', amount: '250'),
  ],
);
// quoted: batch.totals (per coin), batch.totalUsd; the rows left out:
final invalid = await payitgo.payoutBatches.items(batch.id, status: 'invalid');

final submitted = await payitgo.payoutBatches.submit(batch.id);
for (final s in submitted.waiting?.shortfall ?? const <PayoutShortfall>[]) {
  print('top up ${s.amount} ${s.asset} at ${s.address}'); // it starts by itself once funded
}
```

A call takes up to 1000 payments (`addItems` adds more, up to 10,000 in a batch). A batch's
prices hold for an hour: when `submit` answers `409` (`its prices expired`), call
`payoutBatches.quote(id)` and submit again. `cancel(id)` stops it before it is funded.

**Claim links.** When you do not know the recipient's address, ask for a claim link with
`claim: true` or `claimAssets` (the other coins the recipient may choose, paid at the same
dollar value) and leave the address out: its recipient opens the link and chooses the coin
and the address ([Claim links](https://api.payitgo.co/docs/payouts#claim-links)). With an
`email`, payitgo emails the link; without one, you share it yourself. An email alone makes
no claim link: a payment without an address is refused (`invalid_address`).

```dart
final prize = await payitgo.payouts.request(   // or a PayoutItemInput in a batch
  reference: 'prize-cup-final-1',
  asset: 'USDT_TRC20',
  amount: '250',
  claim: true,                                 // no email: share the link yourself
  claimAssets: ['USDT_BEP20', 'BTC'],
);
// Once its batch is funded: status 'claimable', prize.claim!.url to share, until
// prize.claim!.expiresAt (then 'expired', its money free again in the wallet).
```

`payout_item.claimed` says when the recipient chose (`claim.claimedAt`, the payment's
`address`, and `claim.fundedAsset` / `fundedAmount` when they chose another coin);
`payout_item.claim_expired` when nobody did. Batch `counts` add `claimable` and `expired`.
In test mode nothing is emailed: open `claim.url` yourself; the emailed code is always `000000`.

**Converted payments.** To pay recipients in a coin your wallet does not hold, create the
batch (or the quote) with `convert: 'convert'` and the coin to pay from: every payment in
another coin is paid from `convertFrom`, converted on its way
([Conversion](https://api.payitgo.co/docs/payouts#conversion)). Both default to your payout
settings.

```dart
final batch = await payitgo.payoutBatches.create(
  reference: 'payroll-2026-10-btc',
  convert: 'convert',
  convertFrom: 'USDT_TRC20',
  items: [PayoutItemInput(asset: 'BTC', address: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq', amount: '0.01')],
);
final item = (await payitgo.payoutBatches.items(batch.id)).items.single;
// item.asset 'USDT_TRC20', item.amount, item.fee (with item.conversionFee) and item.debit
// are in the wallet's coin; item.convert!.to 'BTC', .toAmount '0.01' (what you asked),
// .estimate (about what arrives) and, once sent, .amountOut (what arrived).
```

A coin that cannot be converted to right now makes the payment `invalid`
(`conversion_unavailable`). A batch with converted payments holds its prices 15 minutes, not
an hour.

**The wallet.** `payoutWallets.list()` returns one `PayoutWallet` per network: its `address`,
and per coin its `balance`, `reserved`, `spendable` and `needed` (the top-up batches waiting
for funds need). Withdrawing from it is done in the dashboard, by the owner, never with a key.

**Test mode.** A test key has a test wallet with balances on paper: top it up, and its
payments are sent on paper within seconds (with made-up `txId`s), webhooks included.

```dart
await payitgo.payoutWallets.simulateTopUp('USDT_TRC20', '1000'); // test keys only
```

**Webhooks.** `payout_batch.quoted`, `.pending_approval`, `.approved`, `.rejected`,
`.awaiting_funds`, `.processing`, `.completed` and `.canceled` carry the batch
(`PayoutBatch(event.data)`); `payout_item.sent`, `.failed` and `.canceled` the payment
(`PayoutItem(event.data)`; a canceled one's `cancelReason`, `canceledBy` and `canceledAt`
say why, who and when), as do a claim link's `payout_item.claimed` and `.claim_expired`, and
a payout request's `payout_item.processing` (it left your list for a batch) and
`payout_item.returned` (it came back to the list); `payout_wallet.withdrawn` and
`payout_wallet.withdrawal_failed` the withdrawal (`PayoutWithdrawal`, with `failReason`). Schedules,
set up in the dashboard, send `payout_schedule.run` (`PayoutSchedule(event.data)`: its
`lastBatchId`, or `lastError`) and, a few days before a run the wallet cannot cover,
`payout_schedule.funding_needed` (`PayoutScheduleFunding(event.data)`: its `schedule` and the
`shortfall` to send).

```dart
switch (event.type) {
  case 'payout_item.sent':
    final item = PayoutItem(event.data);
    await markWithdrawalPaid(item.reference!, item.txId!);
  case 'payout_item.failed' || 'payout_item.canceled':
    final item = PayoutItem(event.data);
    // never sent: its reference is given back, for a new request to use
    await reopenWithdrawal(item.releasedReference ?? item.reference!);
}
```

**Staying in sync.** Every payment, a payout request or a batch row, ends `sent`, `failed`,
`canceled` or `expired`, with one event each, delivered at least once: handle each event `id`
once. Events can arrive out of order: act on the payment's `status` and latest `updatedAt`.
Replay what you missed with `payitgo.events.list(after: lastId)`, and check every payment with
`payitgo.payouts.list(cursor: savedCursor)` (keep its `nextCursor`).

## In a Flutter app: show and follow a payment

```dart
final checkout = PayitgoCheckout();

final payment = await checkout.retrieve(checkoutToken);    // from your backend
// show payment.cryptoAmount, payment.token, payment.depositAddress,
// payment.destinationTag (XRP) and a QR code of payment.qrPayload

await for (final p in checkout.watch(checkoutToken)) {     // polls every 5 s
  if (p.isConfirmed) showPaid();                           // ends once confirmed or failed
}
checkout.close();                                          // when the app no longer needs it
```

`watch` keeps following an expired or underpaid payment for the 24 hours in which a late
payment can still complete it (then the stream ends); cancel the subscription to stop sooner.

On a test payment (`payment.livemode` false), `checkout.simulate(checkoutToken, 'confirmed')`
plays an outcome with no coins, for "simulate" buttons on your test screens; `watch` shows it
([Test mode](https://api.payitgo.co/docs/testing)).

The app only shows status; your backend still fulfils orders from the
`payment.confirmed` webhook. Start with a test key, where you
[simulate](#on-your-server-test-mode) what the customer pays.

## API

```dart
final payitgo = Payitgo(apiKey,             // also baseUrl: payitgo's API, default https://api.payitgo.co
    maxRetries: 2, timeout: Duration(seconds: 30),
    webhookSecret: secret,               // for webhooks.constructEvent
    webhookUrl: 'https://…');            // default webhookUrl of payments.create

await payitgo.isLive();                                    // false for a test key (asks payitgo once)
await payitgo.payments.create(orderId: …, amountUsd: …, token: …, description: …, metadata: {…},
                            customerEmail: …, successUrl: …, cancelUrl: …, webhookUrl: …, simulate: …);
await payitgo.payments.create(orderId: …, priceAmount: …, priceCurrency: …, …); // priced in another currency
await payitgo.payments.selectToken(paymentId, token);      // or your order id: the payment with its coin
await payitgo.payments.simulate(paymentId, 'confirmed');   // test keys: plays the outcome
await payitgo.payments.retrieve(paymentId);                // or your order id
await payitgo.payments.list(status: 'confirmed', storeId: storeId, limit: 50, offset: 0); // every filter optional
await payitgo.tokens.list();                               // [TokenInfo(token, chain, minUsd, networkFeeUsd, feeNote)]
await payitgo.tokens.list(amountUsd: '49.90');             // the coins a $49.90 payment offers, with amountDueUsd (a num works too)
await payitgo.checkout.retrieve(checkoutToken);
await payitgo.payouts.request(reference: …, asset: …, address: …, amount: …, tag: …, name: …, email: …, note: …,
                             claim: …, claimAssets: […], webhookUrl: …); // no address: a claim link
await payitgo.payouts.retrieve(id);                        // PayoutItem; or retrieveByReference(reference)
await payitgo.payouts.list(status: ['sent', 'failed'], updatedSince: …, cursor: …, limit: …); // PayoutPage(items, hasMore, nextCursor)
await payitgo.payouts.inbox(status: 'ready', limit: 50, offset: 0); // PayoutInbox(inbox, coverage, items, total, …)
await payitgo.payouts.send(ids: […]);                      // PayoutBatch; without ids every valid request
await payitgo.payouts.cancel(id);                          // PayoutItem, canceled (safe to retry)
await payitgo.payouts.remove([…]);                         // [PayoutRemoveResult(id, item or error)]
await payitgo.payouts.quote(items: [PayoutItemInput(…)], feePaidBy: …, convert: …, convertFrom: …); // PayoutQuoteResult(quote, items)
await payitgo.payoutBatches.create(items: […], reference: …, name: …, feePaidBy: …, webhookUrl: …,
                                   convert: 'convert', convertFrom: 'USDT_TRC20');
await payitgo.payoutBatches.list(status: …, limit: …, offset: …); // PayoutBatchList
await payitgo.payoutBatches.retrieve(id);                  // PayoutBatch
await payitgo.payoutBatches.items(id, status: 'sent,failed', limit: …, offset: …); // PayoutItemList
await payitgo.payoutBatches.addItems(id, [PayoutItemInput(…)]);
await payitgo.payoutBatches.quote(id);                     // also submit(id), cancel(id): PayoutBatch
await payitgo.payoutWallets.list();                        // [PayoutWallet(chain, address, assets, …)]
await payitgo.payoutWallets.simulateTopUp(asset, amount);  // test keys: the wallets, topped up on paper
await payitgo.webhooks.get();                              // WebhookSettings(livemode, url, secret, createdAt, updatedAt)
await payitgo.webhooks.set(url);                           // WebhookSettings
await payitgo.webhooks.remove();                           // WebhookSettings, url null (the secret stays)
await payitgo.webhooks.test();                             // WebhookDelivery of a "ping" event
await payitgo.events.list(types: ['payout_item.*'], after: …, createdAfter: …, limit: …); // EventPage(events, hasMore)
payitgo.webhooks.constructEvent(rawBody, signatureHeader, secret: …, tolerance: Duration(minutes: 5));
Webhook.constructEvent(rawBody, signatureHeader, secret, tolerance: Duration(minutes: 5)); // no client needed
```

`Payment`, `Deposit`, `WebhookSettings`, `WebhookDelivery` and the payout models
(`PayoutItem`, `PayoutBatch`, `PayoutWallet`, `PayoutWithdrawal`, …) have typed getters
(`status`, `checkoutUrl`, `webhookUrl`, `isConfirmed`, a deposit's `from` and `failReason`, a
payout's `fee` and `txId`, …) and `raw` for every field. Amounts are decimal strings. `Webhooks.events` lists the event types. `payitgo.close()` (and
`PayitgoCheckout.close()`) closes the http.Client the library made for itself; one you pass as
`httpClient` stays yours to close.

## Errors

```dart
try {
  await payitgo.payments.create(orderId: 'ORD-1', amountUsd: 1, token: 'BTC');
} on PayitgoException catch (e) {
  print('${e.status} ${e.message}');   // 400 minimum payment in BTC is $10 right now (network fees)
}
```

`constructEvent` throws `SignatureVerificationException` for a bad signature, a stale
timestamp, or when it has no secret (none passed and no `webhookSecret`).

## Development

```bash
dart pub get && dart test
```
