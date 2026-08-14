import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../services/customer_reminder_service.dart';
import '../../../services/whatsapp_share_service.dart';

final _dateFormat = DateFormat('dd MMM yyyy');

class ServiceRemindersScreen extends ConsumerStatefulWidget {
  const ServiceRemindersScreen({super.key});

  @override
  ConsumerState<ServiceRemindersScreen> createState() => _ServiceRemindersScreenState();
}

class _ServiceRemindersScreenState extends ConsumerState<ServiceRemindersScreen> {
  late Future<List<CustomerReminderInfo>> _remindersFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _remindersFuture = CustomerReminderService().getCustomerReminders();
  }

  Future<void> _sendReminder(CustomerReminderInfo info) async {
    await WhatsAppShareService.sendReminder(
      customerName: info.name,
      phone: info.phone,
      topProducts: info.topProducts,
    );
  }

  Color _lapseColor(int days) {
    if (days >= 30) return Colors.red;
    if (days >= 15) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Service Reminders',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CustomerReminderInfo>>(
              future: _remindersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                var reminders = snapshot.data ?? [];
                if (_search.isNotEmpty) {
                  reminders = reminders
                      .where((r) =>
                          r.name.toLowerCase().contains(_search) || r.phone.contains(_search))
                      .toList();
                }
                if (reminders.isEmpty) {
                  return const Center(child: Text('No customer purchase history yet'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: reminders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) => _buildTile(reminders[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(CustomerReminderInfo info) {
    final color = _lapseColor(info.daysSinceLastPurchase);
    return ListTile(
      onTap: () => context.push('/customers/history?id=${info.customerId}'),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(Icons.person, color: color),
      ),
      title: Text(info.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${info.phone}  •  ${info.orderCount} orders'),
          const SizedBox(height: 2),
          Text('Last purchase: ${_dateFormat.format(info.lastPurchaseDate)}'),
          if (info.topProducts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: info.topProducts
                  .map((p) => Chip(
                        label: Text(p, style: const TextStyle(fontSize: 11)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${info.daysSinceLastPurchase}d ago',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(height: 6),
          IconButton(
            icon: const Icon(Icons.chat, color: Colors.green),
            tooltip: 'Send reminder on WhatsApp',
            onPressed: () => _sendReminder(info),
          ),
        ],
      ),
    );
  }
}
