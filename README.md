# payitgo for Dart and Flutter

Accept crypto payments with [payitgo](https://api.payitgo.co/docs) from Dart 3.

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
  baseUrl: Platform.environment['PAYITGO_BASE_URL']!,
  webhookSecret: Platform.environment['PAYITGO_WEBHOOK_SECRET'], // "whsec_…": see Webhooks (IPN) below
);

// 1. Create a payment and send the customer to the checkout page (or return the
//    checkout_token to your Flutter app).
final payment = await payitgo.payments.create(
  orderId: 'ORD-1001',   // your order id: safe to retry
  amountUsd: 19.99,
  // token: 'USDT_TRC20',   // optional: without it the customer picks the coin
  successUrl: 'https://shop.example/thanks',
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

The coin is chosen once: choosing again is a `409` (`payments.retrieve` then returns the
payment with its coin). A coin outside `tokenOptions`, or a payment that can no longer be
paid, is a `400`.

## On your server: Webhooks (IPN)

payitgo POSTs a signed notification for every change of a payment (`payment.confirmed`,
`payment.expired`, …), of a direct settlement and of a payout. Each mode has one webhook:
a test key manages the test one, a live key the live one.

**Where the notifications go.** Set the URL once per mode (https:// on a public host,
accepting POST requests), or give a payment its own when you create it:

```dart
// Once per mode (safe to repeat):
await payitgo.webhooks.set('https://shop.example/payitgo/ipn');

// Or per payment: its events go there instead of the webhook's URL.
await payitgo.payments.create(orderId: 'ORD-1', amountUsd: 10, webhookUrl: 'https://shop.example/orders/ipn');

// Or as the client's default for every payment it creates (a payment's own webhookUrl wins):
final shop = Payitgo(key, baseUrl: baseUrl, webhookUrl: 'https://shop.example/orders/ipn');
```

A storefront's key cannot set the account's URL (`403`): pass `webhookUrl` on its payments
instead. Payout events always go to the webhook's URL.

**The signing secret.** Every notification of a mode is signed with that mode's secret
(`whsec_…`), whichever URL it goes to. Copy it from the dashboard or read it with
`(await payitgo.webhooks.get()).secret`, and give it to the client once:

```dart
final payitgo = Payitgo(key, baseUrl: baseUrl, webhookSecret: Platform.environment['PAYITGO_WEBHOOK_SECRET']);
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

## In a Flutter app: show and follow a payment

```dart
final checkout = PayitgoCheckout(baseUrl: 'https://api.example.com');

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

The app only shows status; your backend still fulfils orders from the
`payment.confirmed` webhook. Start with your test key (`sk_test_…`) and testnet coins.

## API

```dart
final payitgo = Payitgo(apiKey,
    baseUrl: 'https://api.example.com',  // or the package's default address
    maxRetries: 2, timeout: Duration(seconds: 30),
    webhookSecret: 'whsec_…',            // for webhooks.constructEvent
    webhookUrl: 'https://…');            // default webhookUrl of payments.create

payitgo.livemode;                                          // false for sk_test_ keys
await payitgo.payments.create(orderId: …, amountUsd: …, token: …, description: …, metadata: {…},
                            customerEmail: …, successUrl: …, cancelUrl: …, webhookUrl: …);
await payitgo.payments.selectToken('pay_…', token);        // or your order id: the payment with its coin
await payitgo.payments.retrieve('pay_…');                  // or your order id
await payitgo.payments.list(status: 'confirmed', storeId: 'sto_…', limit: 50, offset: 0); // every filter optional
await payitgo.tokens.list();                               // [TokenInfo(token, chain, minUsd, networkFeeUsd, feeNote)]
await payitgo.tokens.list(amountUsd: '49.90');             // the coins a $49.90 payment offers, with amountDueUsd (a num works too)
await payitgo.checkout.retrieve(checkoutToken);
await payitgo.webhooks.get();                              // WebhookSettings(livemode, url, secret, createdAt, updatedAt)
await payitgo.webhooks.set(url);                           // WebhookSettings
await payitgo.webhooks.remove();                           // WebhookSettings, url null (the secret stays)
await payitgo.webhooks.test();                             // WebhookDelivery of a "ping" event
payitgo.webhooks.constructEvent(rawBody, signatureHeader, secret: …, tolerance: Duration(minutes: 5));
Webhook.constructEvent(rawBody, signatureHeader, secret, tolerance: Duration(minutes: 5)); // no client needed
```

`Payment`, `Deposit`, `WebhookSettings` and `WebhookDelivery` have typed getters (`status`,
`checkoutUrl`, `webhookUrl`, `isConfirmed`, a deposit's `from` and `failReason`, …) and `raw`
for every field. `Webhooks.events` lists the event types. `payitgo.close()` (and
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
