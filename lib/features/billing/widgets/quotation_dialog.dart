import 'package:flutter/material.dart';

class QuotationDialog extends StatefulWidget {
  final double subtotal;
  final double totalTax;
  final double discountTotal;
  final String? discountReason;
  final double grandTotal;
  final List<Map<String, dynamic>> cartItems;

  const QuotationDialog({
    super.key,
    required this.subtotal,
    required this.totalTax,
    required this.discountTotal,
    this.discountReason,
    required this.grandTotal,
    required this.cartItems,
  });

  @override
  State<QuotationDialog> createState() => _QuotationDialogState();
}

class _QuotationDialogState extends State<QuotationDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate Quotation'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Customer Name *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _expiryController,
              decoration: const InputDecoration(labelText: 'Expiry Date (YYYY-MM-DD)'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Items:'),
                      Text('${widget.cartItems.length}'),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal:'),
                      Text('₹${widget.subtotal.toStringAsFixed(2)}'),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tax:'),
                      Text('₹${widget.totalTax.toStringAsFixed(2)}'),
                    ],
                  ),
                  if (widget.discountTotal > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Discount:'),
                        Text(' -₹${widget.discountTotal.toStringAsFixed(2)}'),
                      ],
                    ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '₹${widget.grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (_nameController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter customer name'), backgroundColor: Colors.red),
              );
              return;
            }
            Navigator.pop(context, {
              'customerName': _nameController.text.trim(),
              'customerPhone': _phoneController.text.trim(),
              'customerEmail': _emailController.text.trim(),
              'notes': _notesController.text.trim(),
              'expiryDate': _expiryController.text.trim(),
            });
          },
          icon: const Icon(Icons.description),
          label: const Text('Generate'),
        ),
      ],
    );
  }
}
