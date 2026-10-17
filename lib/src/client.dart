import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'webhook.dart';

const _version = '0.4.0';

/// Where the gateway lives when no `baseUrl` is passed.
const _defaultBaseUrl = 'https://api.payitgo.co';

/// How long a closed payment's address is still watched for late deposits.
const _lateWindow = Duration(hours: 24);

/// The API refused the request. [status] is the HTTP status, or 0 for a network error.
class PayitgoException implements Exception {
  PayitgoException(this.message, this.status);

  final String message;
  final int status;

  @override
  String toString() => status == 0
      ? 'PayitgoException: $message'
      : 'PayitgoException($status): $message';
}

/// One transfer to a payment's address.
class Deposit {
  Deposit(this.raw);

  final Map<String, dynamic> raw;

  String get txId => raw['tx_id'] as String;

  /// The asset that arrived: another than the payment's own for a wrong-asset deposit.
  String get token => raw['token'] as String;
  String get chain => raw['chain'] as String;
  String get amount => raw['amount'] as String;
  String get usdValue => raw['usd_value'] as String;

  /// Whether it counts toward the payment.
  bool get counted => raw['counted'] as bool? ?? false;

  /// Whether it arrived after the payment had closed.
  bool get late => raw['late'] as bool? ?? false;

  /// pending (confirming), confirmed (final and credited) or failed.
  String get status => raw['status'] as String;

  /// When payitgo first saw it.
  DateTime get seenAt => DateTime.parse(raw['seen_at'] as String);

  /// When it became final.
  DateTime? get confirmedAt => _date(raw['confirmed_at']);

  /// The sender's address, when the network reports it (for a Bitcoin-like
  /// coin, the first input's): where a refund would go.
  String? get from => raw['from'] as String?;

  /// The address it was sent to: the payment's, or a previous coin's.
  String? get to => raw['to'] as String?;

  /// The block (on XRP, the ledger) that holds it.
  int? get block => raw['block'] as int?;

  /// That block's time.
  DateTime? get madeAt => _date(raw['made_at']);

  /// When it failed: it never became final, and nothing was settled.
  DateTime? get failedAt => _date(raw['failed_at']);

  /// Why it failed: `transaction not found on chain` or `confirmation timeout`.
  String? get failReason => raw['fail_reason'] as String?;

  /// Played by a test payment's simulation: its [txId] names no transaction
  /// on any chain.
  bool get simulated => raw['simulated'] as bool? ?? false;
}

/// A test payment's simulated outcome, and how far it is.
class Simulation {
  Simulation(this.raw);

  final Map<String, dynamic> raw;

  /// One of [Payments.simulationOutcomes].
  String get outcome => raw['outcome'] as String;

  /// requested (asked for on create, waiting for the coin), running or done.
  String get state => raw['state'] as String;
}

/// A coin chosen for a payment before its current one, when the customer
/// changed it. Its address is still watched.
class PreviousCoin {
  PreviousCoin(this.raw);

  final Map<String, dynamic> raw;

