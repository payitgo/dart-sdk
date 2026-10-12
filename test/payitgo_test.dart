import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payitgo/payitgo.dart';
import 'package:test/test.dart';

// Signed by the gateway's own signer.
const secret = 'whsec_test_secret';
const header =
    't=1760000000,v1=6abd292fdf2ecc51779c161f5d4be2d47236f7a43fbaa9dd7093303904b91a7b';
const body =
    '{"id":"evt_test_123","type":"payment.confirmed","livemode":false,"created_at":"2026-10-09T12:00:00Z","data":{"id":"pay_123","order_id":"ORD-1","status":"confirmed","usd_amount":"10"}}';

String sign(String secret, int t, String body) =>
    't=$t,v1=${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$body'))}';

const webhook = {
  'livemode': false,
  'url': 'https://shop.example/payitgo/ipn',
  'secret': 'whsec_abc',
  'created_at': '2026-10-10T09:00:00Z',
  'updated_at': '2026-10-10T09:05:00Z',
};
const delivery = {
  'id': 'whd_1',
  'merchant_id': 'mch_1',
  'target': 'account',
  'url': 'https://shop.example/payitgo/ipn',
  'event_id': 'evt_1',
  'event_type': 'ping',
  'payload': '{}',
  'status': 'pending',
  'attempts': 0,
  'max_attempts': 7,
  'next_attempt_at': '2026-10-10T12:00:00Z',
  'created_at': '2026-10-10T12:00:00Z',
};

/// A payment whose coin the customer chose on the merchant's own page.
const chosen = {
  'id': 'pay_1',
  'merchant_id': 'mch_1',
  'order_id': 'ORD-7',
  'status': 'pending',
  'livemode': false,
  'token': 'XRP',
  'chain': 'xrp',
  'deposit_address': 'rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe',
  'destination_tag': 1042,
  'crypto_amount': '20',
  'received_amount': '0',
  'usd_amount': '10',
  'amount_due_usd': '10',
  'fees_paid_by_customer': false,
  'network_fee': '0.000012',
  'network_fee_usd': '0.01',
  'settlement': 'custodial',
  'received_usd': '0',
  'rate_locked': '0.5',
  'deposits': [],
  'expires_at': '2026-10-10T12:15:00Z',
  'created_at': '2026-10-10T12:00:00Z',
  'network_fee_note': 'Near-zero fees. Include destination tag — required.',
  'qr_payload': 'rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe',
  'checkout_token': 'ct_abc',
  'checkout_url': 'https://pay.example/ct_abc',
  'description': 'Order 7',
  'metadata': {'cart': '42'},
};

/// A test payment whose simulated outcome has paid it.
const simulated = {
  'id': 'pay_2',
  'merchant_id': 'mch_1',
  'order_id': 'ORD-8',
  'status': 'detecting',
  'livemode': false,
  'simulation': {'outcome': 'confirmed', 'state': 'running'},
  'token': 'USDT_TRC20',
  'chain': 'tron',
  'deposit_address': 'TPk2bpQqWRpXiaUHS9SXnZCDgvwrsuJ71o',
  'crypto_amount': '20',
  'received_amount': '20',
  'usd_amount': '20',
  'amount_due_usd': '20',
  'fees_paid_by_customer': false,
  'network_fee': '1',
  'network_fee_usd': '0.3',
  'settlement': 'custodial',
  'received_usd': '20',
  'rate_locked': '1',
  'deposits': [
    {
      'tx_id': 'sim_pay_2_1791817211348_0',
      'token': 'USDT_TRC20',
      'chain': 'tron',
      'amount': '20',
      'usd_value': '20',
      'counted': true,
      'status': 'pending',
      'seen_at': '2026-10-10T12:00:05Z',
      'simulated': true,
    }
  ],
  'expires_at': '2026-10-10T12:15:00Z',
  'created_at': '2026-10-10T12:00:00Z',
  'network_fee_note': 'Near-zero fees on Tron. Fastest settlement.',
  'qr_payload': 'TPk2bpQqWRpXiaUHS9SXnZCDgvwrsuJ71o',
};

