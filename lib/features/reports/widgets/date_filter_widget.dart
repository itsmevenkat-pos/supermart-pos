import 'package:flutter/material.dart';

class DateFilterWidget extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  final Function(DateTime?, DateTime?) onFilterApplied;
  final VoidCallback onFilterCleared;

  const DateFilterWidget({
    super.key,
    this.fromDate,
    this.toDate,
    required this.onFilterApplied,
    required this.onFilterCleared,
  });

  @override
  State<DateFilterWidget> createState() => _DateFilterWidgetState();
}

class _DateFilterWidgetState extends State<DateFilterWidget> {
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _fromDate = widget.fromDate;
    _toDate = widget.toDate;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_list),
      tooltip: 'Filter by Date',
      onSelected: (value) {
        if (value == 'clear') {
          setState(() {
            _fromDate = null;
            _toDate = null;
          });
          widget.onFilterCleared();
        } else {
          _showDatePickerDialog(context);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'filter',
          child: Row(
            children: [
              Icon(Icons.date_range),
              SizedBox(width: 8),
              Text('Select Date Range'),
            ],
          ),
        ),
        if (_fromDate != null)
          const PopupMenuItem(
            value: 'clear',
            child: Row(
              children: [
                Icon(Icons.clear),
                SizedBox(width: 8),
                Text('Clear Filter'),
              ],
            ),
          ),
      ],
    );
  }

  void _showDatePickerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Filter by Date Range'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Start Date'),
              subtitle: Text(_fromDate != null
                  ? _fromDate!.toLocal().toString().split(' ')[0]
                  : 'Select'),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _fromDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _fromDate = date);
                }
              },
            ),
            ListTile(
              title: const Text('End Date'),
              subtitle: Text(_toDate != null
                  ? _toDate!.toLocal().toString().split(' ')[0]
                  : 'Select'),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _toDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _toDate = date);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onFilterApplied(_fromDate, _toDate);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}