  String get token => raw['token'] as String;
  String get chain => raw['chain'] as String;
  String get depositAddress => raw['deposit_address'] as String;
  int? get destinationTag => raw['destination_tag'] as int?;
  String get cryptoAmount => raw['crypto_amount'] as String;
  String get rateLocked => raw['rate_locked'] as String;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

/// A payment, as the API returns it. Amounts are decimal strings; [raw] holds every field.
class Payment {
  Payment(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get orderId => raw['order_id'] as String;

  /// The merchant's id; not on the payer's view (PayitgoCheckout).
  String? get merchantId => raw['merchant_id'] as String?;
  String? get storeId => raw['store_id'] as String?;

  /// pending, partially_paid, detecting, confirmed, underpaid, expired or failed.
  String get status => raw['status'] as String;
  bool get livemode => raw['livemode'] as bool? ?? false;

  /// A test payment's simulated outcome, when it has one.
  Simulation? get simulation => raw['simulation'] == null
      ? null
      : Simulation(raw['simulation'] as Map<String, dynamic>);

  /// Empty until the customer chooses the coin, from [tokenOptions], which
  /// stay while the coin can still change.
  String get token => raw['token'] as String;
  List<TokenInfo> get tokenOptions => [
        for (final t in (raw['token_options'] as List?) ?? const [])
          TokenInfo(t as Map<String, dynamic>)
      ];

  /// The coins chosen before [token], when the customer changed it.
  List<PreviousCoin> get previousCoins => [
        for (final c in (raw['previous_coins'] as List?) ?? const [])
          PreviousCoin(c as Map<String, dynamic>)
      ];
  String get chain => raw['chain'] as String;
  String get depositAddress => raw['deposit_address'] as String;
  int? get destinationTag => raw['destination_tag'] as int?;
  String get cryptoAmount => raw['crypto_amount'] as String;
  String get receivedAmount => raw['received_amount'] as String;

  /// Your price.
  String get usdAmount => raw['usd_amount'] as String;

  /// Your price as you gave it in another currency than the dollar (the
  /// `priceAmount` of [Payments.create]); null for a payment priced in
  /// dollars.
  String? get priceAmount => raw['price_amount'] as String?;

  /// That currency's ISO 4217 code, upper case (`EUR`); null for a payment
  /// priced in dollars.
  String? get priceCurrency => raw['price_currency'] as String?;

  /// The dollar value of one unit of [priceCurrency] that [usdAmount] was
  /// converted at; null for a payment priced in dollars.
  String? get priceRate => raw['price_rate'] as String?;

  /// The coin's dollar price, locked for this payment when its coin was set
  /// ("0" while no coin is chosen).
  String get rateLocked => raw['rate_locked'] as String? ?? '0';

  /// What the customer pays in dollars: the price, plus the fees when you pass them on.
  String get amountDueUsd => raw['amount_due_usd'] as String? ?? usdAmount;
  bool get feesPaidByCustomer => raw['fees_paid_by_customer'] as bool? ?? false;

  /// The network fee quoted for moving the payment, in its coin and in dollars.
  String get networkFee => raw['network_fee'] as String? ?? '0';
  String get networkFeeUsd => raw['network_fee_usd'] as String? ?? '0';

  /// Where the money goes once final: `custodial` (your balance) or `direct` (your payout address).
  String get settlement => raw['settlement'] as String? ?? 'custodial';

  /// Dollar value of every deposit that counts toward the payment.
  String get receivedUsd => raw['received_usd'] as String? ?? '0';

  /// Completed after it had expired.
  bool get paidLate => raw['paid_late'] as bool? ?? false;
  List<Deposit> get deposits => [
        for (final d in (raw['deposits'] as List?) ?? const [])
          Deposit(d as Map<String, dynamic>)
      ];
  String? get txId => raw['tx_id'] as String?;
  bool get overpaid => raw['overpaid'] as bool? ?? false;
  DateTime get expiresAt => DateTime.parse(raw['expires_at'] as String);
  DateTime get createdAt => DateTime.parse(raw['created_at'] as String);
  DateTime? get confirmedAt => raw['confirmed_at'] == null
      ? null
      : DateTime.parse(raw['confirmed_at'] as String);
  String get networkFeeNote => raw['network_fee_note'] as String? ?? '';
  String get qrPayload => raw['qr_payload'] as String? ?? '';
  String? get checkoutToken => raw['checkout_token'] as String?;
  String? get checkoutUrl => raw['checkout_url'] as String?;

  /// Where this payment's events go instead of the webhook's URL, when it was created with one.
  String? get webhookUrl => raw['webhook_url'] as String?;
  String? get description => raw['description'] as String?;
  String? get customerEmail => raw['customer_email'] as String?;
  String? get successUrl => raw['success_url'] as String?;
  String? get cancelUrl => raw['cancel_url'] as String?;
  Map<String, String> get metadata =>
      (raw['metadata'] as Map?)?.cast<String, String>() ?? const {};

  /// True once the payment is final: fulfil the order.
  bool get isConfirmed => status == 'confirmed';

  /// True when the payment can no longer be paid.
  bool get isClosed =>
      const {'confirmed', 'underpaid', 'expired', 'failed'}.contains(status);
}

/// One page of payments.
class PaymentList {
  PaymentList(Map<String, dynamic> json)
      : payments = [
          for (final p in json['payments'] as List)
            Payment(p as Map<String, dynamic>)
        ],
        total = json['total'] as int,
        limit = json['limit'] as int,
        offset = json['offset'] as int;

