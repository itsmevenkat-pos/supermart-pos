import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/bank_account_model.dart';
import '../../../models/chart_of_account_model.dart';
import '../../../repositories/bank_reconciliation_repository.dart';
import '../../../repositories/gl_repository.dart';

/// The bank accounts this shop reconciles. Tapping one opens its
/// reconciliation view.
class BankAccountListScreen extends ConsumerStatefulWidget {
  const BankAccountListScreen({super.key});

  @override
  ConsumerState<BankAccountListScreen> createState() => _BankAccountListScreenState();
}

class _BankAccountListScreenState extends ConsumerState<BankAccountListScreen> {
  final _repo = BankReconciliationRepository();
  final _glRepo = GLRepository();
  late Future<List<BankAccount>> _accountsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _accountsFuture = _repo.getAllAccounts();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _accountsFuture;
  }

  Future<void> _createAccount() async {
    // Only asset accounts can sensibly back a bank account, so the picker is
    // narrowed rather than offering the whole chart and relying on the user
    // to know that revenue accounts are the wrong answer.
    final assetAccounts = await _glRepo.getAllAccounts(type: AccountType.asset, isActive: true);
    if (!mounted) return;

    final created = await showDialog<BankAccount>(
      context: context,
      builder: (_) => _BankAccountDialog(assetAccounts: assetAccounts),
    );
    if (created == null) return;

    await _repo.createAccount(created);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Bank Accounts',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(_load)),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: _createAccount,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<BankAccount>>(
        future: _accountsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final accounts = snapshot.data ?? [];
          if (accounts.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'No bank accounts yet. Add one and link it to a ledger account '
                        '(usually 1010 Bank) to start importing statements and reconciling '
                        'them against the General Ledger.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final reconciledThrough = account.reconciledUpToDate;
                return ListTile(
                  leading: Icon(
                    Icons.account_balance,
                    color: account.isActive ? null : Theme.of(context).disabledColor,
                  ),
                  title: Text('${account.bankName} · ${account.maskedNumber}'),
                  subtitle: Text(
                    [
                      account.accountHolder,
                      if (account.glAccountId == null)
                        'Not linked to a ledger account — cannot reconcile'
                      else if (reconciledThrough == null)
                        'Never reconciled'
                      else
                        'Reconciled through ${_formatDate(reconciledThrough)}',
                      if (!account.isActive) 'Inactive',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await context.push('/banking/reconcile', extra: account.id);
                    if (mounted) await _refresh();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class _BankAccountDialog extends StatefulWidget {
  const _BankAccountDialog({required this.assetAccounts});

  final List<ChartOfAccount> assetAccounts;

  @override
  State<_BankAccountDialog> createState() => _BankAccountDialogState();
}

class _BankAccountDialogState extends State<_BankAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _holderController = TextEditingController();
  final _bankController = TextEditingController();
  final _openingController = TextEditingController(text: '0');
  String? _glAccountId;

  @override
  void initState() {
    super.initState();
    // Default to 1010 Bank when it is there — it is the right answer for
    // virtually every shop, and Phase 1 seeds it.
    for (final account in widget.assetAccounts) {
      if (account.code == '1010') {
        _glAccountId = account.id;
        break;
      }
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    _holderController.dispose();
    _bankController.dispose();
    _openingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Bank Account'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _bankController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Bank Name', hintText: 'e.g. State Bank of India'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _numberController,
                decoration: const InputDecoration(labelText: 'Account Number'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _holderController,
                decoration: const InputDecoration(labelText: 'Account Holder'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _openingController,
                decoration: const InputDecoration(labelText: 'Opening Balance', prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: (v) => double.tryParse((v ?? '').trim()) == null ? 'Enter a number' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _glAccountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ledger Account'),
                items: widget.assetAccounts
                    .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.code} — ${a.name}')))
                    .toList(),
                onChanged: (value) => setState(() => _glAccountId = value),
                validator: (v) => v == null ? 'Pick the ledger account to reconcile against' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              BankAccount.create(
                accountNumber: _numberController.text.trim(),
                accountHolder: _holderController.text.trim(),
                bankName: _bankController.text.trim(),
                openingBalance: double.parse(_openingController.text.trim()),
                glAccountId: _glAccountId,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
