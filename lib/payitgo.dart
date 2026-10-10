/// Dart client for the payitgo crypto payment gateway.
///
/// On your server, with your secret key:
///
/// ```dart
/// final payitgo = Payitgo(Platform.environment['PAYITGO_KEY']!, baseUrl: 'https://api.example.com');
/// final payment = await payitgo.payments.create(orderId: 'ORD-1001', amountUsd: 10, token: 'USDT_TRC20');
/// // send the customer to payment.checkoutUrl; fulfil on the payment.confirmed webhook
/// ```
///
/// In a Flutter app, never with a secret key: [PayitgoCheckout] shows a payment
/// your backend created, from its checkout token.
library;

export 'src/client.dart';
export 'src/webhook.dart';