  final List<Payment> payments;
  final int total;
  final int limit;
  final int offset;
}

/// A token a customer can pay with. [minUsd] and [networkFeeUsd] move with
/// the network's fees.
class TokenInfo {
  TokenInfo(Map<String, dynamic> json)
      : token = json['token'] as String,
        chain = json['chain'] as String,
        minUsd = json['min_usd'].toString(),
        networkFeeUsd = json['network_fee_usd']?.toString() ?? '0',
        amountDueUsd = json['amount_due_usd'] as String?,
        feeNote = json['fee_note'] as String? ?? '';

  final String token;
  final String chain;
  final String minUsd;
  final String networkFeeUsd;

  /// In a payment's token options (or [Tokens.list] with an amount), when fees are passed on: what the customer pays in this token.
  final String? amountDueUsd;
  final String feeNote;
}

/// The webhook (IPN) of the key's mode: the URL every event of the mode is
/// POSTed to, and the secret that signs them; [raw] holds every field.
class WebhookSettings {
  WebhookSettings(this.raw);

  final Map<String, dynamic> raw;

  /// The key's mode: a test key has the test webhook, a live key the live one.
  bool get livemode => raw['livemode'] as bool? ?? false;

  /// Null when not set: events then go only to the payments created with
  /// their own webhook URL.
  String? get url => raw['url'] as String?;

  /// Signs every notification of the mode. Pass it to [Payitgo] as
  /// `webhookSecret`.
  String get secret => raw['secret'] as String;
  DateTime get createdAt => DateTime.parse(raw['created_at'] as String);
  DateTime get updatedAt => DateTime.parse(raw['updated_at'] as String);
}

/// One try at a delivery, or a person's action on it.
class WebhookDeliveryAttempt {
  WebhookDeliveryAttempt(this.raw);

  final Map<String, dynamic> raw;

  DateTime get at => DateTime.parse(raw['at'] as String);

  /// Where it was actually posted.
  String? get url => raw['url'] as String?;

  /// The signature's timestamp.
  String? get signed => raw['signed'] as String?;
  int? get statusCode => raw['status_code'] as int?;
  String? get error => raw['error'] as String?;

  /// The start of the answer your server gave.
  String? get response => raw['response'] as String?;
  int? get millis => raw['millis'] as int?;

  /// Redelivered or resolved, and by whom.
  String? get note => raw['note'] as String?;
}

/// One event on its way to one URL; [raw] holds every field.
class WebhookDelivery {
  WebhookDelivery(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get merchantId => raw['merchant_id'] as String? ?? '';

  /// `account`: the webhook's URL (as it is at each attempt); `payment`: the
  /// payment's own webhook URL.
  String get target => raw['target'] as String;
  String get url => raw['url'] as String;
  String get eventId => raw['event_id'] as String;
  String get eventType => raw['event_type'] as String;

  /// The exact JSON body that is signed and posted.
  String get payload => raw['payload'] as String;

  /// pending, sending, delivered, failed or resolved.
  String get status => raw['status'] as String;
  int get attempts => raw['attempts'] as int? ?? 0;
  int get maxAttempts => raw['max_attempts'] as int? ?? 0;
  DateTime get nextAttemptAt =>
      DateTime.parse(raw['next_attempt_at'] as String);
  int? get lastStatusCode => raw['last_status_code'] as int?;
  String? get lastError => raw['last_error'] as String?;
  DateTime? get lastAttemptAt => _date(raw['last_attempt_at']);
  DateTime? get deliveredAt => _date(raw['delivered_at']);
  DateTime? get resolvedAt => _date(raw['resolved_at']);
  String? get resolutionNote => raw['resolution_note'] as String?;
  DateTime get createdAt => DateTime.parse(raw['created_at'] as String);
  List<WebhookDeliveryAttempt> get history => [
        for (final a in (raw['history'] as List?) ?? const [])
          WebhookDeliveryAttempt(a as Map<String, dynamic>)
      ];
}

class _Transport {
  /// Uses [httpClient], or an http.Client of its own when it is null: only
  /// that one is closed by [close].
  _Transport(String baseUrl, this._apiKey, http.Client? httpClient,
      this._maxRetries, this._timeout)
      : _baseUrl = _checkBaseUrl(baseUrl),
        _ownsClient = httpClient == null,
        _http = httpClient ?? http.Client();

