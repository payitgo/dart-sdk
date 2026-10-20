part of 'client.dart';

// Mass payouts: you pay your own clients (payroll, prizes, withdrawals from
// your platform) from your payout wallet, one address per network that you
// top up. Payout requests come in one by one and wait in your open list
// until sent; batches send a whole list at once. Every payment is checked
// and priced before anything leaves the wallet. A payment can be a claim
// link (its recipient chooses the coin and the address), or be paid in
// another coin than the wallet's, converted on its way.

/// A decimal the API sends as a string; "0" when absent.
String _dec(Object? v) => v == null ? '0' : '$v';

List<T> _each<T>(Object? list, T Function(Map<String, dynamic>) make) => [
      for (final e in (list as List?) ?? const [])
        make(e as Map<String, dynamic>)
    ];

String _query(Map<String, String> q) =>
    q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';

/// A list's filter and page, as a query string.
String _page(String? status, int? limit, int? offset) => _query({
      if (status != null) 'status': status,
      if (limit != null) 'limit': '$limit',
      if (offset != null) 'offset': '$offset',
    });

/// One payment to a recipient, as you give it to [Payouts.quote],
/// [PayoutBatches.create] and [PayoutBatches.addItems]. Fields left null
/// are not sent.
class PayoutItemInput {
  const PayoutItemInput({
    required this.asset,
    required this.amount,
    this.address,
    this.reference,
    this.tag,
    this.name,
    this.email,
    this.note,
    this.claim,
    this.claimAssets,
  });

  /// The coin, one of the payout coins: `USDT_TRC20`, `USDT_BEP20`, `TRX`,
  /// `BNB`, … In a batch that converts, a coin other than its
  /// `convertFrom` is paid from that one, converted on its way.
  final String asset;

  /// The recipient's address on the coin's network. Required, unless the
  /// payment is a claim link: then leave it null.
  final String? address;

  /// How much of the coin, a String or a num, sent as `amount.toString()`:
  /// prefer a String to a double. With `feePaidBy: 'recipient'` the fees
  /// come out of it.
  final Object amount;

  /// Your id for the payment, unique in its mode: a reference another
  /// payment carries makes this one invalid (`duplicate_reference`).
  final String? reference;

  /// A destination tag, for an XRP address.
  final int? tag;

  /// Who it is for, and why: kept with it. Only a claim link uses [email]:
  /// its link is emailed there. An email alone makes no claim link.
  final String? name;
  final String? email;
  final String? note;

  /// True makes it a claim link: no address, its recipient opens the link
  /// and chooses where to receive it. Without an [email], you share the
  /// link ([PayoutClaim.url]) yourself.
  final bool? claim;

  /// A claim link's other coins its recipient may choose, paid at the same
  /// dollar value; giving them makes it a claim link too.
  final List<String>? claimAssets;

  Map<String, dynamic> toJson() => {
        'asset': asset,
        if (address != null) 'address': address,
        'amount': amount.toString(),
        if (reference != null) 'reference': reference,
        if (tag != null) 'tag': tag,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (note != null) 'note': note,
        if (claim != null) 'claim': claim,
        if (claimAssets != null) 'claim_assets': claimAssets,
      };
}

/// Something wrong with a payment (in [PayoutItem.errors]: it is left out)
/// or worth knowing (in [PayoutItem.warnings]: it still goes).
class PayoutIssue {
  PayoutIssue(this.raw);

  final Map<String, dynamic> raw;

  /// For your code: `wrong_network`, `below_minimum`, `new_recipient`, …
  /// Codes may be added: treat an unknown one by where it is.
  String get code => raw['code'] as String;

  /// The field at fault: `asset`, `amount`, `address`, `tag` or `reference`.
  String? get field => raw['field'] as String?;

  /// For people: what is wrong.
  String get message => raw['message'] as String;

  /// For people: what to do.
  String? get hint => raw['hint'] as String?;
}

/// Who a payment is for, as you named them; each null when not given.
class PayoutRecipient {
  PayoutRecipient(this.raw);

  final Map<String, dynamic> raw;

  String? get name => raw['name'] as String?;
  String? get email => raw['email'] as String?;
  String? get note => raw['note'] as String?;
}

