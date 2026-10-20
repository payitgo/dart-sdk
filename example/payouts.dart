// Pays a client from your payout wallet, in test mode, on your server:
//
//   1. tops up the test payout wallet on paper (no coins);
//   2. sends a client's payout request as it comes in, and shows its fee;
//   3. looks at the open list and what sending it needs of the wallet;
//   4. sends the list as a batch, and follows the payment until it is sent.
//
// Run it with a test key that has payouts turned on (in the dashboard's API
// keys):
//
//   PAYITGO_KEY=<test key> dart run example/payouts.dart
import 'dart:io';

import 'package:payitgo/payitgo.dart';

Future<void> main() async {
  final env = Platform.environment;
  final payitgo = Payitgo(
    env['PAYITGO_KEY'] ?? '',
    baseUrl: env['PAYITGO_BASE_URL'], // the API's default when unset
  );
  try {
    if (await payitgo.isLive()) {
      stderr.writeln('use a test key: this example tops up on paper');
      exitCode = 1;
      return;
    }

    // 1. Top up the test wallet: 1000 USDT on Tron, on paper.
    await payitgo.payoutWallets.simulateTopUp('USDT_TRC20', '1000');

    // 2. A client asks for a withdrawal. Your own id for it is the
    //    reference: sending it again returns the same payment, so a
    //    timeout never pays twice.
    final request = await payitgo.payouts.request(
      reference: 'wd-${DateTime.now().millisecondsSinceEpoch}',
      asset: 'USDT_TRC20',
      address: 'TR7mNkucnhLZoJQLLJ6DR88jpLQufWxUJi',
      amount: '25',
      name: 'Ana Silva',
    );
    if (request.status == 'invalid') {
      for (final e in request.errors) {
        print('refused: ${e.code}: ${e.message}');
      }
      return;
    }
    print('request ${request.id}: ${request.amount} ${request.ticker}, '
        'fee ${request.fee}, the wallet gives ${request.debit}');

    // 3. The open list, and what sending it takes of each coin.
    final inbox = await payitgo.payouts.inbox();
    for (final c in inbox.coverage) {
      print('${c.asset}: needs ${c.needed}, the wallet can spend '
          '${c.spendable}, top up ${c.topUp}');
    }

    // 4. Send every valid request as a batch. Without approvals in your
    //    payout settings it is funded at once and sent within seconds.
    final batch = await payitgo.payouts.send();
    print('batch ${batch.id}: ${batch.status}');
    for (final s in batch.waiting?.shortfall ?? const <PayoutShortfall>[]) {
      print('send ${s.amount} ${s.asset} to ${s.address} first');
    }

    // In production, follow the payout_item.sent webhook instead.
    for (var i = 0; i < 20; i++) {
      final item = await payitgo.payouts.retrieve(request.id!);
      if (item.status == 'sent' || item.status == 'failed') {
        print('${item.status}: ${item.txId ?? item.failReason}');
        break;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  } on PayitgoException catch (e) {
    stderr.writeln('payitgo refused: $e');
    exitCode = 1;
  } finally {
    payitgo.close();
  }
}