  /// The same gateway and http.Client as [t], without the key; closing it
  /// leaves the client open (it is [t]'s).
  _Transport._keyless(_Transport t)
      : _baseUrl = t._baseUrl,
        _apiKey = null,
        _http = t._http,
        _ownsClient = false,
        _maxRetries = t._maxRetries,
        _timeout = t._timeout;

  final String _baseUrl;
  final String? _apiKey;
  final http.Client _http;
  final bool _ownsClient;
  final int _maxRetries;
  final Duration _timeout;

  static String _checkBaseUrl(String baseUrl) {
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      throw ArgumentError("payitgo: baseUrl must be your gateway's address");
    }
    return trimmed;
  }

  void close() {
    if (_ownsClient) _http.close();
  }

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body}) async {
    // The key-less checkout client may run in a browser (Flutter web): it sends
    // only headers that need no CORS preflight.
    final headers = <String, String>{'Accept': 'application/json'};
    if (_apiKey != null) {
      headers['Authorization'] = 'Bearer $_apiKey';
      headers['X-Payitgo-Client'] = 'payitgo-dart/$_version';
    }
    if (body != null) headers['Content-Type'] = 'application/json';

    for (var attempt = 0;; attempt++) {
      http.Response res;
      try {
        final req = http.Request(method, Uri.parse('$_baseUrl$path'))
          ..headers.addAll(headers);
        if (body != null) req.body = jsonEncode(body);
        res = await http.Response.fromStream(
            await _http.send(req).timeout(_timeout));
      } on Object catch (e) {
        if (attempt < _maxRetries) {
          await _backoff(attempt);
          continue;
        }
        throw PayitgoException('request failed: $e', 0);
      }
      if ((res.statusCode == 429 || res.statusCode >= 500) &&
          attempt < _maxRetries) {
        await _backoff(attempt);
        continue;
      }
      dynamic json;
      try {
        json = res.body.isEmpty ? null : jsonDecode(res.body);
      } on FormatException {
        json = null;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final message = json is Map && json['error'] is String
            ? json['error'] as String
            : 'HTTP ${res.statusCode}';
        throw PayitgoException(message, res.statusCode);
      }
      return json is Map<String, dynamic> ? json : <String, dynamic>{};
    }
  }

  Future<void> _backoff(int attempt) =>
      Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
}

/// The payitgo client, for your server. The API key ([apiKey], a test or a
/// live key: [isLive] says which) is a secret: never put it in a Flutter app;
/// use [PayitgoCheckout] there.
///
/// [webhookSecret] is the signing secret of the key's mode, which
/// `webhooks.constructEvent` uses when given none; [webhookUrl] is sent as the
/// `webhook_url` of every payment created without its own.
///
/// Without [httpClient] the client makes one http.Client of its own, shared
/// with [checkout]; [close] closes it when you are done.
class Payitgo {
  Payitgo(String apiKey,
      {String? baseUrl,
      http.Client? httpClient,
      int maxRetries = 2,
      Duration timeout = const Duration(seconds: 30),
      String? webhookSecret,
      String? webhookUrl})
      : this._(
            _Transport(baseUrl ?? _defaultBaseUrl, _checkKey(apiKey),
                httpClient, maxRetries, timeout),
            webhookSecret,
            webhookUrl);

