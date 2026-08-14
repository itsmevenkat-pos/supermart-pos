import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyEvent, KeyDownEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/customer_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/customer_provider.dart';
import '../../customers/screens/customer_form_screen.dart';

/// Search-and-select dialog for choosing (or clearing, or creating) the
/// billing customer. Opened from the "Customer" button on the billing screen.
class CustomerPickerDialog extends ConsumerStatefulWidget {
  const CustomerPickerDialog({super.key});

  @override
  ConsumerState<CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends ConsumerState<CustomerPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  // Kept in sync with whatever the provider last resolved to, so the
  // keyboard handler (which runs synchronously on keypress) has something
  // to navigate without needing to await the async provider itself.
  List<Customer> _currentResults = [];
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    // Start from the full customer list every time the dialog opens.
    Future.microtask(() => ref.invalidate(customerNotifierProvider));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(Customer? customer) {
    ref.read(cartProvider.notifier).setCustomer(customer);
    Navigator.pop(context);
  }

  void _addNewCustomer() {
    showDialog(
      context: context,
      builder: (_) => CustomerFormScreen(
        onSaved: (customer) {
          ref.read(cartProvider.notifier).setCustomer(customer);
        },
      ),
    ).then((_) {
      // CustomerFormScreen pops itself after saving; close this picker too
      // so the person lands back on billing with the new customer selected.
      if (context.mounted) Navigator.pop(context);
    });
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_currentResults.isNotEmpty) {
        setState(() => _highlightedIndex = (_highlightedIndex + 1) % _currentResults.length);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_currentResults.isNotEmpty) {
        setState(() => _highlightedIndex =
            (_highlightedIndex - 1 + _currentResults.length) % _currentResults.length);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_currentResults.isNotEmpty) {
        final index = _highlightedIndex >= 0 ? _highlightedIndex : 0;
        _select(_currentResults[index]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerNotifierProvider);

    return Dialog(
      child: SizedBox(
        width: 420,
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Select Customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Focus(
                onKeyEvent: _handleSearchKeyEvent,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search by name or phone — ↓ to pick, Enter to select',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() => _highlightedIndex = -1);
                    if (value.trim().isNotEmpty) {
                      ref.read(customerNotifierProvider.notifier).search(value.trim());
                    } else {
                      ref.invalidate(customerNotifierProvider);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Continue without a customer'),
              onTap: () => _select(null),
            ),
            const Divider(height: 1),
            Expanded(
              child: customersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
                data: (customers) {
                  // Plain field write (no setState) — just keeps the
                  // keyboard handler's view of the list current.
                  _currentResults = customers;

                  if (customers.isEmpty) {
                    return const Center(child: Text('No customers found'));
                  }
                  return ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (_, index) {
                      final c = customers[index];
                      final isHighlighted = index == _highlightedIndex;
                      return Container(
                        color: isHighlighted ? Colors.green.withValues(alpha: 0.15) : null,
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person, size: 18)),
                          title: Text(c.name),
                          subtitle: Text(
                            c.loyaltyPoints > 0 ? '${c.phone}  •  ${c.loyaltyPoints} pts' : c.phone,
                          ),
                          trailing: c.outstandingBalance > 0
                              ? Text(
                                  '₹${c.outstandingBalance.toStringAsFixed(0)} due',
                                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                                )
                              : null,
                          onTap: () => _select(c),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addNewCustomer,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add New Customer'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}