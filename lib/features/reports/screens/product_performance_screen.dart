import 'package:flutter/material.dart';

import '../../../services/advanced_report_service.dart';
import 'generic_report_screen.dart';

String _qty(dynamic v) => ((v as num?)?.toDouble() ?? 0).toStringAsFixed(2);
String _money(dynamic v) => '₹${((v as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';

class ProductPerformanceScreen extends StatelessWidget {
  const ProductPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GenericReportScreen(
      title: 'Top Selling Products',
      fetch: (from, to) => AdvancedReportService().getTopSellingProducts(from: from, to: to),
      columns: const [
        ReportColumn(key: 'name', label: 'Item'),
        ReportColumn(key: 'barcode', label: 'Barcode'),
        ReportColumn(key: 'quantity', label: 'Quantity Sold', formatter: _qty),
        ReportColumn(key: 'revenue', label: 'Revenue', formatter: _money),
      ],
    );
  }
}
