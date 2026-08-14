import 'package:flutter/material.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../models/customer_model.dart';
import '../../../repositories/customer_repository.dart';
import '../../../services/whatsapp_share_service.dart';

enum _Filter { all, hasDues, gold, silver, bronze, birthdayThisMonth }

enum _Template { offer, duesReminder, birthdayWish, custom }

/// Filtered customer list + templated WhatsApp message, one contact at a
/// time — mirrors `service_reminders_screen.dart`'s honest architecture
/// (this app has no WhatsApp Business API / SMS gateway, so "campaign"
/// means fast targeting + a prefilled message, not automated bulk send).
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  late Future<List<Customer>> _customersFuture;
  String _search = '';
  _Filter _filter = _Filter.all;
  _Template _template = _Template.offer;
  final _customTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _customersFuture = CustomerRepository().getAll();
  }

  @override
  void dispose() {
    _customTextController.dispose();
    super.dispose();
  }

  bool _matchesFilter(Customer c) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.hasDues:
        return c.outstandingBalance > 0;
      case _Filter.gold:
        return c.effectiveRating == CustomerRating.gold;
      case _Filter.silver:
        return c.effectiveRating == CustomerRating.silver;
      case _Filter.bronze:
        return c.effectiveRating == CustomerRating.bronze;
      case _Filter.birthdayThisMonth:
        if (c.dateOfBirth == null) return false;
        final dob = DateTime.fromMillisecondsSinceEpoch(c.dateOfBirth! * 1000);
        return dob.month == DateTime.now().month;
    }
  }

  String _messageFor(Customer c) {
    switch (_template) {
      case _Template.offer:
        return 'Hi ${c.name}! 🎉 Special offer just for you at SuperMart POS this week — visit us and save on your favorites!';
      case _Template.duesReminder:
        return 'Hi ${c.name}, a gentle reminder that ₹${c.outstandingBalance.toStringAsFixed(2)} is due on your account at SuperMart POS. Thank you!';
      case _Template.birthdayWish:
        return 'Happy Birthday ${c.name}! 🎂 Wishing you a wonderful day from all of us at SuperMart POS.';
      case _Template.custom:
        return _customTextController.text.trim().isEmpty
            ? 'Hi ${c.name}!'
            : '${c.name.isNotEmpty ? "Hi ${c.name}, " : ""}${_customTextController.text.trim()}';
    }
  }

  Future<void> _send(Customer c) async {
    await WhatsAppShareService.sendCampaignMessage(phone: c.phone, message: _messageFor(c));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Campaigns',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() => _customersFuture = CustomerRepository().getAll()),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == _Filter.all,
                  onSelected: (_) => setState(() => _filter = _Filter.all),
                ),
                ChoiceChip(
                  label: const Text('Has Dues'),
                  selected: _filter == _Filter.hasDues,
                  onSelected: (_) => setState(() => _filter = _Filter.hasDues),
                ),
                ChoiceChip(
                  label: const Text('Gold'),
                  selected: _filter == _Filter.gold,
                  onSelected: (_) => setState(() => _filter = _Filter.gold),
                ),
                ChoiceChip(
                  label: const Text('Silver'),
                  selected: _filter == _Filter.silver,
                  onSelected: (_) => setState(() => _filter = _Filter.silver),
                ),
                ChoiceChip(
                  label: const Text('Bronze'),
                  selected: _filter == _Filter.bronze,
                  onSelected: (_) => setState(() => _filter = _Filter.bronze),
                ),
                ChoiceChip(
                  label: const Text('Birthday This Month'),
                  selected: _filter == _Filter.birthdayThisMonth,
                  onSelected: (_) => setState(() => _filter = _Filter.birthdayThisMonth),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                const Text('Message:'),
                const SizedBox(width: 12),
                DropdownButton<_Template>(
                  value: _template,
                  items: const [
                    DropdownMenuItem(value: _Template.offer, child: Text('Offer')),
                    DropdownMenuItem(value: _Template.duesReminder, child: Text('Dues Reminder')),
                    DropdownMenuItem(value: _Template.birthdayWish, child: Text('Birthday Wish')),
                    DropdownMenuItem(value: _Template.custom, child: Text('Custom')),
                  ],
                  onChanged: (v) => setState(() => _template = v ?? _Template.offer),
                ),
              ],
            ),
          ),
          if (_template == _Template.custom)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: TextField(
                controller: _customTextController,
                decoration: const InputDecoration(
                  hintText: 'Custom message text',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            child: FutureBuilder<List<Customer>>(
              future: _customersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                var customers = (snapshot.data ?? []).where(_matchesFilter).toList();
                if (_search.isNotEmpty) {
                  customers = customers
                      .where((c) => c.name.toLowerCase().contains(_search) || c.phone.contains(_search))
                      .toList();
                }
                if (customers.isEmpty) {
                  return const Center(child: Text('No customers match this filter'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final c = customers[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c.name),
                      subtitle: Text(c.phone),
                      trailing: IconButton(
                        icon: const Icon(Icons.chat, color: Colors.green),
                        tooltip: 'Send on WhatsApp',
                        onPressed: () => _send(c),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