/// A claim link's state: the payment's recipient opens [url] and chooses
/// the coin and the address.
class PayoutClaim {
  PayoutClaim(this.raw);

  final Map<String, dynamic> raw;

  /// Where the link is emailed; null when you share it yourself.
  String? get email => raw['email'] as String?;

  /// The other coins its recipient may choose, besides the payment's own.
  List<String> get assets =>
      (raw['assets'] as List?)?.cast<String>() ?? const [];

  /// It can be claimed until then; past it, the payment is expired and its
  /// money free again.
  DateTime? get expiresAt => _date(raw['expires_at']);
  DateTime? get claimedAt => _date(raw['claimed_at']);

  /// How many times the link was emailed, and when last.
  int get emailed => raw['emailed'] as int? ?? 0;
  DateTime? get lastEmailAt => _date(raw['last_email_at']);

  /// How many times it was extended.
  int get extended => raw['extended'] as int? ?? 0;

  /// The link, to share with the recipient.
  String? get url => raw['url'] as String?;

  /// A link without an email: the 6 digits its recipient enters to claim
  /// it. Give it another way than the link (a call, a text message), so
  /// the link alone pays no one.
  String? get pin => raw['pin'] as String?;

  /// 5 wrong PINs were entered: a new PIN from the dashboard unlocks it.
  bool get pinLocked => raw['pin_locked'] as bool? ?? false;

  /// What it was funded with when its recipient chose another coin (paid
  /// at the same dollar value).
  String? get fundedAsset => raw['funded_asset'] as String?;
  String? get fundedAmount => raw['funded_amount']?.toString();
}

/// A payment paid in another coin than the wallet's, converted on its way:
/// you asked to pay [toAmount] of [to]; its recipient receives about
/// [estimate], and [amountOut] once it is sent.
class PayoutConversion {
  PayoutConversion(this.raw);

  final Map<String, dynamic> raw;

  /// The coin the recipient receives.
  String get to => raw['to'] as String;
  String get ticker => raw['ticker'] as String? ?? '';
  String get network => raw['network'] as String? ?? '';

  /// What you asked to pay, in [to].
  String get toAmount => _dec(raw['to_amount']);

  /// About what arrives, in [to].
  String get estimate => _dec(raw['estimate']);

  /// What arrived, once sent.
  String? get amountOut => raw['amount_out']?.toString();
}

/// One payment to a recipient: a payout request, or a row of a batch.
/// Amounts are decimal strings in the payment's coin (for a converted
/// payment, the wallet's coin: see [convert]); [raw] holds every field.
class PayoutItem {
  PayoutItem(this.raw);

  final Map<String, dynamic> raw;

  /// Null on a quote's payments, which are not kept.
  String? get id => raw['id'] as String?;
  String? get merchantId => raw['merchant_id'] as String?;
  bool get livemode => raw['livemode'] as bool? ?? false;

  /// Its batch: your open list of payout requests until it is sent.
  String? get batchId => raw['batch_id'] as String?;

  /// Your id for it, unique in its mode.
  String? get reference => raw['reference'] as String?;

  /// A reference it was given that another payment carries: it keeps none,
  /// and is invalid.
  String? get refusedReference => raw['refused_reference'] as String?;

  /// The reference of a payment canceled or failed (never sent), given back
  /// for a new payment to use; [reference] is then empty.
  String? get releasedReference => raw['released_reference'] as String?;

