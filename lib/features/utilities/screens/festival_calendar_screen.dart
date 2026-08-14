import 'package:flutter/material.dart';

import '../../../core/widgets/app_scaffold.dart';
import '../../../models/festival_model.dart';
import '../../../repositories/festival_repository.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Editable list of recurring festival dates (month + day, no year) that the
/// AI Analysis screen's festival-stock-suggestion report compares against
/// last year's sales. See FestivalRepository for how "next occurrence" is
/// computed and why lunar-calendar festivals need yearly correction here.
class FestivalCalendarScreen extends StatefulWidget {
  const FestivalCalendarScreen({super.key});

  @override
  State<FestivalCalendarScreen> createState() => _FestivalCalendarScreenState();
}

class _FestivalCalendarScreenState extends State<FestivalCalendarScreen> {
  final _repo = FestivalRepository();
  late Future<List<Festival>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _repo.getAll();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _openForm({Festival? existing}) async {
    final result = await showDialog<Festival>(
      context: context,
      builder: (_) => _FestivalFormDialog(existing: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await _repo.insert(result);
    } else {
      await _repo.update(result);
    }
    if (mounted) await _refresh();
  }

  Future<void> _delete(Festival festival) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Festival?'),
        content: Text('Remove "${festival.name}" from the calendar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.delete(festival.id);
    if (mounted) await _refresh();
  }

  Future<void> _toggleActive(Festival festival) async {
    await _repo.update(festival.copyWith(isActive: !festival.isActive));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Festival Calendar',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Festival>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final festivals = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Used by AI Analysis → Festival Stock Suggestions to compare against last '
                    'year\'s sales. Lunar-calendar festivals (Diwali, Navaratri, Vinayagar '
                    'Chaturthi) shift every year — check and correct their dates below each year.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                if (festivals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No festivals yet — tap + to add one.')),
                  )
                else
                  ...festivals.map((f) => ListTile(
                        title: Text(
                          f.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: f.isActive ? null : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          '${_monthNames[f.month - 1]} ${f.day}'
                          '${f.notes != null && f.notes!.isNotEmpty ? '\n${f.notes}' : ''}',
                        ),
                        isThreeLine: f.notes != null && f.notes!.isNotEmpty,
                        leading: Switch(value: f.isActive, onChanged: (_) => _toggleActive(f)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _openForm(existing: f)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _delete(f),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FestivalFormDialog extends StatefulWidget {
  final Festival? existing;

  const _FestivalFormDialog({this.existing});

  @override
  State<_FestivalFormDialog> createState() => _FestivalFormDialogState();
}

class _FestivalFormDialogState extends State<_FestivalFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late int _month;
  late int _day;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _month = existing?.month ?? 1;
    _day = existing?.day ?? 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _daysInMonth => DateTime(2027, _month + 1, 0).day;

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final festival = widget.existing?.copyWith(
          name: name,
          month: _month,
          day: _day,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        ) ??
        Festival.create(
          name: name,
          month: _month,
          day: _day,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        );
    Navigator.pop(context, festival);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Festival' : 'Edit Festival'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Festival Name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    decoration: const InputDecoration(labelText: 'Month'),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text(_monthNames[m - 1])),
                    ],
                    onChanged: (v) => setState(() {
                      _month = v!;
                      if (_day > _daysInMonth) _day = _daysInMonth;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _day,
                    decoration: const InputDecoration(labelText: 'Day'),
                    items: [
                      for (var d = 1; d <= _daysInMonth; d++) DropdownMenuItem(value: d, child: Text('$d')),
                    ],
                    onChanged: (v) => setState(() => _day = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. lunar calendar — verify each year',
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
