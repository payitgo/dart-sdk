// Accepts a test payment end to end, on your server:
//
//   1. creates a payment and prints the checkout page to send the customer to
//      (test mode plays a "confirmed" outcome by itself, no coins needed);
//   2. receives its webhook (IPN) on http://localhost:8080/ipn, verifies the
//      signature and fulfils the order once the payment is confirmed.
//
// Run it with your test key and your webhook's signing secret (from the
// dashboard, or `(await payitgo.webhooks.get()).secret`):
//
//   PAYITGO_KEY=<test key> PAYITGO_WEBHOOK_SECRET=<signing secret> dart run example/main.dart
//
// For the webhook to reach your machine, expose port 8080 (with ngrok, say)
// and set that public URL as PAYITGO_WEBHOOK_URL.
import 'dart:io';

import 'package:payitgo/payitgo.dart';

Future<void> main() async {
  final env = Platform.environment;
  final payitgo = Payitgo(
    env['PAYITGO_KEY'] ?? '',
    baseUrl: env['PAYITGO_BASE_URL'], // the API's default when unset
    webhookSecret: env['PAYITGO_WEBHOOK_SECRET'],
    webhookUrl: env['PAYITGO_WEBHOOK_URL'], // this payment's events go here
  );

  // 1. Create the payment. Retrying with the same order id returns the same
  //    payment, so a timeout never charges twice.
  final Payment payment;
  try {
    payment = await payitgo.payments.create(
      orderId: 'ORD-${DateTime.now().millisecondsSinceEpoch}',
      amountUsd: '19.99',
      // What is being paid for: shown to the customer on the checkout page.
      description: '2 x Acme T-shirt',
      token: 'USDT_TRC20', // leave it out to let the customer choose the coin
      successUrl: 'https://yourdomain.com/thanks',
      simulate: await payitgo.isLive() ? null : 'confirmed',
    );
  } on PayitgoException catch (e) {
    stderr.writeln('could not create the payment: $e');
    exitCode = 1;
    payitgo.close();
    return;
  }
  print('payment ${payment.id} for ${payment.description}: ${payment.status}');
  if (payment.checkoutUrl != null) {
    print('send the customer to ${payment.checkoutUrl}');
  }
  print(
      'or show ${payment.cryptoAmount} ${payment.token} to ${payment.depositAddress}');

  // 2. Receive its webhook. Verify the raw body: the signature covers its
  //    exact bytes, so read them before any JSON parsing.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
  print('waiting for webhooks on http://localhost:8080/ipn (Ctrl-C to stop)');
  await for (final request in server) {
    if (request.method != 'POST' || request.uri.path != '/ipn') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    final body = await request
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    final WebhookEvent event;
    try {
      event = payitgo.webhooks
          .constructEvent(body, request.headers.value('x-webhook-signature'));
    } on SignatureVerificationException catch (e) {
      request.response.statusCode = HttpStatus.badRequest; // not from payitgo
      await request.response.close();
      print('refused a webhook: ${e.message}');
      continue;
    }
    // Answer quickly (within 10 seconds), and handle each event once: an
    // event can arrive twice, with the same id.
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
    print('${event.type} (${event.id})');
    if (event.type == 'payment.confirmed') {
      print('order ${event.data['order_id']} is paid: fulfil it');
    }
  }
}