  /// Its place in its batch, from 1.
  int get row => raw['row'] as int? ?? 0;
  PayoutRecipient get recipient =>
      PayoutRecipient((raw['recipient'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{});
  String get asset => raw['asset'] as String;

  /// What people call the coin (`USDT`) and its icon; null for a coin
  /// payouts do not know.
  String? get ticker => raw['ticker'] as String?;
  String? get iconUrl => raw['icon_url'] as String?;
  String get chain => raw['chain'] as String? ?? '';

  /// The recipient's address; for a converted payment, on [convert]'s
  /// network. Empty for a claim link not claimed yet.
  String get address => raw['address'] as String? ?? '';
  int? get tag => raw['tag'] as int?;

  /// What you asked to pay.
  String get amount => _dec(raw['amount']);

  /// What reaches the recipient: [amount], less [fee] when the recipient
  /// pays the fees.
  String get sendAmount => _dec(raw['send_amount']);
  String get platformFee => _dec(raw['platform_fee']);
  String get networkFee => _dec(raw['network_fee']);

  /// [platformFee] and [networkFee] together.
  String get fee => _dec(raw['fee']);

  /// What it takes from the payout wallet.
  String get debit => _dec(raw['debit']);

  /// The coin's dollar price when it was priced, and [amount] in dollars.
  String get usdRate => _dec(raw['usd_rate']);
  String get amountUsd => _dec(raw['amount_usd']);

  /// validating, ready, invalid ([errors] say why), cooling, queued,
  /// sending, sent, failed or canceled; a claim link's also claimable
  /// (funded, waiting for its recipient) or expired (never claimed, its
  /// money free again).
  String get status => raw['status'] as String;
  List<PayoutIssue> get errors => _each(raw['errors'], PayoutIssue.new);
  List<PayoutIssue> get warnings => _each(raw['warnings'], PayoutIssue.new);

  /// A new recipient's payment waits until then.
  DateTime? get coolingUntil => _date(raw['cooling_until']);

  /// Its transaction, once sent (made up in test mode).
  String? get txId => raw['tx_id'] as String?;

  /// The transaction on the block explorer; live only.
  String? get explorerUrl => raw['explorer_url'] as String?;
  String? get failReason => raw['fail_reason'] as String?;

  /// A claim link's state; null for a payment to an address you gave.
  PayoutClaim? get claim => raw['claim'] == null
      ? null
      : PayoutClaim(raw['claim'] as Map<String, dynamic>);

  /// How it is converted on its way; null when it is paid in the wallet's
  /// own coin.
  PayoutConversion? get convert => raw['convert'] == null
      ? null
      : PayoutConversion(raw['convert'] as Map<String, dynamic>);

  /// What converting costs, part of [fee]; "0" when not converted.
  String get conversionFee => _dec(raw['conversion_fee']);

  /// The fee given back for a payment never sent, taken off your next
  /// fees in its coin.
  String? get feeCredit => raw['fee_credit']?.toString();
  DateTime? get sentAt => _date(raw['sent_at']);

  /// Null on a quote's payments.
  DateTime? get createdAt => _date(raw['created_at']);
  DateTime? get updatedAt => _date(raw['updated_at']);
}

/// A batch's valid payments in one coin.
class PayoutAssetTotal {
  PayoutAssetTotal(this.raw);

  final Map<String, dynamic> raw;

  String get asset => raw['asset'] as String;
  String get ticker => raw['ticker'] as String? ?? '';
  String get iconUrl => raw['icon_url'] as String? ?? '';
  String get chain => raw['chain'] as String? ?? '';

  /// The network for people: `Tron (TRC-20)`.
  String get network => raw['network'] as String? ?? '';

  /// How many payments.
  int get items => raw['items'] as int? ?? 0;
  String get amount => _dec(raw['amount']);
  String get sendAmount => _dec(raw['send_amount']);
  String get platformFee => _dec(raw['platform_fee']);
  String get networkFee => _dec(raw['network_fee']);
  String get fee => _dec(raw['fee']);

  /// What the wallet gives for them, and its dollar value.
  String get debit => _dec(raw['debit']);
  String get debitUsd => _dec(raw['debit_usd']);

  /// What sending them together saves in network fees.
  String get savedUsd => _dec(raw['saved_usd']);
}

/// A batch's payments by status.
class PayoutCounts {
  PayoutCounts(this.raw);

  final Map<String, dynamic> raw;

  int _n(String k) => raw[k] as int? ?? 0;
  int get total => _n('total');
  int get invalid => _n('invalid');
  int get ready => _n('ready');
  int get cooling => _n('cooling');
  int get queued => _n('queued');
  int get sending => _n('sending');
  int get sent => _n('sent');
  int get failed => _n('failed');
  int get canceled => _n('canceled');
  int get claimable => _n('claimable');
  int get expired => _n('expired');
}

/// How much more of a coin the payout wallet needs, and where to send it.
class PayoutShortfall {
  PayoutShortfall(this.raw);

  final Map<String, dynamic> raw;

  String get asset => raw['asset'] as String;
  String get network => raw['network'] as String? ?? '';
  String get amount => _dec(raw['amount']);
  String get address => raw['address'] as String;
}

/// Why a batch waits for funding, and since when.
class PayoutWaiting {
  PayoutWaiting(this.raw);

  final Map<String, dynamic> raw;

  /// funds (send the [shortfall]), daily_limit (funded from 00:00 UTC) or
  /// paused (contact support).
  String get reason => raw['reason'] as String;

  /// The same, for people.
  String get note => raw['note'] as String? ?? '';
  DateTime get since => DateTime.parse(raw['since'] as String);
  List<PayoutShortfall> get shortfall =>
      _each(raw['shortfall'], PayoutShortfall.new);
}

/// A team member's approval of a batch.
class PayoutApproval {
  PayoutApproval(this.raw);

  final Map<String, dynamic> raw;

  String get userId => raw['user_id'] as String;
  DateTime get at => DateTime.parse(raw['at'] as String);
}

/// Who rejected a batch, when, and why.
class PayoutRejection {
  PayoutRejection(this.raw);

  final Map<String, dynamic> raw;

  String get by => raw['by'] as String;
  DateTime get at => DateTime.parse(raw['at'] as String);
  String get reason => raw['reason'] as String? ?? '';
}

/// A batch of payments, checked, priced, approved and funded together; or
/// your open list of payout requests ([open]). [raw] holds every field.
class PayoutBatch {
  PayoutBatch(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get merchantId => raw['merchant_id'] as String? ?? '';
  bool get livemode => raw['livemode'] as bool? ?? false;

  /// Your id for it, unique in its mode.
  String? get reference => raw['reference'] as String?;
  String get name => raw['name'] as String? ?? '';

  /// api, dashboard, csv, requests (payout requests sent together) or
  /// schedule (a schedule's run).
  String get source => raw['source'] as String? ?? '';

  /// Made of payout requests.
  bool get inbox => raw['inbox'] as bool? ?? false;

  /// Your open list of payout requests, where they wait until sent: never
  /// submitted itself.
  bool get open => raw['open'] as bool? ?? false;

  /// The team member who made it, or the API key's id ([byApiKey]).
  String get createdBy => raw['created_by'] as String? ?? '';
  bool get byApiKey => raw['by_api_key'] as bool? ?? false;

  /// merchant (fees on top) or recipient (fees out of each amount).
  String get feePaidBy => raw['fee_paid_by'] as String? ?? '';

  /// same_network (each payment from the wallet's own coin) or convert
  /// (every payment in another coin than [convertFrom] paid from it,
  /// converted on its way).
  String get convert => raw['convert'] as String? ?? '';
  String? get convertFrom => raw['convert_from'] as String?;

  /// Where its events go instead of your webhook's URL.
  String? get webhookUrl => raw['webhook_url'] as String?;

  /// validating, quoted, pending_approval, awaiting_funds, processing,
  /// completed, canceled or rejected.
  String get status => raw['status'] as String;

  /// While awaiting_funds: why, and for funds what to send where.
  PayoutWaiting? get waiting => raw['waiting'] == null
      ? null
      : PayoutWaiting(raw['waiting'] as Map<String, dynamic>);

  /// Its valid payments, per coin.
  List<PayoutAssetTotal> get totals =>
      _each(raw['totals'], PayoutAssetTotal.new);
  PayoutCounts get counts => PayoutCounts(
      (raw['counts'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{});

  /// What it takes from the wallet, in dollars.
  String get totalUsd => _dec(raw['total_usd']);

  /// Its prices hold until then; submitting later asks for a new quote.
  DateTime? get quoteExpiresAt => _date(raw['quote_expires_at']);
  int get approvalsNeeded => raw['approvals_needed'] as int? ?? 0;
  List<PayoutApproval> get approvals =>
      _each(raw['approvals'], PayoutApproval.new);
  PayoutRejection? get rejection => raw['rejection'] == null
      ? null
      : PayoutRejection(raw['rejection'] as Map<String, dynamic>);
  String? get submittedBy => raw['submitted_by'] as String?;
  DateTime? get submittedAt => _date(raw['submitted_at']);
  DateTime? get fundedAt => _date(raw['funded_at']);
  DateTime? get completedAt => _date(raw['completed_at']);
  String? get canceledBy => raw['canceled_by'] as String?;
  DateTime? get canceledAt => _date(raw['canceled_at']);
  DateTime get createdAt => DateTime.parse(raw['created_at'] as String);
  DateTime get updatedAt => DateTime.parse(raw['updated_at'] as String);
}

/// One page of batches.
class PayoutBatchList {
  PayoutBatchList(Map<String, dynamic> json)
      : batches = _each(json['batches'], PayoutBatch.new),
        total = json['total'] as int,
        limit = json['limit'] as int,
        offset = json['offset'] as int;

  final List<PayoutBatch> batches;
  final int total;
  final int limit;
  final int offset;
}

/// One page of a batch's payments.
class PayoutItemList {
  PayoutItemList(Map<String, dynamic> json)
      : items = _each(json['items'], PayoutItem.new),
        total = json['total'] as int,
        limit = json['limit'] as int,
        offset = json['offset'] as int;

  final List<PayoutItem> items;
  final int total;
  final int limit;
  final int offset;
}

/// What sending your valid payout requests in one coin takes ([needed])
/// against what the wallet can spend: [topUp] is the difference to send
/// to [address] first.
class PayoutCoverage {
  PayoutCoverage(this.raw);

  final Map<String, dynamic> raw;

  String get asset => raw['asset'] as String;
  String get ticker => raw['ticker'] as String? ?? '';
  String get network => raw['network'] as String? ?? '';
  String get needed => _dec(raw['needed']);
  String get spendable => _dec(raw['spendable']);
  String get topUp => _dec(raw['top_up']);
  String get address => raw['address'] as String? ?? '';
}

/// Your open payout requests: the list itself (a batch with its totals and
/// counts), what sending them takes of each coin, and one page of them.
class PayoutInbox {
  PayoutInbox(Map<String, dynamic> json)
      : inbox = PayoutBatch(json['inbox'] as Map<String, dynamic>),
        coverage = _each(json['coverage'], PayoutCoverage.new),
        items = _each(json['items'], PayoutItem.new),
        total = json['total'] as int,
        limit = json['limit'] as int,
        offset = json['offset'] as int;

  final PayoutBatch inbox;
  final List<PayoutCoverage> coverage;
  final List<PayoutItem> items;
  final int total;
  final int limit;
  final int offset;
}

/// The totals a batch of the quoted payments would have.
class PayoutQuote {
  PayoutQuote(this.raw);

  final Map<String, dynamic> raw;

  bool get livemode => raw['livemode'] as bool? ?? false;
  String get feePaidBy => raw['fee_paid_by'] as String? ?? '';
  List<PayoutAssetTotal> get totals =>
      _each(raw['totals'], PayoutAssetTotal.new);
  String get totalUsd => _dec(raw['total_usd']);
  PayoutCounts get counts => PayoutCounts(
      (raw['counts'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{});
}

/// What [Payouts.quote] returns: the [quote], and the [items] as they would
/// be, each with its fees and issues. Nothing is kept.
class PayoutQuoteResult {
  PayoutQuoteResult(Map<String, dynamic> json)
      : quote = PayoutQuote(json['quote'] as Map<String, dynamic>),
        items = _each(json['items'], PayoutItem.new);

  final PayoutQuote quote;
  final List<PayoutItem> items;
}

/// What a payout wallet holds of one coin.
class PayoutWalletAsset {
  PayoutWalletAsset(this.raw);

  final Map<String, dynamic> raw;

  String get asset => raw['asset'] as String;
  String get ticker => raw['ticker'] as String? ?? '';
  String get iconUrl => raw['icon_url'] as String? ?? '';

  /// On chain (on paper in test mode).
  String get balance => _dec(raw['balance']);

  /// Promised to payments funded, and fees and withdrawals not sent yet.
  String get reserved => _dec(raw['reserved']);

  /// [balance] less [reserved].
  String get spendable => _dec(raw['spendable']);

  /// What batches waiting for funds need beyond [spendable]: the top-up to
  /// send now.
  String get needed => _dec(raw['needed']);
}

/// Your payout wallet on one network: where to top it up, and what it
/// holds of each coin it pays in.
class PayoutWallet {
  PayoutWallet(this.raw);

  final Map<String, dynamic> raw;

  /// The network: tron, bsc, ethereum, bitcoin, …
  String get chain => raw['chain'] as String;

  /// The network for people: `Tron`, `BNB Smart Chain`.
  String get network => raw['network'] as String? ?? '';

  /// Where to send that network's payout coins.
  String get address => raw['address'] as String;

  /// The address on the block explorer; live only.
  String? get explorerUrl => raw['explorer_url'] as String?;
  bool get livemode => raw['livemode'] as bool? ?? false;
  List<PayoutWalletAsset> get assets =>
      _each(raw['assets'], PayoutWalletAsset.new);

  /// Why its balances could not be read just now (they are then "0").
  String? get error => raw['error'] as String?;
}

/// A payout wallet's coin sent back to one of your payout addresses: the
/// data of a `payout_wallet.withdrawn` event.
class PayoutWithdrawal {
  PayoutWithdrawal(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get merchantId => raw['merchant_id'] as String? ?? '';
  bool get livemode => raw['livemode'] as bool? ?? false;
  String get asset => raw['asset'] as String;
  String get chain => raw['chain'] as String? ?? '';

  /// What left the wallet; [fee] went to the network and payitgo, and
  /// [sendAmount] arrived.
  String get amount => _dec(raw['amount']);
  String get fee => _dec(raw['fee']);
  String get sendAmount => _dec(raw['send_amount']);
  String get addressId => raw['address_id'] as String? ?? '';
  String get address => raw['address'] as String;
  int? get tag => raw['tag'] as int?;

  /// requested, sending, sent or failed.
  String get status => raw['status'] as String;
  String? get txId => raw['tx_id'] as String?;
  String? get explorerUrl => raw['explorer_url'] as String?;
  String get requestedBy => raw['requested_by'] as String? ?? '';
  DateTime get createdAt => DateTime.parse(raw['created_at'] as String);
  DateTime get updatedAt => DateTime.parse(raw['updated_at'] as String);
  DateTime? get sentAt => _date(raw['sent_at']);
}

/// A schedule, which makes the same batch again and again (a payroll): the
/// summary a `payout_schedule.run` event carries, without its payments.
/// Schedules are set up in the dashboard.
class PayoutSchedule {
  PayoutSchedule(this.raw);

  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  bool get livemode => raw['livemode'] as bool? ?? false;
  String get name => raw['name'] as String? ?? '';

  /// active or paused.
  String get status => raw['status'] as String? ?? '';

  /// weekly, biweekly or monthly.
  String get cadence => raw['cadence'] as String? ?? '';
  DateTime? get nextRunAt => _date(raw['next_run_at']);
  DateTime? get lastRunAt => _date(raw['last_run_at']);

  /// The batch its last run made.
  String? get lastBatchId => raw['last_batch_id'] as String?;

  /// Why its last run made no batch; empty when it made one.
  String? get lastError => raw['last_error'] as String?;
}

/// What a schedule's next run lacks: the data of a
/// `payout_schedule.funding_needed` event, sent a few days before the run.
class PayoutScheduleFunding {
  PayoutScheduleFunding(Map<String, dynamic> data)
      : schedule = PayoutSchedule(data['schedule'] as Map<String, dynamic>),
        shortfall = _each(data['shortfall'], PayoutShortfall.new);

  final PayoutSchedule schedule;

  /// What to send to the payout wallet, coin by coin, and where.
  final List<PayoutShortfall> shortfall;
}

/// Payout requests: each of your clients' payouts, sent as it comes in.
/// payitgo checks and prices it, keeps it in your open list with its
/// costs, and sends the list when you ask ([send]), or by itself with
/// auto-send in your payout settings. Reading works with any key; the rest
/// needs a key with payouts on.
class Payouts {
  Payouts._(this._t);

  final _Transport _t;

  static PayoutItem _item(Map<String, dynamic> json) =>
      PayoutItem(json['item'] as Map<String, dynamic>);

  /// Adds a client's payout request to your open list, checked and priced
  /// at once. Safe to retry: a [reference] another payment carries returns
  /// that payment (200 instead of 201). An invalid request is kept too,
  /// with [PayoutItem.errors] saying why, and is never sent. The other
  /// parameters are those of [PayoutItemInput]: leave [address] out for a
  /// claim link ([claim] or [claimAssets]).
  Future<PayoutItem> request({
    required String reference,
    required String asset,
    required Object amount,
    String? address,
    int? tag,
    String? name,
    String? email,
    String? note,
    bool? claim,
    List<String>? claimAssets,
  }) async =>
      _item(await _t.request('POST', '/v1/payouts',
          body: PayoutItemInput(
                  reference: reference,
                  asset: asset,
                  address: address,
                  amount: amount,
                  tag: tag,
                  name: name,
                  email: email,
                  note: note,
                  claim: claim,
                  claimAssets: claimAssets)
              .toJson()));

  /// A payment by its id: a payout request, or any batch's row.
  Future<PayoutItem> retrieve(String id) async =>
      _item(await _t.request('GET', '/v1/payouts/${Uri.encodeComponent(id)}'));

  /// A payment by your reference.
  Future<PayoutItem> retrieveByReference(String reference) async =>
      _item(await _t.request(
          'GET', '/v1/payouts${_query({'reference': reference})}'));

  /// Your open payout requests, what sending the valid ones takes of each
  /// coin against what the wallet can spend, and one page of them.
  /// [status] takes one status or several, comma-separated
  /// (`'ready'`, `'invalid'`).
  Future<PayoutInbox> inbox({String? status, int? limit, int? offset}) async =>
      PayoutInbox(await _t.request(
          'GET', '/v1/payouts/inbox${_page(status, limit, offset)}'));

  /// Sends your valid payout requests (or only those of [ids]) as a new
  /// batch, priced again and submitted: it then waits for its approvals
  /// and the funds, or starts. The rest stay in the list. An empty [ids]
  /// throws an ArgumentError: leave it null to send them all.
  Future<PayoutBatch> send({List<String>? ids}) async {
    if (ids != null && ids.isEmpty) {
      throw ArgumentError(
          'payitgo: ids is empty: leave it null to send every valid request');
    }
    return PayoutBatch((await _t.request('POST', '/v1/payouts/send',
            body: ids == null ? null : {'ids': ids}))['batch']
        as Map<String, dynamic>);
  }

  /// Takes a payout request out: one still in your open list is removed
  /// (its reference free again); one sent but not on its way yet is
  /// canceled. Either comes back with status `canceled`.
  Future<PayoutItem> cancel(String id) async => _item(
      await _t.request('DELETE', '/v1/payouts/${Uri.encodeComponent(id)}'));

  /// What up to 100 payments would cost, checked and priced as in a batch,
  /// without keeping anything: show a client their fee before they ask.
  /// [feePaidBy], [convert] and [convertFrom] are those of
  /// [PayoutBatches.create].
  Future<PayoutQuoteResult> quote(
          {required List<PayoutItemInput> items,
          String? feePaidBy,
          String? convert,
          String? convertFrom}) async =>
      PayoutQuoteResult(await _t.request('POST', '/v1/payout-quotes', body: {
        if (feePaidBy != null) 'fee_paid_by': feePaidBy,
        if (convert != null) 'convert': convert,
        if (convertFrom != null) 'convert_from': convertFrom,
        'items': [for (final i in items) i.toJson()],
      }));
}

/// Batches: a whole list of payments at once. Reading works with any key;
/// the rest needs a key with payouts on.
class PayoutBatches {
  PayoutBatches._(this._t);

  final _Transport _t;

  static PayoutBatch _batch(Map<String, dynamic> json) =>
      PayoutBatch(json['batch'] as Map<String, dynamic>);

  String _path(String id, [String action = '']) =>
      '/v1/payout-batches/${Uri.encodeComponent(id)}$action';

  /// Makes a batch of 1 to 1000 [items], checked and priced (more than 100
  /// in the background: the batch comes back `validating`, then a
  /// `payout_batch.quoted` webhook). Send a [reference] to make it safe to
  /// retry: one used already returns that batch. [feePaidBy] is `merchant`
  /// or `recipient` (default: your payout settings'); [webhookUrl] (https)
  /// gets its events instead of your webhook's URL. [convert] is
  /// `same_network` (each payment from the wallet's own coin) or `convert`
  /// (every payment in another coin than [convertFrom], such as
  /// `USDT_TRC20`, paid from it, converted on its way); both default to
  /// your payout settings'.
  Future<PayoutBatch> create({
    required List<PayoutItemInput> items,
    String? reference,
    String? name,
    String? feePaidBy,
    String? webhookUrl,
    String? convert,
    String? convertFrom,
  }) async =>
      _batch(await _t.request('POST', '/v1/payout-batches', body: {
        if (reference != null) 'reference': reference,
        if (name != null) 'name': name,
        if (feePaidBy != null) 'fee_paid_by': feePaidBy,
        if (webhookUrl != null) 'webhook_url': webhookUrl,
        if (convert != null) 'convert': convert,
        if (convertFrom != null) 'convert_from': convertFrom,
        'items': [for (final i in items) i.toJson()],
      }));

  /// Batches of the key's mode, newest first.
  Future<PayoutBatchList> list(
          {String? status, int? limit, int? offset}) async =>
      PayoutBatchList(await _t.request(
          'GET', '/v1/payout-batches${_page(status, limit, offset)}'));

  Future<PayoutBatch> retrieve(String id) async =>
      _batch(await _t.request('GET', _path(id)));

  /// A batch's payments, in row order. [status] takes one status or
  /// several, comma-separated (`'sent,failed'`).
  Future<PayoutItemList> items(String id,
          {String? status, int? limit, int? offset}) async =>
      PayoutItemList(await _t.request(
          'GET', _path(id, '/items${_page(status, limit, offset)}')));

  /// Adds 1 to 1000 payments to a batch not submitted yet; the whole batch
  /// is checked and priced again.
  Future<PayoutBatch> addItems(String id, List<PayoutItemInput> items) async =>
      _batch(await _t.request('POST', _path(id, '/items'), body: {
        'items': [for (final i in items) i.toJson()]
      }));

  /// Prices a batch not submitted yet again, for another hour: when
  /// [submit] says its prices expired (409).
  Future<PayoutBatch> quote(String id) async =>
      _batch(await _t.request('POST', _path(id, '/quote')));

  /// Sends a quoted batch on: to its approvals, or to funding (it starts
  /// at once when the wallet covers it; otherwise [PayoutBatch.waiting]
  /// says what to send where).
  Future<PayoutBatch> submit(String id) async =>
      _batch(await _t.request('POST', _path(id, '/submit')));

  /// Cancels a batch before it is funded; once processing, the payments
  /// not sent yet.
  Future<PayoutBatch> cancel(String id) async =>
      _batch(await _t.request('POST', _path(id, '/cancel')));
}

/// Your payout wallets: one address per network (tron, bsc, …), made the
/// first time they are asked for.
class PayoutWallets {
  PayoutWallets._(this._t);

  final _Transport _t;

  static List<PayoutWallet> _wallets(Map<String, dynamic> json) =>
      _each(json['wallets'], PayoutWallet.new);

  /// Each wallet's address, and what it holds of each coin.
  Future<List<PayoutWallet>> list() async =>
      _wallets(await _t.request('GET', '/v1/payout-wallets'));

  /// Test keys only: adds [amount] (a String or a num) of [asset] to the
  /// test wallet's paper balance, and funds any test batch waiting for it.
  /// Returns the wallets.
  Future<List<PayoutWallet>> simulateTopUp(String asset, Object amount) async =>
      _wallets(await _t.request('POST',
          '/v1/payout-wallets/${Uri.encodeComponent(asset)}/simulate-top-up',
          body: {'amount': amount.toString()}));
}
