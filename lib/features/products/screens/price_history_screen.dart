import 'package:flutter/material.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/price_history_model.dart';
import '../../../models/user_model.dart';
import '../../../repositories/price_history_repository.dart';
import '../../../repositories/user_repository.dart';

const Map<String, String> _fieldLabels = {
  'retail_price': 'Retail Price',
  'mrp': 'MRP',
  'cost_price': 'Cost Price',
  'wholesale_price': 'Wholesale Price',
};

String _labelFor(String field) => _fieldLabels[field] ?? field;

/// Read-only audit trail of price edits for one product — see
/// `PriceHistoryRepository` / MigrationV24. Reached from
/// `product_form_screen.dart` only while editing an existing product.
class PriceHistoryScreen extends StatefulWidget {
  final String productId;
  final String productName;

  const PriceHistoryScreen({super.key, required this.productId, required this.productName});

  @override
  State<PriceHistoryScreen> createState() => _PriceHistoryScreenState();
}

class _PriceHistoryScreenState extends State<PriceHistoryScreen> {
  late final Future<List<PriceHistoryEntry>> _historyFuture;
  final Map<String, User?> _userCache = {};

  @override
  void initState() {
    super.initState();
    _historyFuture = PriceHistoryRepository().getHistory(widget.productId);
  }

  Future<User?> _resolveUser(String? userId) async {
    if (userId == null) return null;
    if (_userCache.containsKey(userId)) return _userCache[userId];
    final user = await UserRepository().getById(userId);
    _userCache[userId] = user;
    return user;
  }

  String _formatDate(int changedAtSeconds) {
    return DateTime.fromMillisecondsSinceEpoch(changedAtSeconds * 1000).toLocal().toString().split(' ')[0];
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Price History — ${widget.productName}',
      body: FutureBuilder<List<PriceHistoryEntry>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Text('No price changes recorded yet.', style: TextStyle(color: Colors.grey)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                child: ListTile(
                  title: Text(_labelFor(entry.field), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.oldValue != null ? '₹${entry.oldValue!.toStringAsFixed(2)}' : '-'} '
                        '→ ₹${entry.newValue.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 4),
                      FutureBuilder<User?>(
                        future: _resolveUser(entry.changedByUserId),
                        builder: (context, userSnapshot) {
                          final name = userSnapshot.data?.name ?? 'Unknown';
                          return Text(
                            'By $name on ${_formatDate(entry.changedAt)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
