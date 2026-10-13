enum PaymentMethod { zarinpal, paypal, bitcoin, zibal }

PaymentMethod toPaymentMethod(String str) {
  switch (str) {
    case 'zarinpal':
      return PaymentMethod.zarinpal;
    case 'paypal':
      return PaymentMethod.paypal;
    case 'bitcoin':
      return PaymentMethod.bitcoin;
    case 'zibal':
      return PaymentMethod.zibal;
    default:
      throw Exception('Invalid PaymentMethod provided');
  }
}