  Payitgo._(this._transport, String? webhookSecret, String? webhookUrl) {
    payments = Payments._(_transport, webhookUrl);
    tokens = Tokens._(_transport);
    webhooks = Webhooks._(_transport, webhookSecret);
    checkout = PayitgoCheckout._(_Transport._keyless(_transport));
  }

  final _Transport _transport;

  /// The key's mode, once payitgo has said it ([isLive]).
  bool? _live;
  late final Payments payments;
  late final Tokens tokens;

  /// The key's mode's webhook, and `constructEvent` to verify its
  /// notifications.
  late final Webhooks webhooks;
  late final PayitgoCheckout checkout;

  /// Closes the http.Client this client made for itself (and shares with
  /// [checkout]). One passed as `httpClient` is yours to close. Calls made
  /// after closing fail with a [PayitgoException] of status 0.
  void close() => _transport.close();

  /// Whether the key is a live key (its payments are real) rather than a test
  /// key. payitgo says which (`GET /v1/webhook`'s `livemode`) the first time;
  /// the answer is kept for the client's life. Throws a [PayitgoException]
  /// when payitgo refuses the key or cannot be reached.
  Future<bool> isLive() async => _live ??= (await webhooks.get()).livemode;

  static String _checkKey(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError('payitgo: the API key is required');
    }
    return key;
  }
}

class Payments {
  Payments._(this._t, this._webhookUrl);

  final _Transport _t;
  final String? _webhookUrl;

  /// The outcomes a test payment can be made to go through: see [simulate].
  static const simulationOutcomes = [
    'confirmed',
    'overpaid',
    'partially_paid',
    'underpaid',
    'expired',
    'failed',
    'wrong_asset',
    'paid_late',
  ];

  /// Creates a payment. Safe to retry: an order with an open payment returns
  /// that payment. Give the price as [amountUsd] (a String or a num), or as
  /// [priceAmount] (likewise) in [priceCurrency] (an ISO 4217 code such as
  /// `EUR`, `GBP` or `NGN`), which payitgo converts into dollars at the rate
  /// of the moment. Leave [token] out to let the customer choose the coin on
  /// the checkout page, from [tokens] (default: every token the amount
  /// reaches the minimum of). [webhookUrl] (https) gets the payment's events
  /// instead of the webhook's URL, signed with the same secret (default: the
  /// client's `webhookUrl`). [simulate] (test keys only) plays that outcome,
  /// as [simulate] does, once the payment has its coin.
  Future<Payment> create({
    required String orderId,
    Object? amountUsd,
    Object? priceAmount,
    String? priceCurrency,
    String? token,
    List<String>? tokens,
    String? description,
    Map<String, String>? metadata,
    String? customerEmail,
    String? successUrl,
    String? cancelUrl,
    String? webhookUrl,
    String? simulate,
  }) async {
    final hookUrl = webhookUrl ?? _webhookUrl;
    final body = <String, dynamic>{
      'order_id': orderId,
      if (amountUsd != null) 'amount_usd': amountUsd.toString(),
      if (priceAmount != null) 'price_amount': priceAmount.toString(),
      if (priceCurrency != null) 'price_currency': priceCurrency,
      if (token != null) 'token': token,
      if (tokens != null) 'tokens': tokens,
      if (description != null) 'description': description,
      if (metadata != null) 'metadata': metadata,
      if (customerEmail != null) 'customer_email': customerEmail,
      if (successUrl != null) 'success_url': successUrl,
      if (cancelUrl != null) 'cancel_url': cancelUrl,
      if (hookUrl != null && hookUrl.isNotEmpty) 'webhook_url': hookUrl,
      if (simulate != null) 'simulate': simulate,
    };
    return Payment(await _t.request('POST', '/v1/payments', body: body));
  }

