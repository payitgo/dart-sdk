import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A webhook request whose signature or timestamp did not check out.
class SignatureVerificationException implements Exception {
  SignatureVerificationException(this.message);

  final String message;

  @override
  String toString() => 'SignatureVerificationException: $message';
}

/// A webhook event.
class WebhookEvent {
  WebhookEvent(this.raw);

  final Map<String, dynamic> raw;

  /// The event id: the same when the event is delivered again.
  String get id => raw['id'] as String;
  String get type => raw['type'] as String;
  bool get livemode => raw['livemode'] as bool? ?? false;
  DateTime get createdAt => DateTime.parse(raw['created_at'] as String);

  /// The payment (payment.* events), the settlement (settlement.*), the
  /// payout (payout.*), the payout batch (payout_batch.*: `PayoutBatch`),
  /// the payout batch's payment (payout_item.*: `PayoutItem`), the payout
  /// wallet's withdrawal (payout_wallet.withdrawn: `PayoutWithdrawal`), the
  /// payout schedule (payout_schedule.run: `PayoutSchedule`), the schedule
  /// and its shortfall (payout_schedule.funding_needed:
  /// `PayoutScheduleFunding`), or `{"message": "pong"}` (ping).
  Map<String, dynamic> get data => (raw['data'] as Map).cast<String, dynamic>();
}

class Webhook {
  static const defaultTolerance = Duration(minutes: 5);

  /// Verifies a webhook request and returns its event. Pass the raw request
  /// body (a String or bytes, before any JSON parsing), the
  /// X-Webhook-Signature header and the mode's signing secret (the webhook's
  /// `secret`, from `payitgo.webhooks.get()` or the dashboard). Throws
  /// [SignatureVerificationException] when the signature is wrong or the
  /// timestamp is older than [tolerance] (Duration.zero disables the check).
  static WebhookEvent constructEvent(
      Object payload, String? signatureHeader, String secret,
      {Duration tolerance = defaultTolerance}) {
    final body = payload is String
        ? utf8.encode(payload)
        : List<int>.from(payload as List<int>);
    final parts = <String, String>{};
    for (final part in (signatureHeader ?? '').split(',')) {
      final i = part.indexOf('=');
      if (i > 0) {
        parts[part.substring(0, i).trim()] = part.substring(i + 1).trim();
      }
    }
    final t = parts['t'] ?? '';
    final v1 = parts['v1'] ?? '';
    if (t.isEmpty || v1.isEmpty) {
      throw SignatureVerificationException(
          'missing or malformed X-Webhook-Signature header');
    }
    final expected = Hmac(sha256, utf8.encode(secret))
        .convert([...utf8.encode('$t.'), ...body]).toString();
    if (!_equal(expected, v1)) {
      throw SignatureVerificationException('signature does not match');
    }
    if (tolerance > Duration.zero) {
      final ts = int.tryParse(t);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (ts == null || (now - ts).abs() > tolerance.inSeconds) {
        throw SignatureVerificationException('timestamp outside the tolerance');
      }
    }
    return WebhookEvent(
        (jsonDecode(utf8.decode(body)) as Map).cast<String, dynamic>());
  }

  static bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