/// A client whose requests go to [requests] and are answered with [status]
/// and [reply] (by default: a created payment's body echoed back as the
/// payment), without any network.
Payitgo fakeGateway(List<http.Request> requests, int status,
        [Object? reply, String? webhookUrl]) =>
    Payitgo('sk_test_abc',
        baseUrl: 'https://gateway.test/',
        maxRetries: 0,
        webhookUrl: webhookUrl, httpClient: MockClient((req) async {
      requests.add(req);
      final answer = reply ?? {'id': 'pay_1', ...jsonDecode(req.body) as Map};
      return http.Response(jsonEncode(answer), status,
          headers: {'content-type': 'application/json'});
    }));

void main() {
  group('Webhook.constructEvent', () {
    test('accepts a delivery signed by the gateway', () {
      final e = Webhook.constructEvent(body, header, secret,
          tolerance: Duration.zero);
      expect(e.type, 'payment.confirmed');
      expect(e.data['order_id'], 'ORD-1');
      expect(e.livemode, isFalse);
    });
    test('accepts bytes', () {
      expect(
          Webhook.constructEvent(utf8.encode(body), header, secret,
                  tolerance: Duration.zero)
              .id,
          'evt_test_123');
    });
    test('rejects a changed body, the wrong secret, a missing header', () {
      expect(
          () => Webhook.constructEvent(
              body.replaceFirst('"10"', '"1000"'), header, secret,
              tolerance: Duration.zero),
          throwsA(isA<SignatureVerificationException>()));
      expect(
          () => Webhook.constructEvent(body, header, 'whsec_other',
              tolerance: Duration.zero),
          throwsA(isA<SignatureVerificationException>()));
      expect(() => Webhook.constructEvent(body, null, secret),
          throwsA(isA<SignatureVerificationException>()));
    });
    test('rejects an old timestamp, accepts a fresh one', () {
      expect(() => Webhook.constructEvent(body, header, secret),
          throwsA(isA<SignatureVerificationException>()));
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(Webhook.constructEvent(body, sign(secret, now, body), secret).id,
          'evt_test_123');
    });
  });

  group('webhook (IPN)', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('get reads the mode\'s webhook', () async {
      final payitgo = fakeGateway(requests, 200, {'webhook': webhook});
      final w = await payitgo.webhooks.get();
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(), 'https://gateway.test/v1/webhook');
      expect(requests.single.headers['Authorization'], 'Bearer sk_test_abc');
      expect(requests.single.body, isEmpty);
      expect(w.url, 'https://shop.example/payitgo/ipn');
      expect(w.secret, 'whsec_abc');
      expect(w.livemode, isFalse);
      expect(w.updatedAt, DateTime.utc(2026, 10, 10, 9, 5));
    });

    test('set puts the URL', () async {
      final payitgo = fakeGateway(requests, 200, {'webhook': webhook});
      final w = await payitgo.webhooks.set('https://shop.example/payitgo/ipn');
      expect(requests.single.method, 'PUT');
      expect(requests.single.url.path, '/v1/webhook');
      expect(requests.single.headers['Content-Type'],
          startsWith('application/json'));
      expect(jsonDecode(requests.single.body),
          {'url': 'https://shop.example/payitgo/ipn'});
      expect(w.url, 'https://shop.example/payitgo/ipn');
    });

    test('remove deletes the URL and keeps the secret', () async {
      final payitgo = fakeGateway(requests, 200, {
        'webhook': {...webhook, 'url': null}
      });
      final w = await payitgo.webhooks.remove();
      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.path, '/v1/webhook');
      expect(w.url, isNull);
      expect(w.secret, 'whsec_abc');
    });

    test('test queues a ping', () async {
      final payitgo = fakeGateway(requests, 202, {'delivery': delivery});
      final d = await payitgo.webhooks.test();
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/v1/webhook/test');
      expect(requests.single.headers['Authorization'], 'Bearer sk_test_abc');
      expect(d.eventType, 'ping');
      expect(d.target, 'account');
      expect(d.status, 'pending');
      expect(d.maxAttempts, 7);
      expect(d.deliveredAt, isNull);
      expect(d.history, isEmpty);
    });

    test('errors carry the message and status', () async {
      final noUrl = fakeGateway(requests, 400,
          {'error': 'no webhook url is set for this mode: set one first'});
      await expectLater(
          noUrl.webhooks.test(),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message',
                  'no webhook url is set for this mode: set one first')));
      const forbidden =
          "a storefront's key cannot change the account's webhook: set webhook_url on its payments instead";
      final store = fakeGateway(requests, 403, {'error': forbidden});
      await expectLater(
          store.webhooks.set('https://shop.example/payitgo/ipn'),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 403)
              .having((e) => e.message, 'message', forbidden)));
    });

    test('payments.create sends no webhook_url without one', () async {
      final payitgo = fakeGateway(requests, 201);
      final p = await payitgo.payments.create(orderId: 'ORD-1', amountUsd: 10);
      expect(jsonDecode(requests.single.body),
          {'order_id': 'ORD-1', 'amount_usd': '10'});
      expect(p.webhookUrl, isNull);
    });

    test('payments.create sends its own webhook_url', () async {
      final payitgo = fakeGateway(requests, 201);
      final p = await payitgo.payments.create(
          orderId: 'ORD-1',
          amountUsd: 10,
          webhookUrl: 'https://shop.example/own');
      expect(jsonDecode(requests.single.body)['webhook_url'],
          'https://shop.example/own');
      expect(p.webhookUrl, 'https://shop.example/own');
    });

    test('payments.create sends the client\'s webhookUrl; its own wins',
        () async {
      final payitgo =
          fakeGateway(requests, 201, null, 'https://shop.example/default');
      final p = await payitgo.payments.create(orderId: 'ORD-1', amountUsd: 10);
      expect(jsonDecode(requests[0].body)['webhook_url'],
          'https://shop.example/default');
      expect(p.webhookUrl, 'https://shop.example/default');
      await payitgo.payments.create(
          orderId: 'ORD-2',
          amountUsd: 10,
          webhookUrl: 'https://shop.example/own');
      expect(jsonDecode(requests[1].body)['webhook_url'],
          'https://shop.example/own');
    });
  });

  group('tokens.list', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('lists every token, or a payment of an amount\'s options', () async {
      final payitgo = fakeGateway(requests, 200, {
        'tokens': [
          {
            'token': 'USDT_BEP20',
            'chain': 'bsc',
            'min_usd': '1',
            'network_fee_usd': '0.01',
            'amount_due_usd': '40.43',
            'fee_note': ''
          }
        ]
      });
      final all = await payitgo.tokens.list();
      expect(requests[0].method, 'GET');
      expect(requests[0].url.toString(), 'https://gateway.test/v1/tokens');
      expect(all.single.token, 'USDT_BEP20');
      final forAmount = await payitgo.tokens.list(amountUsd: '49.90');
      expect(requests[1].url.toString(),
          'https://gateway.test/v1/tokens?amount_usd=49.90');
      expect(forAmount.single.amountDueUsd, '40.43');
    });
  });

  group('payments.selectToken', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('posts the coin with the key and returns the whole payment', () async {
      final payitgo = fakeGateway(requests, 200, chosen);
      final p = await payitgo.payments.selectToken('pay_1', 'XRP');
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payments/pay_1/token');
      expect(requests.single.headers['Authorization'], 'Bearer sk_test_abc');
      expect(requests.single.headers['Content-Type'],
          startsWith('application/json'));
      expect(jsonDecode(requests.single.body), {'token': 'XRP'});
      expect(p.raw, chosen);
      expect(p.token, 'XRP');
      expect(p.chain, 'xrp');
      expect(p.depositAddress, 'rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe');
      expect(p.destinationTag, 1042);
      expect(p.cryptoAmount, '20');
      expect(p.rateLocked, '0.5');
      expect(p.qrPayload, 'rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe');
      expect(p.expiresAt, DateTime.utc(2026, 10, 10, 12, 15));
      expect(p.checkoutToken, 'ct_abc');
      expect(p.checkoutUrl, 'https://pay.example/ct_abc');
      expect(p.metadata, {'cart': '42'});
      expect(p.tokenOptions, isEmpty);
    });

    test('escapes an order id in the path, as retrieve does', () async {
      final payitgo = fakeGateway(requests, 200, chosen);
      await payitgo.payments.selectToken('ORD 7/1', 'XRP');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payments/ORD%207%2F1/token');
    });

    test('a coin already chosen is a 409', () async {
      const message = 'the coin for this payment has already been chosen';
      final payitgo = fakeGateway(requests, 409, {'error': message});
      await expectLater(
          payitgo.payments.selectToken('pay_1', 'XRP'),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.message, 'message', message)));
    });
  });

  group('payments.simulate', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('posts the outcome with the key and returns the payment', () async {
      final payitgo = fakeGateway(requests, 200, simulated);
      final p = await payitgo.payments.simulate('pay_2', 'confirmed');
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payments/pay_2/simulate');
      expect(requests.single.headers['Authorization'], 'Bearer sk_test_abc');
      expect(requests.single.headers['Content-Type'],
          startsWith('application/json'));
      expect(jsonDecode(requests.single.body), {'outcome': 'confirmed'});
      expect(p.raw, simulated);
      expect((p.simulation!.outcome, p.simulation!.state),
          ('confirmed', 'running'));
      expect(p.deposits.single.simulated, isTrue);
      expect(p.deposits.single.txId, startsWith('sim_'));
      expect(Payment(chosen).simulation, isNull);
      expect(Deposit({'tx_id': 'c19240'}).simulated, isFalse);
    });

    test('escapes an order id in the path, as retrieve does', () async {
      final payitgo = fakeGateway(requests, 200, simulated);
      await payitgo.payments.simulate('ORD 8/1', 'expired');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payments/ORD%208%2F1/simulate');
    });

    test('a simulation still running is a 409', () async {
      const message = 'a simulation is already running for this payment';
      final payitgo = fakeGateway(requests, 409, {'error': message});
      await expectLater(
          payitgo.payments.simulate('pay_2', 'confirmed'),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.message, 'message', message)));
    });

    test('payments.create sends simulate', () async {
      final payitgo = fakeGateway(requests, 201, simulated);
      final p = await payitgo.payments.create(
          orderId: 'ORD-8',
          amountUsd: 20,
          token: 'USDT_TRC20',
          simulate: 'confirmed');
      expect(jsonDecode(requests.single.body), {
        'order_id': 'ORD-8',
        'amount_usd': '20',
        'token': 'USDT_TRC20',
        'simulate': 'confirmed'
      });
      expect(p.simulation!.outcome, 'confirmed');
      expect(Payments.simulationOutcomes, contains('confirmed'));
    });
  });

  group('client webhooks.constructEvent', () {
    test('uses the client\'s webhookSecret', () {
      final payitgo =
          Payitgo('sk_test_abc', baseUrl: 'http://x', webhookSecret: secret);
      expect(
          payitgo.webhooks
              .constructEvent(body, header, tolerance: Duration.zero)
              .id,
          'evt_test_123');
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(payitgo.webhooks.constructEvent(body, sign(secret, now, body)).id,
          'evt_test_123');
    });
    test('an explicit secret wins', () {
      final payitgo = Payitgo('sk_test_abc',
          baseUrl: 'http://x', webhookSecret: 'whsec_other');
      expect(
          () => payitgo.webhooks
              .constructEvent(body, header, tolerance: Duration.zero),
          throwsA(isA<SignatureVerificationException>()));
      expect(
          payitgo.webhooks
              .constructEvent(body, header,
                  secret: secret, tolerance: Duration.zero)
              .id,
          'evt_test_123');
    });
    test('throws without any secret', () {
      final payitgo = Payitgo('sk_test_abc', baseUrl: 'http://x');
      expect(
          () => payitgo.webhooks.constructEvent(body, header),
          throwsA(isA<SignatureVerificationException>().having(
              (e) => e.message, 'message', contains('no webhook secret'))));
    });
  });

  group('payments.list', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('sends its filters, store_id included', () async {
      final payitgo = fakeGateway(requests, 200, {
        'payments': [chosen],
        'total': 1,
        'limit': 10,
        'offset': 20
      });
      final page = await payitgo.payments
          .list(status: 'pending', storeId: 'sto_1', limit: 10, offset: 20);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payments?status=pending&store_id=sto_1&limit=10&offset=20');
      expect(page.payments.single.id, 'pay_1');
      expect((page.total, page.limit, page.offset), (1, 10, 20));
    });
  });

  test('a deposit has a getter for every field the gateway sends', () {
    final d = Payment({
      ...chosen,
      'deposits': [
        {
          'tx_id': 'c19240',
          'token': 'USDT_TRC20',
          'chain': 'tron',
          'amount': '49.9',
          'usd_value': '49.9',
          'counted': true,
          'late': true,
          'status': 'failed',
          'seen_at': '2026-10-10T09:03:02.418Z',
          'confirmed_at': '2026-10-10T09:04:03.77Z',
          'from': 'TL8wHk',
          'block': 79412538,
          'made_at': '2026-10-10T09:02:57Z',
          'failed_at': '2026-10-10T15:03:02Z',
          'fail_reason': 'confirmation timeout',
        }
      ]
    }).deposits.single;
    expect((d.txId, d.token, d.chain, d.amount, d.usdValue),
        ('c19240', 'USDT_TRC20', 'tron', '49.9', '49.9'));
    expect((d.counted, d.late, d.status), (true, true, 'failed'));
    expect(d.seenAt, DateTime.utc(2026, 10, 10, 9, 3, 2, 418));
    expect(d.confirmedAt, DateTime.utc(2026, 10, 10, 9, 4, 3, 770));
    expect((d.from, d.block), ('TL8wHk', 79412538));
    expect(d.madeAt, DateTime.utc(2026, 10, 10, 9, 2, 57));
    expect(d.failedAt, DateTime.utc(2026, 10, 10, 15, 3, 2));
    expect(d.failReason, 'confirmation timeout');
    final bare = Deposit({
      'tx_id': 'x',
      'token': 'TRX',
      'chain': 'tron',
      'amount': '1',
      'usd_value': '0.3',
      'counted': true,
      'status': 'pending',
      'seen_at': '2026-10-10T09:03:02Z',
    });
    expect([bare.confirmedAt, bare.from, bare.block, bare.madeAt],
        everyElement(isNull));
    expect([bare.failedAt, bare.failReason], everyElement(isNull));
  });

  test('tokens.list takes the amount as a String or a num', () async {
    final requests = <http.Request>[];
    final payitgo = fakeGateway(requests, 200, {'tokens': []});
    await payitgo.tokens.list(amountUsd: 49.9);
    await payitgo.tokens.list(amountUsd: '49.90');
    expect(requests.map((r) => r.url.query),
        ['amount_usd=49.9', 'amount_usd=49.90']);
  });

  group('close', () {
    test('leaves an http.Client you passed open', () {
      final client = _Closable();
      final payitgo =
          Payitgo('sk_test_abc', baseUrl: 'http://x', httpClient: client);
      payitgo.checkout.close();
      payitgo.close();
      PayitgoCheckout(baseUrl: 'http://x', httpClient: client).close();
      expect(client.closed, isFalse);
    });

    test('closes the one client the SDK made, which checkout shares', () async {
      final payitgo =
          Payitgo('sk_test_abc', baseUrl: 'http://x', maxRetries: 0);
      payitgo.close();
      final closed = isA<PayitgoException>()
          .having((e) => e.status, 'status', 0)
          .having((e) => e.message, 'message', contains('closed'));
      await expectLater(payitgo.webhooks.get(), throwsA(closed));
      await expectLater(payitgo.checkout.retrieve('cs_1'), throwsA(closed));
      final checkout = PayitgoCheckout(baseUrl: 'http://x')..close();
      await expectLater(checkout.retrieve('cs_1'), throwsA(closed));
    });

    test('the checkout of a Payitgo does not close the shared client',
        () async {
      final payitgo =
          Payitgo('sk_test_abc', baseUrl: 'http://127.0.0.1:9', maxRetries: 0);
      payitgo.checkout.close();
      // Still open: the request goes out (and is refused by the closed port, not
      // by a closed client).
      await expectLater(
          payitgo.webhooks.get(),
          throwsA(isA<PayitgoException>()
              .having((e) => e.message, 'message', isNot(contains('closed')))));
      payitgo.close();
    });
  });

  test('checkout.simulate posts the outcome, without a key', () async {
    late http.Request sent;
    final checkout = PayitgoCheckout(
        baseUrl: 'https://gateway.test',
        httpClient: MockClient((req) async {
          sent = req;
          return http.Response(
              jsonEncode({
                ...chosen,
                'simulation': {'outcome': 'confirmed', 'state': 'running'},
              }),
              200,
              headers: {'content-type': 'application/json'});
        }));
    final p = await checkout.simulate('cs_1/2', 'confirmed');
    expect(sent.method, 'POST');
    expect(
        sent.url.toString(), 'https://gateway.test/checkout/cs_1%2F2/simulate');
    expect(jsonDecode(sent.body), {'outcome': 'confirmed'});
    expect(sent.headers.containsKey('authorization'), isFalse);
    expect(p.simulation?.state, 'running');
  });

  group('checkout.watch', () {
    PayitgoCheckout answering(List<Map<String, Object?>> views) {
      var i = 0;
      return PayitgoCheckout(
          baseUrl: 'https://gateway.test',
          httpClient: MockClient((req) async => http.Response(
              jsonEncode(views[i < views.length ? i++ : views.length - 1]), 200,
              headers: {'content-type': 'application/json'})));
    }

    Map<String, Object?> view(String status,
            {String token = 'XRP', DateTime? expiresAt}) =>
        {
          ...chosen,
          'status': status,
          'token': token,
          'expires_at': (expiresAt ?? DateTime.now().toUtc()).toIso8601String(),
        };

    test('follows an expired payment to its late confirmation', () async {
      final checkout = answering([
        view('pending'),
        view('expired'),
        view('expired'),
        view('detecting'),
        view('confirmed'),
      ]);
      final statuses = await checkout
          .watch('cs_1', every: Duration.zero)
          .map((p) => p.status)
          .toList();
      expect(statuses, ['pending', 'expired', 'detecting', 'confirmed']);
    });

    test('ends on failed', () async {
      final statuses = await answering([view('detecting'), view('failed')])
          .watch('cs_1', every: Duration.zero)
          .map((p) => p.status)
          .toList();
      expect(statuses, ['detecting', 'failed']);
    });

    test('ends on a payment expired without a coin', () async {
      final statuses = await answering([view('expired', token: '')])
          .watch('cs_1', every: Duration.zero)
          .map((p) => p.status)
          .toList();
      expect(statuses, ['expired']);
    });

    test('ends once the 24 hours for late payments are over', () async {
      final longAgo = DateTime.now().toUtc().subtract(const Duration(days: 2));
      final statuses = await answering([
        view('underpaid', expiresAt: longAgo),
      ]).watch('cs_1', every: Duration.zero).map((p) => p.status).toList();
      expect(statuses, ['underpaid']);
    });
  });

  test('client checks the key and the base URL', () {
    expect(() => Payitgo('pk_123', baseUrl: 'http://x'), throwsArgumentError);
    expect(() => Payitgo('sk_test_abc', baseUrl: ''), throwsArgumentError);
    expect(() => PayitgoCheckout(baseUrl: ''), throwsArgumentError);
    expect(Payitgo('sk_live_abc', baseUrl: 'http://x').livemode, isTrue);
    expect(Payitgo('sk_test_abc', baseUrl: 'http://x').livemode, isFalse);
  });
}

/// An http.Client that records whether it was closed.
class _Closable extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}
