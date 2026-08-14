class GstService {
  double calculateTax({required double amount, required double taxRate}) {
    return (amount * taxRate) / 100;
  }

  Map<String, double> splitInvoice(double totalAmount, double taxRate) {
    final taxable = totalAmount / (1 + (taxRate / 100));
    final tax = totalAmount - taxable;
    return {'taxable': taxable, 'tax': tax};
  }
}
