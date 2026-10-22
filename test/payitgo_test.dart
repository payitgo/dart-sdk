import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payitgo/payitgo.dart';
import 'package:test/test.dart';

const key = '8334dfeae25b9b200b75995e6e55cf8c3602120c1920bfef7a4ff8900b620881';

// Signed by the gateway's own signer.
const secret =
    '05bd6b428158318cc38756fa34aa60795af0fc5d9a316dcc9b060c8ca1863fc3';
const header =
    't=1760000000,v1=75eb20fb34bccab4b9121285930b076e5e60ccad0a2542bd76eb56d89744faed';
const body =
    '{"id":"b8e1f80bd70ae0784c7855a4","type":"payment.confirmed","livemode":false,"created_at":"2026-10-09T12:00:00Z","data":{"id":"040ffd5925d40e11c67b7238","order_id":"ORD-1","status":"confirmed","usd_amount":"10"}}';
const otherSecret =
    'bd4106123e659e259c401119d0c7ef0a221df306a5a414b6fb6a579499962d26';

String sign(String secret, int t, String body) =>
    't=$t,v1=${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$body'))}';

const webhook = {
  'livemode': false,
  'url': 'https://shop.example/payitgo/ipn',
  'secret':
      'abababababababababababababababababababababababababababababababab',
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
  'settlement': 'custodial',
  'received_usd': '0',
  'rate_locked': '0.5',
  'deposits': [],
  'expires_at': '2026-10-10T12:15:00Z',
  'created_at': '2026-10-10T12:00:00Z',
  'network_fee_note': 'Final in seconds. Include the destination tag: it is required.',
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
  'settlement': 'custodial',
  'received_usd': '20',
  'rate_locked': '1',
  'deposits': [
    {
      'tx_id':
          '8de0120d502929788a71a7b7cf60e5ef3c095cdbb05cd8a7ddabc0bc9ffa9582',
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
  'network_fee_note': 'Final in about a minute.',
  'qr_payload': 'TPk2bpQqWRpXiaUHS9SXnZCDgvwrsuJ71o',
};

/// A payment priced in euros: the gateway converted the price into
/// usd_amount at price_rate.
final priced = {
  ...chosen,
  'order_id': 'ORD-10',
  'usd_amount': '49.23',
  'amount_due_usd': '49.23',
  'price_amount': '45.5',
  'price_currency': 'EUR',
  'price_rate': '1.082',
};

/// A payout request that was sent: a payment of a batch.
const payoutItem = {
  'id': '8b2d4f6a1c3e5a7b9d0f2c4e',
  'merchant_id': 'mch_1',
  'livemode': false,
  'batch_id': '6a1f3c8e2d9b4a7051c3e8f2',
  'reference': 'wd-1001',
  'row': 1,
  'recipient': {'name': 'Ana Silva', 'email': 'ana@example.com'},
  'asset': 'USDT_TRC20',
  'ticker': 'USDT',
  'icon_url': 'https://api.payitgo.co/coins/USDT_TRC20.svg',
  'chain': 'tron',
  'address': 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
  'amount': '120',
  'send_amount': '120',
  'fee': '6.348213',
  'debit': '126.348213',
  'usd_rate': '1',
  'amount_usd': '120',
  'status': 'sent',
  'errors': [],
  'warnings': [
    {
      'code': 'new_recipient',
      'field': 'address',
      'message': 'you never paid this address',
    }
  ],
  'tx_id': '3c9f1a7e5b2d8c4f6a0e9b3d7c1f5a2e8b4d0c6f9a3e7b1d5c8f2a6e0b4d9c3f',
  'sent_at': '2026-10-20T09:31:12.6Z',
  'created_at': '2026-10-20T09:15:01.88Z',
  'updated_at': '2026-10-20T09:31:12.6Z',
};

/// A payout request kept in the open list, invalid.
const invalidItem = {
  'id': '4e6a8c0b2d4f6a1c3e5b7d9a',
  'merchant_id': 'mch_1',
  'livemode': false,
  'batch_id': 'inbox_1',
  'reference': 'wd-1002',
  'row': 2,
  'recipient': {},
  'asset': 'USDT_BEP20',
  'chain': 'bsc',
  'address': 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7',
  'amount': '75',
  'send_amount': '0',
  'fee': '0',
  'debit': '0',
  'usd_rate': '0',
  'amount_usd': '0',
  'status': 'invalid',
  'errors': [
    {
      'code': 'wrong_network',
      'field': 'address',
      'message': 'this address is for Tron, not BNB Smart Chain',
      'hint': 'pay it in a coin of that network, or check the address',
    }
  ],
  'warnings': null,
  'created_at': '2026-10-20T09:15:01.88Z',
  'updated_at': '2026-10-20T09:15:02.4Z',
};

/// A payout request a team member removed from the list: its record stays,
/// without a batch.
const removedItem = {
  'id': '5c7e9a1b3d5f7a9c1e3b5d7f',
  'merchant_id': 'mch_1',
  'livemode': false,
  'released_reference': 'wd-88231',
  'row': 4,
  'recipient': {},
  'asset': 'USDT_TRC20',
  'chain': 'tron',
  'address': 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
  'amount': '40',
  'send_amount': '40',
  'fee': '2.102417',
  'debit': '42.102417',
  'usd_rate': '1',
  'amount_usd': '40',
  'status': 'canceled',
  'errors': [],
  'warnings': [],
  'cancel_reason': 'removed',
  'canceled_by': 'usr_7',
  'canceled_at': '2026-10-20T14:02:44.312Z',
  'members': {'usr_7': 'finance@example.com'},
  'webhook_url': 'https://shop.example/payouts/ipn',
  'created_at': '2026-10-20T13:15:01.88Z',
  'updated_at': '2026-10-20T14:02:44.312Z',
};

const usdtTotal = {
  'asset': 'USDT_TRC20',
  'ticker': 'USDT',
  'icon_url': 'https://api.payitgo.co/coins/USDT_TRC20.svg',
  'chain': 'tron',
  'network': 'Tron (TRC-20)',
  'items': 1,
  'amount': '120',
  'send_amount': '120',
  'fee': '6.348213',
  'debit': '126.348213',
  'debit_usd': '126.35',
  'saved_usd': '0',
};

const counts = {
  'total': 2,
  'invalid': 1,
  'ready': 1,
  'cooling': 0,
  'queued': 0,
  'sending': 0,
  'sent': 0,
  'failed': 0,
  'canceled': 0,
};

/// A submitted batch the wallet cannot cover yet.
const payoutBatch = {
  'id': '6a1f3c8e2d9b4a7051c3e8f2',
  'merchant_id': 'mch_1',
  'livemode': false,
  'reference': 'payroll-2026-10',
  'name': 'October payroll',
  'source': 'api',
  'inbox': false,
  'open': false,
  'created_by': 'key_1',
  'by_api_key': true,
  'fee_paid_by': 'merchant',
  'status': 'awaiting_funds',
  'waiting': {
    'reason': 'funds',
    'note': 'top up the payout wallet: 126.348213 USDT_TRC20 on Tron (TRC-20)',
    'since': '2026-10-20T09:16:40.12Z',
    'shortfall': [
      {
        'asset': 'USDT_TRC20',
        'network': 'Tron (TRC-20)',
        'amount': '126.348213',
        'address': 'TMkq7dZ3vN8xR2pB6cH9sJ4fL1wY5tGaQe',
      }
    ],
  },
  'totals': [usdtTotal],
  'counts': counts,
  'total_usd': '126.35',
  'quote_expires_at': '2026-10-20T10:15:02.41Z',
  'approvals_needed': 0,
  'approvals': null,
  'submitted_by': 'key_1',
  'submitted_at': '2026-10-20T09:16:40.09Z',
  'created_at': '2026-10-20T09:15:01.87Z',
  'updated_at': '2026-10-20T09:16:40.12Z',
};

/// The open list of payout requests.
const openList = {
  'id': 'inbox_1',
  'merchant_id': 'mch_1',
  'livemode': false,
  'name': 'Payout requests',
  'source': 'requests',
  'inbox': true,
  'open': true,
  'created_by': 'requests',
  'by_api_key': false,
  'fee_paid_by': 'merchant',
  'status': 'quoted',
  'totals': [usdtTotal],
  'counts': counts,
  'total_usd': '126.35',
  'approvals_needed': 0,
  'approvals': [],
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:15:02.4Z',
};

const payoutWallets = [
  {
    'chain': 'tron',
    'network': 'Tron',
    'address': 'TMkq7dZ3vN8xR2pB6cH9sJ4fL1wY5tGaQe',
    'livemode': false,
    'assets': [
      {
        'asset': 'USDT_TRC20',
        'ticker': 'USDT',
        'icon_url': 'https://api.payitgo.co/coins/USDT_TRC20.svg',
        'balance': '1000',
        'reserved': '126.348213',
        'spendable': '873.651787',
        'needed': '0',
      }
    ],
  },
  {
    'chain': 'bsc',
    'network': 'BNB Smart Chain',
    'address': '0x8F3a6B2c9D1e4F7a0B5c8D2e6F9a1B4c7D0e3F6a',
    'livemode': false,
    'assets': [],
    'error': 'balances unavailable: try again in a moment',
  },
];

/// A claim link funded and waiting for its recipient.
const claimItem = {
  'id': '7a9c1e3b5d7f9a1c3e5b7d9f',
  'merchant_id': 'mch_1',
  'livemode': false,
  'batch_id': '6a1f3c8e2d9b4a7051c3e8f2',
  'reference': 'prize-cup-1',
  'row': 3,
  'recipient': {'name': 'Player One', 'email': 'player@example.com'},
  'asset': 'USDT_TRC20',
  'ticker': 'USDT',
  'chain': 'tron',
  'address': '',
  'amount': '250',
  'send_amount': '250',
  'fee': '2.852417',
  'debit': '252.852417',
  'usd_rate': '1',
  'amount_usd': '250',
  'status': 'claimable',
  'errors': [],
  'warnings': [],
  'claim': {
    'email': 'player@example.com',
    'assets': ['USDT_BEP20', 'BTC'],
    'expires_at': '2026-11-19T09:20:00Z',
    'emailed': 1,
    'last_email_at': '2026-10-20T09:20:01Z',
    'extended': 0,
    'url': 'https://pay.example/claim/Zm9vYmFy',
  },
  'created_at': '2026-10-20T09:15:01.88Z',
  'updated_at': '2026-10-20T09:20:01Z',
};

/// A payment in BTC paid from the wallet's USDT, converted on its way.
const convertedItem = {
  'id': '9c1e3b5d7f9a1c3e5b7d9f1a',
  'merchant_id': 'mch_1',
  'livemode': false,
  'batch_id': 'b_conv',
  'row': 1,
  'recipient': {},
  'asset': 'USDT_TRC20',
  'ticker': 'USDT',
  'chain': 'tron',
  'address': 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
  'amount': '650.12',
  'send_amount': '650.12',
  'fee': '13.572417',
  'debit': '663.692417',
  'usd_rate': '1',
  'amount_usd': '650.12',
  'status': 'sent',
  'errors': [],
  'warnings': [],
  'convert': {
    'to': 'BTC',
    'ticker': 'BTC',
    'network': 'Bitcoin',
    'to_amount': '0.01',
    'estimate': '0.00998',
    'amount_out': '0.00999',
  },
  'tx_id': 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd',
  'sent_at': '2026-10-20T09:40:00Z',
  'created_at': '2026-10-20T09:15:01.88Z',
  'updated_at': '2026-10-20T09:40:00Z',
};

/// A schedule as its webhooks carry it: a summary, without its payments.
const schedule = {
  'id': 'sch_1',
  'livemode': false,
  'name': 'Monthly payroll',
  'status': 'active',
  'cadence': 'monthly',
  'weekday': 0,
  'day': -1,
  'at': '09:00',
  'timezone': 'Africa/Harare',
  'fee_paid_by': 'merchant',
  'auto_submit': true,
  'remind_days': 3,
  'totals': [
    {'asset': 'USDT_TRC20', 'ticker': 'USDT', 'items': 12, 'amount': '18000'}
  ],
  'next_run_at': '2026-11-30T07:00:00Z',
  'last_run_at': '2026-10-31T07:00:00Z',
  'last_batch_id': 'b_oct',
  'last_error': '',
  'runs': 4,
};

/// A client whose requests go to [requests] and are answered with [status]
/// and [reply] (by default: a created payment's body echoed back as the
/// payment), without any network.
Payitgo fakeGateway(List<http.Request> requests, int status,
        [Object? reply, String? webhookUrl]) =>
    Payitgo(key,
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
          'b8e1f80bd70ae0784c7855a4');
    });
    test('rejects a changed body, the wrong secret, a missing header', () {
      expect(
          () => Webhook.constructEvent(
              body.replaceFirst('"10"', '"1000"'), header, secret,
              tolerance: Duration.zero),
          throwsA(isA<SignatureVerificationException>()));
      expect(
          () => Webhook.constructEvent(body, header, otherSecret,
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
          'b8e1f80bd70ae0784c7855a4');
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
      expect(requests.single.headers['Authorization'], 'Bearer $key');
      expect(requests.single.body, isEmpty);
      expect(w.url, 'https://shop.example/payitgo/ipn');
      expect(w.secret, 'ab' * 32);
      expect(w.livemode, isFalse);
      expect(w.updatedAt, DateTime.utc(2026, 10, 10, 9, 5));
    });

    for (final live in [true, false]) {
      test('isLive asks payitgo once (${live ? 'a live' : 'a test'} key)',
          () async {
        final payitgo = fakeGateway(requests, 200, {
          'webhook': {...webhook, 'livemode': live}
        });
        expect(await payitgo.isLive(), live);
        expect(await payitgo.isLive(), live);
        // Asked once, with the key; the second call does not ask again.
        expect(requests.single.method, 'GET');
        expect(requests.single.url.toString(), 'https://gateway.test/v1/webhook');
        expect(requests.single.headers['Authorization'], 'Bearer $key');
      });
    }

    test('isLive: a key payitgo refuses throws, and is asked again', () async {
      var status = 401;
      final payitgo = Payitgo(key,
          baseUrl: 'https://gateway.test',
          maxRetries: 0, httpClient: MockClient((req) async {
        requests.add(req);
        return http.Response(
            jsonEncode(status == 200
                ? {'webhook': webhook}
                : {'error': 'invalid API key'}),
            status,
            headers: {'content-type': 'application/json'});
      }));
      await expectLater(
          payitgo.isLive(),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.message, 'message', 'invalid API key')));
      status = 200;
      expect(await payitgo.isLive(), isFalse);
      expect(requests, hasLength(2));
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
      expect(w.secret, 'ab' * 32);
    });

    test('test queues a ping', () async {
      final payitgo = fakeGateway(requests, 202, {'delivery': delivery});
      final d = await payitgo.webhooks.test();
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/v1/webhook/test');
      expect(requests.single.headers['Authorization'], 'Bearer $key');
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
      expect(requests.single.headers['Authorization'], 'Bearer $key');
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
      const message = 'the coin for this payment can no longer be changed';
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
      expect(requests.single.headers['Authorization'], 'Bearer $key');
      expect(requests.single.headers['Content-Type'],
          startsWith('application/json'));
      expect(jsonDecode(requests.single.body), {'outcome': 'confirmed'});
      expect(p.raw, simulated);
      expect((p.simulation!.outcome, p.simulation!.state),
          ('confirmed', 'running'));
      expect(p.deposits.single.simulated, isTrue);
      expect(p.deposits.single.txId, hasLength(64));
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

  group('payments.create with a price in another currency', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('sends the price, its amount as a string, and reads it back',
        () async {
      final payitgo = fakeGateway(requests, 201, priced);
      final p = await payitgo.payments
          .create(orderId: 'ORD-10', priceAmount: 45.5, priceCurrency: 'eur');
      expect(jsonDecode(requests.single.body), {
        'order_id': 'ORD-10',
        'price_amount': '45.5',
        'price_currency': 'eur'
      });
      expect(p.raw, priced);
      expect((p.priceAmount, p.priceCurrency, p.priceRate, p.usdAmount),
          ('45.5', 'EUR', '1.082', '49.23'));
    });

    test('a payment priced in dollars has none of the price fields', () {
      final p = Payment(chosen);
      expect(
          [p.priceAmount, p.priceCurrency, p.priceRate], everyElement(isNull));
    });

    test('no exchange rate for the currency is a 503', () async {
      const message =
          'exchange rate unavailable for price_currency: try again shortly';
      final payitgo = fakeGateway(requests, 503, {'error': message});
      await expectLater(
          payitgo.payments.create(
              orderId: 'ORD-10', priceAmount: '45.50', priceCurrency: 'EUR'),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 503)
              .having((e) => e.message, 'message', message)));
      expect(jsonDecode(requests.single.body)['price_amount'], '45.50');
    });
  });

  group('client webhooks.constructEvent', () {
    test('uses the client\'s webhookSecret', () {
      final payitgo =
          Payitgo(key, baseUrl: 'http://x', webhookSecret: secret);
      expect(
          payitgo.webhooks
              .constructEvent(body, header, tolerance: Duration.zero)
              .id,
          'b8e1f80bd70ae0784c7855a4');
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(payitgo.webhooks.constructEvent(body, sign(secret, now, body)).id,
          'b8e1f80bd70ae0784c7855a4');
    });
    test('an explicit secret wins', () {
      final payitgo =
          Payitgo(key, baseUrl: 'http://x', webhookSecret: otherSecret);
      expect(
          () => payitgo.webhooks
              .constructEvent(body, header, tolerance: Duration.zero),
          throwsA(isA<SignatureVerificationException>()));
      expect(
          payitgo.webhooks
              .constructEvent(body, header,
                  secret: secret, tolerance: Duration.zero)
              .id,
          'b8e1f80bd70ae0784c7855a4');
    });
    test('throws without any secret', () {
      final payitgo = Payitgo(key, baseUrl: 'http://x');
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

  group('payouts (requests)', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    for (final status in [201, 200]) {
      test(
          'request posts the request and returns the item '
          '(${status == 201 ? 'new' : 'its reference already used'})',
          () async {
        final payitgo = fakeGateway(requests, status, {'item': payoutItem});
        final it = await payitgo.payouts.request(
            reference: 'wd-1001',
            asset: 'USDT_TRC20',
            address: 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
            amount: 120,
            name: 'Ana Silva',
            email: 'ana@example.com');
        expect(requests.single.method, 'POST');
        expect(requests.single.url.toString(), 'https://gateway.test/v1/payouts');
        expect(requests.single.headers['Authorization'], 'Bearer $key');
        expect(requests.single.headers['Content-Type'],
            startsWith('application/json'));
        expect(jsonDecode(requests.single.body), {
          'asset': 'USDT_TRC20',
          'address': 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
          'amount': '120',
          'reference': 'wd-1001',
          'name': 'Ana Silva',
          'email': 'ana@example.com',
        });
        expect(it.raw, payoutItem);
        expect((it.id, it.batchId, it.reference, it.row),
            ('8b2d4f6a1c3e5a7b9d0f2c4e', '6a1f3c8e2d9b4a7051c3e8f2', 'wd-1001', 1));
        expect((it.recipient.name, it.recipient.email, it.recipient.note),
            ('Ana Silva', 'ana@example.com', null));
        expect((it.asset, it.ticker, it.chain), ('USDT_TRC20', 'USDT', 'tron'));
        expect((it.amount, it.sendAmount), ('120', '120'));
        expect((it.fee, it.debit, it.usdRate, it.amountUsd),
            ('6.348213', '126.348213', '1', '120'));
        expect(it.status, 'sent');
        expect(it.errors, isEmpty);
        expect(it.warnings.single.code, 'new_recipient');
        expect(it.warnings.single.hint, isNull);
        expect(it.txId, hasLength(64));
        expect(it.sentAt, DateTime.utc(2026, 10, 20, 9, 31, 12, 600));
        expect([it.feeCredit, it.coolingUntil, it.explorerUrl, it.tag],
            everyElement(isNull));
      });
    }

    test('an invalid request is kept, and says why', () async {
      final payitgo = fakeGateway(requests, 201, {'item': invalidItem});
      final it = await payitgo.payouts.request(
          reference: 'wd-1002',
          asset: 'USDT_BEP20',
          address: 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7',
          amount: '75.50',
          tag: 7,
          note: 'withdrawal');
      expect(jsonDecode(requests.single.body), {
        'asset': 'USDT_BEP20',
        'address': 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7',
        'amount': '75.50',
        'reference': 'wd-1002',
        'tag': 7,
        'note': 'withdrawal',
      });
      expect(it.status, 'invalid');
      final e = it.errors.single;
      expect((e.code, e.field, e.message, e.hint), (
        'wrong_network',
        'address',
        'this address is for Tron, not BNB Smart Chain',
        'pay it in a coin of that network, or check the address'
      ));
      expect(it.warnings, isEmpty);
      expect(it.ticker, isNull);
      expect(it.recipient.name, isNull);
    });

    test('retrieve escapes the id; retrieveByReference queries it', () async {
      final payitgo = fakeGateway(requests, 200, {'item': payoutItem});
      final a = await payitgo.payouts.retrieve('8b2d/4f6a');
      final b = await payitgo.payouts.retrieveByReference('wd 1001&x');
      expect(requests.map((r) => r.method), ['GET', 'GET']);
      expect(requests[0].url.toString(),
          'https://gateway.test/v1/payouts/8b2d%2F4f6a');
      expect(requests[1].url.toString(),
          'https://gateway.test/v1/payouts?reference=wd+1001%26x');
      expect(requests[1].url.queryParameters, {'reference': 'wd 1001&x'});
      expect(requests.every((r) => r.body.isEmpty), isTrue);
      expect([a.id, b.id], everyElement('8b2d4f6a1c3e5a7b9d0f2c4e'));
      // Without a reference the same path lists payments: refused here.
      expect(
          () => payitgo.payouts.retrieveByReference(''),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, 'message', 'payitgo: reference is required')));
      expect(requests, hasLength(2));
    });

    test('inbox sends its filters and returns the whole open list', () async {
      final payitgo = fakeGateway(requests, 200, {
        'inbox': openList,
        'coverage': [
          {
            'asset': 'USDT_TRC20',
            'ticker': 'USDT',
            'network': 'Tron (TRC-20)',
            'needed': '126.348213',
            'spendable': '100',
            'top_up': '26.348213',
            'address': 'TMkq7dZ3vN8xR2pB6cH9sJ4fL1wY5tGaQe',
          }
        ],
        'items': [invalidItem],
        'total': 1,
        'limit': 10,
        'offset': 20,
      });
      final view = await payitgo.payouts
          .inbox(status: 'invalid,ready', limit: 10, offset: 20);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/v1/payouts/inbox');
      expect(requests.single.url.queryParameters,
          {'status': 'invalid,ready', 'limit': '10', 'offset': '20'});
      expect((view.inbox.id, view.inbox.inbox, view.inbox.open),
          ('inbox_1', true, true));
      expect(view.inbox.totals.single.debit, '126.348213');
      expect(view.inbox.counts.invalid, 1);
      final c = view.coverage.single;
      expect((c.asset, c.ticker, c.network), ('USDT_TRC20', 'USDT', 'Tron (TRC-20)'));
      expect((c.needed, c.spendable, c.topUp, c.address),
          ('126.348213', '100', '26.348213', 'TMkq7dZ3vN8xR2pB6cH9sJ4fL1wY5tGaQe'));
      expect(view.items.single.status, 'invalid');
      expect((view.total, view.limit, view.offset), (1, 10, 20));

      await payitgo.payouts.inbox();
      expect(requests[1].url.toString(), 'https://gateway.test/v1/payouts/inbox');
    });

    test('send: every valid request, or those of ids', () async {
      final payitgo = fakeGateway(requests, 200, {'batch': payoutBatch});
      final all = await payitgo.payouts.send();
      expect(requests[0].method, 'POST');
      expect(requests[0].url.toString(), 'https://gateway.test/v1/payouts/send');
      expect(requests[0].body, isEmpty);
      expect(requests[0].headers.containsKey('Content-Type'), isFalse);
      expect(all.id, '6a1f3c8e2d9b4a7051c3e8f2');
      await payitgo.payouts.send(ids: ['it_1', 'it_2']);
      expect(jsonDecode(requests[1].body), {
        'ids': ['it_1', 'it_2']
      });
    });

    test('send with empty ids throws, and sends nothing', () async {
      final payitgo = fakeGateway(requests, 200, {'batch': payoutBatch});
      expect(() => payitgo.payouts.send(ids: []), throwsArgumentError);
      expect(requests, isEmpty);
    });

    test('cancel sends DELETE and returns the request, removed', () async {
      final payitgo = fakeGateway(requests, 200, {'item': removedItem});
      final it = await payitgo.payouts.cancel('5c7e9a1b3d5f7a9c1e3b5d7f');
      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payouts/5c7e9a1b3d5f7a9c1e3b5d7f');
      expect(requests.single.body, isEmpty);
      expect((it.status, it.cancelReason), ('canceled', 'removed'));
    });

    test('a removed request says why, by whom and when; it has no batch', () {
      final it = PayoutItem(removedItem);
      expect(it.batchId, isNull);
      expect((it.reference, it.releasedReference), (null, 'wd-88231'));
      expect((it.status, it.cancelReason, it.cancelNote, it.canceledBy),
          ('canceled', 'removed', null, 'usr_7'));
      expect(it.canceledAt, DateTime.utc(2026, 10, 20, 14, 2, 44, 312));
      expect(it.members, {'usr_7': 'finance@example.com'});
      expect(it.webhookUrl, 'https://shop.example/payouts/ipn');

      final rejected = PayoutItem({
        ...payoutItem,
        'status': 'canceled',
        'cancel_reason': 'rejected',
        'cancel_note': 'paid by bank transfer instead',
        'canceled_by': 'system',
      });
      expect(rejected.batchId, '6a1f3c8e2d9b4a7051c3e8f2');
      expect((rejected.cancelReason, rejected.cancelNote, rejected.canceledBy),
          ('rejected', 'paid by bank transfer instead', 'system'));
      expect(rejected.members, isEmpty);

      final sent = PayoutItem(payoutItem);
      expect([sent.cancelReason, sent.cancelNote, sent.canceledBy],
          everyElement(isNull));
      expect([sent.canceledAt, sent.webhookUrl], everyElement(isNull));
      expect(sent.members, isEmpty);
    });

    test('request and batch items send webhook_url', () async {
      final payitgo = fakeGateway(requests, 201, {'item': removedItem});
      await payitgo.payouts.request(
          reference: 'wd-88231',
          asset: 'USDT_TRC20',
          address: 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
          amount: '40',
          webhookUrl: 'https://shop.example/payouts/ipn');
      expect(jsonDecode(requests.single.body), {
        'asset': 'USDT_TRC20',
        'address': 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
        'amount': '40',
        'reference': 'wd-88231',
        'webhook_url': 'https://shop.example/payouts/ipn',
      });
      expect(
          const PayoutItemInput(
                  asset: 'TRX',
                  address: 'T1',
                  amount: 5,
                  webhookUrl: 'https://shop.example/a')
              .toJson(),
          {
            'asset': 'TRX',
            'address': 'T1',
            'amount': '5',
            'webhook_url': 'https://shop.example/a'
          });
    });

    test('remove posts the ids and returns a result per id', () async {
      const sent =
          'not in your list of payout requests (sent already): cancel it with DELETE /v1/payouts/7b1d3f5a9c2e4b6d8f0a1c3e';
      final payitgo = fakeGateway(requests, 200, {
        'results': [
          {'id': '5c7e9a1b3d5f7a9c1e3b5d7f', 'item': removedItem},
          {
            'id': '7b1d3f5a9c2e4b6d8f0a1c3e',
            'error': {'status': 409, 'message': sent}
          },
          {
            'id': 'nope',
            'error': {'status': 404, 'message': 'not found'}
          },
        ]
      });
      final results = await payitgo.payouts.remove(
          ['5c7e9a1b3d5f7a9c1e3b5d7f', '7b1d3f5a9c2e4b6d8f0a1c3e', 'nope']);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payouts/remove');
      expect(requests.single.headers['Content-Type'],
          startsWith('application/json'));
      expect(jsonDecode(requests.single.body), {
        'ids': ['5c7e9a1b3d5f7a9c1e3b5d7f', '7b1d3f5a9c2e4b6d8f0a1c3e', 'nope']
      });
      expect(results.map((r) => r.id),
          ['5c7e9a1b3d5f7a9c1e3b5d7f', '7b1d3f5a9c2e4b6d8f0a1c3e', 'nope']);
      final removed = results[0];
      expect(removed.error, isNull);
      expect((removed.item!.status, removed.item!.cancelReason),
          ('canceled', 'removed'));
      expect(removed.item!.batchId, isNull);
      expect(removed.item!.releasedReference, 'wd-88231');
      expect(results[1].item, isNull);
      expect((results[1].error!.status, results[1].error!.message), (409, sent));
      expect((results[2].error!.status, results[2].error!.message),
          (404, 'not found'));
    });

    test('remove with empty ids throws, and sends nothing', () async {
      final payitgo = fakeGateway(requests, 200, {'results': []});
      expect(
          () => payitgo.payouts.remove([]),
          throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
              'payitgo: ids is empty: remove needs at least one payout request id')));
      expect(requests, isEmpty);
    });

    test('list sends only the filters given and returns a page', () async {
      final payitgo = fakeGateway(requests, 200, {
        'items': [payoutItem, removedItem],
        'has_more': true,
        'next_cursor': 'MjAyNi0xMC0yMFQxNDozMToxMi42WnwyYzVl',
      });
      final page = await payitgo.payouts.list(
          status: ['sent', 'failed', 'canceled'],
          updatedSince: DateTime.utc(2026, 10, 20, 9).toLocal(),
          cursor: 'MjAyNi0xMC0yMFQwOTowMDowMFp8YQ',
          limit: 100);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/v1/payouts');
      expect(requests.single.url.queryParameters, {
        'status': 'sent,failed,canceled',
        'updated_since': '2026-10-20T09:00:00.000Z',
        'cursor': 'MjAyNi0xMC0yMFQwOTowMDowMFp8YQ',
        'limit': '100',
      });
      expect(requests.single.body, isEmpty);
      expect(page.items.map((i) => i.id),
          ['8b2d4f6a1c3e5a7b9d0f2c4e', '5c7e9a1b3d5f7a9c1e3b5d7f']);
      expect(page.items.last.batchId, isNull);
      expect((page.hasMore, page.nextCursor),
          (true, 'MjAyNi0xMC0yMFQxNDozMToxMi42WnwyYzVl'));

      await payitgo.payouts.list(status: [], cursor: '');
      expect(requests[1].url.toString(), 'https://gateway.test/v1/payouts');
    });

    test('list: an empty page has no next_cursor', () async {
      final payitgo =
          fakeGateway(requests, 200, {'items': [], 'has_more': false});
      final page = await payitgo.payouts.list(limit: 50);
      expect(requests.single.url.query, 'limit=50');
      expect(page.items, isEmpty);
      expect((page.hasMore, page.nextCursor), (false, null));
    });

    test('quote posts the items and returns the quote and its items',
        () async {
      final quoted = {
        'livemode': false,
        'row': 1,
        'recipient': {},
        'asset': 'USDT_BEP20',
        'chain': 'bsc',
        'address': '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
        'amount': '120',
        'send_amount': '119.38816579',
        'fee': '0.61183421',
        'debit': '120',
        'usd_rate': '1',
        'amount_usd': '120',
        'status': 'ready',
        'errors': [],
        'warnings': [],
      };
      final payitgo = fakeGateway(requests, 200, {
        'quote': {
          'livemode': false,
          'fee_paid_by': 'recipient',
          'totals': [
            {...usdtTotal, 'asset': 'USDT_BEP20', 'chain': 'bsc'}
          ],
          'total_usd': '120',
          'counts': {...counts, 'total': 1, 'invalid': 0},
        },
        'items': [quoted],
      });
      final res = await payitgo.payouts.quote(feePaidBy: 'recipient', items: [
        const PayoutItemInput(
            asset: 'USDT_BEP20',
            address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
            amount: '120'),
      ]);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payout-quotes');
      expect(jsonDecode(requests.single.body), {
        'fee_paid_by': 'recipient',
        'items': [
          {
            'asset': 'USDT_BEP20',
            'address': '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
            'amount': '120'
          }
        ]
      });
      expect((res.quote.livemode, res.quote.feePaidBy, res.quote.totalUsd),
          (false, 'recipient', '120'));
      expect(res.quote.totals.single.asset, 'USDT_BEP20');
      expect((res.quote.counts.total, res.quote.counts.ready), (1, 1));
      final it = res.items.single;
      expect((it.sendAmount, it.fee, it.status),
          ('119.38816579', '0.61183421', 'ready'));
      // Nothing is kept: no id, batch or times.
      expect([it.id, it.merchantId, it.batchId, it.createdAt, it.updatedAt],
          everyElement(isNull));
    });

    test('a key without payouts is a 403', () async {
      const message =
          'this api key cannot make payouts: turn payouts on for it in the dashboard';
      final payitgo = fakeGateway(requests, 403, {'error': message});
      await expectLater(
          payitgo.payouts.request(
              reference: 'wd-1', asset: 'TRX', address: 'T1', amount: 10),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 403)
              .having((e) => e.message, 'message', message)));
    });
  });

  group('payoutBatches', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    for (final status in [201, 200]) {
      test(
          'create posts the batch and returns it '
          '(${status == 201 ? 'new' : 'its reference already used'})',
          () async {
        final payitgo = fakeGateway(requests, status, {'batch': payoutBatch});
        final b = await payitgo.payoutBatches.create(
          reference: 'payroll-2026-10',
          name: 'October payroll',
          feePaidBy: 'merchant',
          webhookUrl: 'https://shop.example/payouts/ipn',
          items: [
            const PayoutItemInput(
                reference: 'payroll-2026-10-ana',
                asset: 'USDT_TRC20',
                address: 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
                amount: '120',
                name: 'Ana Silva',
                email: 'ana@example.com',
                note: 'October salary'),
            const PayoutItemInput(
                asset: 'BNB',
                address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
                amount: 0.25),
          ],
        );
        expect(requests.single.method, 'POST');
        expect(requests.single.url.toString(),
            'https://gateway.test/v1/payout-batches');
        expect(jsonDecode(requests.single.body), {
          'reference': 'payroll-2026-10',
          'name': 'October payroll',
          'fee_paid_by': 'merchant',
          'webhook_url': 'https://shop.example/payouts/ipn',
          'items': [
            {
              'asset': 'USDT_TRC20',
              'address': 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
              'amount': '120',
              'reference': 'payroll-2026-10-ana',
              'name': 'Ana Silva',
              'email': 'ana@example.com',
              'note': 'October salary'
            },
            {
              'asset': 'BNB',
              'address': '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
              'amount': '0.25'
            }
          ]
        });
        expect(b.raw, payoutBatch);
        expect((b.id, b.reference, b.name, b.source),
            ('6a1f3c8e2d9b4a7051c3e8f2', 'payroll-2026-10', 'October payroll', 'api'));
        expect((b.inbox, b.open, b.byApiKey, b.createdBy),
            (false, false, true, 'key_1'));
        expect((b.feePaidBy, b.status, b.totalUsd),
            ('merchant', 'awaiting_funds', '126.35'));
        final w = b.waiting!;
        expect((w.reason, w.since), ('funds', DateTime.utc(2026, 10, 20, 9, 16, 40, 120)));
        expect(w.note, startsWith('top up the payout wallet'));
        final s = w.shortfall.single;
        expect((s.asset, s.network, s.amount, s.address), (
          'USDT_TRC20',
          'Tron (TRC-20)',
          '126.348213',
          'TMkq7dZ3vN8xR2pB6cH9sJ4fL1wY5tGaQe'
        ));
        final t = b.totals.single;
        expect((t.asset, t.ticker, t.chain, t.network, t.items),
            ('USDT_TRC20', 'USDT', 'tron', 'Tron (TRC-20)', 1));
        expect((t.amount, t.sendAmount, t.fee), ('120', '120', '6.348213'));
        expect((t.debit, t.debitUsd, t.savedUsd), ('126.348213', '126.35', '0'));
        expect((b.counts.total, b.counts.invalid, b.counts.ready, b.counts.sent),
            (2, 1, 1, 0));
        expect(b.quoteExpiresAt, DateTime.utc(2026, 10, 20, 10, 15, 2, 410));
        expect(b.approvalsNeeded, 0);
        expect(b.approvals, isEmpty);
        expect((b.submittedBy, b.submittedAt),
            ('key_1', DateTime.utc(2026, 10, 20, 9, 16, 40, 90)));
        expect([b.rejection, b.webhookUrl, b.fundedAt, b.completedAt],
            everyElement(isNull));
        expect([b.canceledBy, b.canceledAt], everyElement(isNull));
      });
    }

    test('list sends its filters', () async {
      final payitgo = fakeGateway(requests, 200, {
        'batches': [payoutBatch],
        'total': 1,
        'limit': 10,
        'offset': 0
      });
      final page = await payitgo.payoutBatches
          .list(status: 'awaiting_funds', limit: 10, offset: 0);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payout-batches?status=awaiting_funds&limit=10&offset=0');
      expect(page.batches.single.id, '6a1f3c8e2d9b4a7051c3e8f2');
      expect((page.total, page.limit, page.offset), (1, 10, 0));
      await payitgo.payoutBatches.list();
      expect(requests[1].url.toString(), 'https://gateway.test/v1/payout-batches');
    });

    test('retrieve and items escape the id; items sends its filters',
        () async {
      final payitgo = fakeGateway(requests, 200, {
        'batch': payoutBatch,
        'items': [payoutItem, invalidItem],
        'total': 2,
        'limit': 50,
        'offset': 0,
      });
      final b = await payitgo.payoutBatches.retrieve('b/1');
      final page = await payitgo.payoutBatches
          .items('b/1', status: 'sent,failed', limit: 50, offset: 0);
      expect(requests.map((r) => r.method), ['GET', 'GET']);
      expect(requests[0].url.toString(),
          'https://gateway.test/v1/payout-batches/b%2F1');
      expect(requests[1].url.path, '/v1/payout-batches/b%2F1/items');
      expect(requests[1].url.queryParameters,
          {'status': 'sent,failed', 'limit': '50', 'offset': '0'});
      expect(b.status, 'awaiting_funds');
      expect(page.items.map((i) => i.status), ['sent', 'invalid']);
      expect((page.total, page.limit, page.offset), (2, 50, 0));
      await payitgo.payoutBatches.items('b1');
      expect(requests[2].url.toString(),
          'https://gateway.test/v1/payout-batches/b1/items');
    });

    test('addItems posts the items', () async {
      final payitgo = fakeGateway(requests, 200, {'batch': payoutBatch});
      final b = await payitgo.payoutBatches.addItems('b1', [
        const PayoutItemInput(asset: 'TRX', address: 'TJ9', amount: 50),
      ]);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payout-batches/b1/items');
      expect(jsonDecode(requests.single.body), {
        'items': [
          {'asset': 'TRX', 'address': 'TJ9', 'amount': '50'}
        ]
      });
      expect(b.id, '6a1f3c8e2d9b4a7051c3e8f2');
    });

    test('quote, submit and cancel post to the batch without a body',
        () async {
      final payitgo = fakeGateway(requests, 200, {
        'batch': {
          ...payoutBatch,
          'status': 'rejected',
          'approvals_needed': 1,
          'approvals': [
            {'user_id': 'usr_1', 'at': '2026-10-20T09:20:00Z'}
          ],
          'rejection': {
            'by': 'usr_2',
            'at': '2026-10-20T09:21:00Z',
            'reason': 'wrong month'
          },
        }
      });
      final q = await payitgo.payoutBatches.quote('b1');
      await payitgo.payoutBatches.submit('b1');
      await payitgo.payoutBatches.cancel('b1');
      expect(requests.map((r) => r.method), ['POST', 'POST', 'POST']);
      expect(requests.map((r) => r.url.path), [
        '/v1/payout-batches/b1/quote',
        '/v1/payout-batches/b1/submit',
        '/v1/payout-batches/b1/cancel'
      ]);
      expect(requests.every((r) => r.body.isEmpty), isTrue);
      expect(q.approvals.single.userId, 'usr_1');
      expect(q.approvals.single.at, DateTime.utc(2026, 10, 20, 9, 20));
      expect((q.rejection!.by, q.rejection!.reason), ('usr_2', 'wrong month'));
      expect(q.rejection!.at, DateTime.utc(2026, 10, 20, 9, 21));
    });

    test('prices that expired are a 409', () async {
      const message = 'its prices expired: get a new quote first';
      final payitgo = fakeGateway(requests, 409, {'error': message});
      await expectLater(
          payitgo.payoutBatches.submit('b1'),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.message, 'message', message)));
    });
  });

  group('payoutWallets', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('list returns every wallet', () async {
      final payitgo = fakeGateway(requests, 200, {'wallets': payoutWallets});
      final wallets = await payitgo.payoutWallets.list();
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(),
          'https://gateway.test/v1/payout-wallets');
      expect(wallets.map((w) => w.chain), ['tron', 'bsc']);
      final tron = wallets.first;
      expect((tron.network, tron.address, tron.livemode, tron.explorerUrl),
          ('Tron', 'TMkq7dZ3vN8xR2pB6cH9sJ4fL1wY5tGaQe', false, null));
      final a = tron.assets.single;
      expect((a.asset, a.ticker, a.iconUrl),
          ('USDT_TRC20', 'USDT', 'https://api.payitgo.co/coins/USDT_TRC20.svg'));
      expect((a.balance, a.reserved, a.spendable, a.needed),
          ('1000', '126.348213', '873.651787', '0'));
      expect(tron.error, isNull);
      expect(wallets.last.assets, isEmpty);
      expect(wallets.last.error, startsWith('balances unavailable'));
    });

    test('simulateTopUp posts the amount as a string', () async {
      final payitgo = fakeGateway(requests, 200, {'wallets': payoutWallets});
      final wallets = await payitgo.payoutWallets.simulateTopUp('USDT_TRC20', 1000);
      await payitgo.payoutWallets.simulateTopUp('USDT/BEP20', '250.5');
      expect(requests.map((r) => r.method), ['POST', 'POST']);
      expect(requests[0].url.toString(),
          'https://gateway.test/v1/payout-wallets/USDT_TRC20/simulate-top-up');
      expect(requests[1].url.toString(),
          'https://gateway.test/v1/payout-wallets/USDT%2FBEP20/simulate-top-up');
      expect(jsonDecode(requests[0].body), {'amount': '1000'});
      expect(jsonDecode(requests[1].body), {'amount': '250.5'});
      expect(wallets.first.assets.single.balance, '1000');
    });

    test('a live key is a 400', () async {
      const message = 'only a test wallet is topped up on paper: use a test key';
      final payitgo = fakeGateway(requests, 400, {'error': message});
      await expectLater(
          payitgo.payoutWallets.simulateTopUp('TRX', '10'),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message', message)));
    });
  });

  group('payout webhooks', () {
    test('events lists every event, in the gateway\'s order', () {
      expect(Webhooks.events, [
        'payment.partially_paid',
        'payment.detecting',
        'payment.confirmed',
        'payment.underpaid',
        'payment.expired',
        'payment.failed',
        'payment.wrong_asset',
        'payment.late_deposit',
        'payout.approved',
        'payout.rejected',
        'payout.sent',
        'settlement.completed',
        'settlement.failed',
        'payout_batch.quoted',
        'payout_batch.pending_approval',
        'payout_batch.approved',
        'payout_batch.rejected',
        'payout_batch.awaiting_funds',
        'payout_batch.processing',
        'payout_batch.completed',
        'payout_batch.canceled',
        'payout_item.processing',
        'payout_item.returned',
        'payout_item.sent',
        'payout_item.failed',
        'payout_item.canceled',
        'payout_item.claimed',
        'payout_item.claim_expired',
        'payout_wallet.withdrawn',
        'payout_wallet.withdrawal_failed',
        'payout_schedule.run',
        'payout_schedule.funding_needed',
        'ping',
      ]);
    });

    test('an event\'s data wraps into the payout models', () {
      final payitgo = Payitgo(key, baseUrl: 'http://x', webhookSecret: secret);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      WebhookEvent verify(String type, Object data) {
        final body = jsonEncode({
          'id': 'evt_$type',
          'type': type,
          'livemode': false,
          'created_at': '2026-10-20T09:31:13Z',
          'data': data,
        });
        return payitgo.webhooks.constructEvent(body, sign(secret, now, body));
      }

      final batch = PayoutBatch(verify('payout_batch.completed', {
        ...payoutBatch,
        'status': 'completed',
        'waiting': null,
        'completed_at': '2026-10-20T09:40:00Z',
      }).data);
      expect(batch.status, 'completed');
      expect(batch.waiting, isNull);
      expect(batch.completedAt, DateTime.utc(2026, 10, 20, 9, 40));

      final item = PayoutItem(verify('payout_item.sent', payoutItem).data);
      expect((item.reference, item.txId), ('wd-1001', payoutItem['tx_id']));

      final w = PayoutWithdrawal(verify('payout_wallet.withdrawn', {
        'id': '1d3f5a7c9e2b4d6f8a0c2e4b',
        'merchant_id': 'mch_1',
        'livemode': false,
        'asset': 'USDT_TRC20',
        'chain': 'tron',
        'amount': '373.651787',
        'fee': '12.01',
        'send_amount': '361.641787',
        'address_id': '3e7a1c9f5b2d4e8a6c0f2b1d',
        'address': 'TWd4Kp9mR2xH7sN3vB6cJ8fL5qY1tZgEaU',
        'status': 'sent',
        'tx_id': 'ab' * 32,
        'requested_by': 'usr_1',
        'created_at': '2026-10-20T11:02:15.33Z',
        'updated_at': '2026-10-20T11:03:00Z',
        'sent_at': '2026-10-20T11:03:00Z',
      }).data);
      expect((w.id, w.asset, w.chain, w.status),
          ('1d3f5a7c9e2b4d6f8a0c2e4b', 'USDT_TRC20', 'tron', 'sent'));
      expect((w.amount, w.fee, w.sendAmount), ('373.651787', '12.01', '361.641787'));
      expect((w.addressId, w.address, w.tag),
          ('3e7a1c9f5b2d4e8a6c0f2b1d', 'TWd4Kp9mR2xH7sN3vB6cJ8fL5qY1tZgEaU', null));
      expect((w.txId, w.explorerUrl, w.requestedBy), ('ab' * 32, null, 'usr_1'));
      expect(w.createdAt, DateTime.utc(2026, 10, 20, 11, 2, 15, 330));
      expect(w.sentAt, DateTime.utc(2026, 10, 20, 11, 3));
      expect(w.failReason, isNull);

      final failed = PayoutWithdrawal(verify('payout_wallet.withdrawal_failed', {
        ...w.raw,
        'status': 'failed',
        'tx_id': null,
        'sent_at': null,
        'fail_reason': 'the network refused the transfer',
      }).data);
      expect((failed.status, failed.failReason),
          ('failed', 'the network refused the transfer'));
      expect([failed.txId, failed.sentAt], everyElement(isNull));

      // A request leaves the list for a batch of its own, and comes back.
      final processing = PayoutItem(verify('payout_item.processing', {
        ...invalidItem,
        'status': 'ready',
        'errors': [],
        'batch_id': '6a1f3c8e2d9b4a7051c3e8f2',
      }).data);
      expect((processing.status, processing.batchId),
          ('ready', '6a1f3c8e2d9b4a7051c3e8f2'));
      final returned =
          PayoutItem(verify('payout_item.returned', invalidItem).data);
      expect((returned.status, returned.batchId), ('invalid', 'inbox_1'));
      expect(returned.errors.single.code, 'wrong_network');
    });
  });

  group('events.list', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('sends only the filters given and returns the events', () async {
      final payitgo = fakeGateway(requests, 200, {
        'events': [
          {
            'id': '9b1e3c5a7d2f4b6e8a0c1d3f',
            'type': 'payout_item.canceled',
            'livemode': false,
            'created_at': '2026-10-20T15:02:44.312Z',
            'data': removedItem,
          },
          {
            'id': 'a0c2e4b6d8f1a3c5e7b9d1f3',
            'type': 'payment.confirmed',
            'livemode': false,
            'created_at': '2026-10-20T15:03:00Z',
            'data': chosen,
          },
        ],
        'has_more': true,
      });
      final page = await payitgo.events.list(
          types: ['payout_item.*', 'payment.confirmed'],
          after: '4f1c2a9e7b3d5f80a2c4e6b8',
          createdAfter: DateTime.utc(2026, 10, 20, 9, 30, 5),
          limit: 200);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/v1/events');
      expect(requests.single.url.queryParameters, {
        'type': 'payout_item.*,payment.confirmed',
        'after': '4f1c2a9e7b3d5f80a2c4e6b8',
        'created_after': '2026-10-20T09:30:05.000Z',
        'limit': '200',
      });
      expect(requests.single.headers['Authorization'], 'Bearer $key');
      expect(requests.single.body, isEmpty);
      expect(page.hasMore, isTrue);
      final e = page.events.first;
      expect((e.id, e.type, e.livemode),
          ('9b1e3c5a7d2f4b6e8a0c1d3f', 'payout_item.canceled', false));
      expect(e.createdAt, DateTime.utc(2026, 10, 20, 15, 2, 44, 312));
      final it = PayoutItem(e.data);
      expect((it.cancelReason, it.releasedReference), ('removed', 'wd-88231'));
      expect(Payment(page.events.last.data).orderId, 'ORD-7');

      await payitgo.events.list();
      expect(requests[1].url.toString(), 'https://gateway.test/v1/events');
    });

    test('an empty page, and a storefront\'s key refused', () async {
      final empty = await fakeGateway(
          requests, 200, {'events': [], 'has_more': false}).events.list(
          types: ['payout_wallet.withdrawal_failed']);
      expect(requests.single.url.query, 'type=payout_wallet.withdrawal_failed');
      expect(empty.events, isEmpty);
      expect(empty.hasMore, isFalse);

      const message =
          "a storefront's key cannot read the account's events: use an account key";
      await expectLater(
          fakeGateway(requests, 403, {'error': message}).events.list(),
          throwsA(isA<PayitgoException>()
              .having((e) => e.status, 'status', 403)
              .having((e) => e.message, 'message', message)));
    });
  });

  group('claim links and converted payments', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('request makes a claim link: no address, its claim fields sent',
        () async {
      final payitgo = fakeGateway(requests, 201, {'item': claimItem});
      final it = await payitgo.payouts.request(
          reference: 'prize-cup-1',
          asset: 'USDT_TRC20',
          amount: '250',
          name: 'Player One',
          email: 'player@example.com',
          claim: true,
          claimAssets: ['USDT_BEP20', 'BTC']);
      expect(jsonDecode(requests.single.body), {
        'asset': 'USDT_TRC20',
        'amount': '250',
        'reference': 'prize-cup-1',
        'name': 'Player One',
        'email': 'player@example.com',
        'claim': true,
        'claim_assets': ['USDT_BEP20', 'BTC'],
      });
      expect((it.status, it.address), ('claimable', ''));
      final c = it.claim!;
      expect((c.email, c.url),
          ('player@example.com', 'https://pay.example/claim/Zm9vYmFy'));
      expect(c.assets, ['USDT_BEP20', 'BTC']);
      expect(c.expiresAt, DateTime.utc(2026, 11, 19, 9, 20));
      expect((c.emailed, c.extended), (1, 0));
      expect(c.lastEmailAt, DateTime.utc(2026, 10, 20, 9, 20, 1));
      expect([c.claimedAt, c.fundedAsset, c.fundedAmount], everyElement(isNull));
      expect(it.convert, isNull);
    });

    test('a claimed link in another coin says what funded it', () {
      final c = PayoutItem({
        ...claimItem,
        'status': 'queued',
        'address': '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
        'claim': {
          'assets': [],
          'claimed_at': '2026-10-21T10:00:00Z',
          'emailed': 0,
          'extended': 2,
          'funded_asset': 'USDT_BEP20',
          'funded_amount': '250.5',
        },
      }).claim!;
      expect(c.email, isNull);
      expect(c.assets, isEmpty);
      expect(c.claimedAt, DateTime.utc(2026, 10, 21, 10));
      expect((c.extended, c.fundedAsset, c.fundedAmount),
          (2, 'USDT_BEP20', '250.5'));
    });

    test('batch items send claim and claim_assets as given; no address',
        () async {
      final payitgo = fakeGateway(requests, 201, {'batch': payoutBatch});
      await payitgo.payoutBatches.create(items: [
        const PayoutItemInput(
            asset: 'USDT_TRC20',
            amount: '50',
            email: 'winner@example.com',
            claim: true),
        const PayoutItemInput(
            asset: 'USDT_BEP20', amount: 20, claimAssets: ['USDT_TRC20']),
        const PayoutItemInput(
            asset: 'XRP',
            address: 'rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe',
            tag: 1042,
            amount: '30',
            claim: false),
      ]);
      expect(jsonDecode(requests.single.body)['items'], [
        {
          'asset': 'USDT_TRC20',
          'amount': '50',
          'email': 'winner@example.com',
          'claim': true
        },
        {
          'asset': 'USDT_BEP20',
          'amount': '20',
          'claim_assets': ['USDT_TRC20']
        },
        {
          'asset': 'XRP',
          'address': 'rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe',
          'amount': '30',
          'tag': 1042,
          'claim': false
        },
      ]);
    });

    test('create and quote send convert and convert_from', () async {
      final payitgo = fakeGateway(requests, 201, {
        'batch': {
          ...payoutBatch,
          'convert': 'convert',
          'convert_from': 'USDT_TRC20',
          'counts': {...counts, 'claimable': 2, 'expired': 1},
        },
        'quote': {
          'livemode': false,
          'fee_paid_by': 'merchant',
          'totals': [usdtTotal],
          'total_usd': '663.69',
          'counts': counts,
        },
        'items': [convertedItem],
      });
      const btc = PayoutItemInput(
          asset: 'BTC',
          address: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
          amount: '0.01');
      final b = await payitgo.payoutBatches.create(
          reference: 'conv-1',
          convert: 'convert',
          convertFrom: 'USDT_TRC20',
          items: [btc]);
      final q = await payitgo.payouts
          .quote(convert: 'convert', convertFrom: 'USDT_TRC20', items: [btc]);
      for (final r in requests) {
        final sent = jsonDecode(r.body) as Map;
        expect((sent['convert'], sent['convert_from']), ('convert', 'USDT_TRC20'));
      }
      expect(requests.map((r) => r.url.path),
          ['/v1/payout-batches', '/v1/payout-quotes']);
      expect((b.convert, b.convertFrom), ('convert', 'USDT_TRC20'));
      expect((b.counts.claimable, b.counts.expired), (2, 1));
      expect(PayoutBatch(payoutBatch).convert, '');
      expect(PayoutBatch(payoutBatch).convertFrom, isNull);
      expect(PayoutBatch(payoutBatch).counts.claimable, 0);

      final it = q.items.single;
      expect((it.asset, it.amount, it.fee, it.debit),
          ('USDT_TRC20', '650.12', '13.572417', '663.692417'));
      expect(it.address, 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq');
      final c = it.convert!;
      expect((c.to, c.ticker, c.network), ('BTC', 'BTC', 'Bitcoin'));
      expect((c.toAmount, c.estimate, c.amountOut),
          ('0.01', '0.00998', '0.00999'));
      expect(PayoutConversion({'to': 'BTC', 'to_amount': '0.01', 'estimate': '0'}).amountOut,
          isNull);
      expect(it.claim, isNull);
    });

    test('events: claim links and schedules wrap into their models', () {
      expect(
          Webhooks.events,
          containsAll([
            'payout_item.claimed',
            'payout_item.claim_expired',
            'payout_schedule.run',
            'payout_schedule.funding_needed',
          ]));
      final payitgo = Payitgo(key, baseUrl: 'http://x', webhookSecret: secret);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      WebhookEvent verify(String type, Object data) {
        final body = jsonEncode({
          'id': 'evt_$type',
          'type': type,
          'livemode': false,
          'created_at': '2026-10-20T09:31:13Z',
          'data': data,
        });
        return payitgo.webhooks.constructEvent(body, sign(secret, now, body));
      }

      final claimed = PayoutItem(verify('payout_item.claimed', {
        ...claimItem,
        'status': 'queued',
        'claim': {...claimItem['claim'] as Map, 'claimed_at': '2026-10-21T10:00:00Z'},
      }).data);
      expect(claimed.claim!.claimedAt, DateTime.utc(2026, 10, 21, 10));
      final expired = PayoutItem(verify('payout_item.claim_expired',
          {...claimItem, 'status': 'expired'}).data);
      expect(expired.status, 'expired');

      final run = PayoutSchedule(verify('payout_schedule.run', schedule).data);
      expect((run.id, run.name, run.status, run.cadence, run.livemode),
          ('sch_1', 'Monthly payroll', 'active', 'monthly', false));
      expect(run.nextRunAt, DateTime.utc(2026, 11, 30, 7));
      expect(run.lastRunAt, DateTime.utc(2026, 10, 31, 7));
      expect((run.lastBatchId, run.lastError), ('b_oct', ''));
      expect(run.raw.containsKey('items'), isFalse);

      final funding = PayoutScheduleFunding(
          verify('payout_schedule.funding_needed', {
        'schedule': schedule,
        'shortfall': [
          {
            'asset': 'USDT_TRC20',
            'network': 'Tron (TRC-20)',
            'amount': '1500',
            'address': 'TMkq7dZ3vN8xR2pB6cH9sJ4fL1wY5tGaQe',
          }
        ],
      }).data);
      expect(funding.schedule.id, 'sch_1');
      final s = funding.shortfall.single;
      expect((s.asset, s.amount, s.address),
          ('USDT_TRC20', '1500', 'TMkq7dZ3vN8xR2pB6cH9sJ4fL1wY5tGaQe'));
    });
  });

  group('close', () {
    test('leaves an http.Client you passed open', () {
      final client = _Closable();
      final payitgo =
          Payitgo(key, baseUrl: 'http://x', httpClient: client);
      payitgo.checkout.close();
      payitgo.close();
      PayitgoCheckout(baseUrl: 'http://x', httpClient: client).close();
      expect(client.closed, isFalse);
    });

    test('closes the one client the SDK made, which checkout shares', () async {
      final payitgo =
          Payitgo(key, baseUrl: 'http://x', maxRetries: 0);
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
          Payitgo(key, baseUrl: 'http://127.0.0.1:9', maxRetries: 0);
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
    final noKey = throwsA(isA<ArgumentError>().having(
        (e) => e.message, 'message', 'payitgo: the API key is required'));
    expect(() => Payitgo('', baseUrl: 'http://x'), noKey);
    expect(() => Payitgo('  ', baseUrl: 'http://x'), noKey);
    expect(() => Payitgo(key, baseUrl: ''), throwsArgumentError);
    expect(() => PayitgoCheckout(baseUrl: ''), throwsArgumentError);
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