  /// A payment by its id or by your order id (the order's open payment).
  Future<Payment> retrieve(String id) async => Payment(
      await _t.request('GET', '/v1/payments/${Uri.encodeComponent(id)}'));

  /// Sets the coin of a payment created without one, when the customer chose
  /// it on your own page: one of its [Payment.tokenOptions]. [id] is the
  /// payment's id or your order id. Returns the whole payment, now
  /// with its address, amount, locked rate and a deadline 15 minutes away.
  /// Another coin changes it while the payment still has [Payment.tokenOptions];
  /// once it can no longer change, a [PayitgoException] with status 409.
  Future<Payment> selectToken(String id, String token) async => Payment(await _t
      .request('POST', '/v1/payments/${Uri.encodeComponent(id)}/token',
          body: {'token': token}));

  /// Plays [outcome] (one of [simulationOutcomes]) on a test payment: payitgo
  /// sends its deposits, status changes and webhooks a few seconds apart,
  /// with no coins. [id] is the payment's id or your order id.
  /// Returns the whole payment, with its [Payment.simulation]. A live payment
  /// is a [PayitgoException] with status 400; a simulation that is still
  /// running, 409.
  Future<Payment> simulate(String id, String outcome) async => Payment(await _t
      .request('POST', '/v1/payments/${Uri.encodeComponent(id)}/simulate',
          body: {'outcome': outcome}));

  /// Payments of the key's mode, newest first. [storeId] keeps the payments
  /// of one store (ignored for a storefront's key, which sees its own).
  Future<PaymentList> list(
      {String? status,
      String? chain,
      String? token,
      String? storeId,
      int? limit,
      int? offset}) async {
    final q = <String, String>{
      if (status != null) 'status': status,
      if (chain != null) 'chain': chain,
      if (token != null) 'token': token,
      if (storeId != null) 'store_id': storeId,
      if (limit != null) 'limit': '$limit',
      if (offset != null) 'offset': '$offset',
    };
    final query = q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';
    return PaymentList(await _t.request('GET', '/v1/payments$query'));
  }
}

class Tokens {
  Tokens._(this._t);

  final _Transport _t;

  /// The tokens a customer can pay with in the key's mode. With [amountUsd]
  /// (a String or a num, as in [Payments.create]), only the ones a payment of
  /// that amount offers (its token options), each with
  /// [TokenInfo.amountDueUsd] when fees are passed on.
  Future<List<TokenInfo>> list({Object? amountUsd}) async {
    final query = amountUsd == null
        ? ''
        : '?${Uri(queryParameters: {
                'amount_usd': amountUsd.toString()
              }).query}';
    final json = await _t.request('GET', '/v1/tokens$query');
    return [
      for (final t in json['tokens'] as List)
        TokenInfo(t as Map<String, dynamic>)
    ];
  }
}

/// The webhook (IPN) of the key's mode: a test key manages the test webhook,
/// a live key the live one. A storefront's key may read and test it, not
/// change it.
class Webhooks {
  Webhooks._(this._t, this._secret);

  final _Transport _t;
  final String? _secret;

  /// The events payitgo sends. A test ([test]) sends `ping`.
  static const events = [
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
    'ping',
  ];

  /// The webhook: its URL (null when not set) and its signing secret.
  Future<WebhookSettings> get() async =>
      WebhookSettings((await _t.request('GET', '/v1/webhook'))['webhook']
          as Map<String, dynamic>);

  /// Sets the URL every event of the mode is POSTed to: https, on a public
  /// host, accepting POST requests. Safe to retry.
  Future<WebhookSettings> set(String url) async => WebhookSettings(
      (await _t.request('PUT', '/v1/webhook', body: {'url': url}))['webhook']
          as Map<String, dynamic>);

  /// Stops POSTing to the URL (payments with their own webhook URL still get
  /// theirs); the secret stays.
  Future<WebhookSettings> remove() async =>
      WebhookSettings((await _t.request('DELETE', '/v1/webhook'))['webhook']
          as Map<String, dynamic>);

  /// Queues a signed `ping` event to the URL and returns its delivery.
  Future<WebhookDelivery> test() async =>
      WebhookDelivery((await _t.request('POST', '/v1/webhook/test'))['delivery']
          as Map<String, dynamic>);

  /// Verifies a webhook request and returns its event; see
  /// `Webhook.constructEvent`. [secret] defaults to the client's
  /// `webhookSecret`; without either it throws
  /// [SignatureVerificationException].
  WebhookEvent constructEvent(Object payload, String? signatureHeader,
      {String? secret, Duration tolerance = Webhook.defaultTolerance}) {
    final key = (secret != null && secret.isNotEmpty) ? secret : _secret;
    if (key == null || key.isEmpty) {
      throw SignatureVerificationException(
          "no webhook secret: pass one, or set the client's webhookSecret");
    }
    return Webhook.constructEvent(payload, signatureHeader, key,
        tolerance: tolerance);
  }
}

/// The payer's side of a payment, without any key: safe in a Flutter app.
/// Your backend creates the payment and hands the app its `checkout_token`.
///
/// ```dart
/// final checkout = PayitgoCheckout(baseUrl: 'https://api.example.com');
/// final payment = await checkout.retrieve(checkoutToken);
/// await for (final p in checkout.watch(checkoutToken)) { /* update the UI */ }
/// checkout.close(); // when the app no longer needs it
/// ```
class PayitgoCheckout {
  PayitgoCheckout({String? baseUrl, http.Client? httpClient})
      : _t = _Transport(baseUrl ?? _defaultBaseUrl, null, httpClient, 2,
            const Duration(seconds: 30));

  PayitgoCheckout._(this._t);

  final _Transport _t;

  /// Closes the http.Client this checkout client made for itself. One passed
  /// as `httpClient`, or the one a [Payitgo]'s `checkout` shares with it, is
  /// left open.
  void close() => _t.close();

  /// The payer's view of a payment, by its checkout token.
  Future<Payment> retrieve(String checkoutToken) async => Payment(await _t
      .request('GET', '/checkout/${Uri.encodeComponent(checkoutToken)}'));

  /// The customer's choice of coin for a payment created without one: the
  /// payment comes back with its address, amount and deadline.
  Future<Payment> selectToken(String checkoutToken, String token) async =>
      Payment(await _t.request(
          'POST', '/checkout/${Uri.encodeComponent(checkoutToken)}/token',
          body: {'token': token}));

  /// Plays [outcome] (one of [Payments.simulationOutcomes]) on a test
  /// payment, for a test checkout's "simulate" buttons: its deposits and
  /// statuses follow a few seconds apart, with no coins ([watch] shows
  /// them). A live payment is a [PayitgoException] with status 400; a
  /// simulation that is still running, 409.
  Future<Payment> simulate(String checkoutToken, String outcome) async =>
      Payment(await _t.request(
          'POST', '/checkout/${Uri.encodeComponent(checkoutToken)}/simulate',
          body: {'outcome': outcome}));

  /// Polls the payment every [every] and emits it at once, then whenever its
  /// status changes. The stream ends once the payment can change no more:
  /// confirmed or failed, or expired or underpaid with its 24 hours for late
  /// payments over (at once for a payment expired without a coin, which has
  /// no address). Until then an expired or underpaid payment is still
  /// followed, so a late payment shows as detecting and then confirmed.
  /// Cancel the subscription to stop sooner.
  Stream<Payment> watch(String checkoutToken,
      {Duration every = const Duration(seconds: 5)}) async* {
    String? last;
    while (true) {
      final p = await retrieve(checkoutToken);
      if (p.status != last) {
        last = p.status;
        yield p;
      }
      if (_settled(p)) return;
      await Future.delayed(every);
    }
  }

  static bool _settled(Payment p) => switch (p.status) {
        'confirmed' || 'failed' => true,
        'expired' when p.token.isEmpty => true,
        'expired' ||
        'underpaid' =>
          DateTime.now().isAfter(p.expiresAt.add(_lateWindow)),
        _ => false,
      };
}
