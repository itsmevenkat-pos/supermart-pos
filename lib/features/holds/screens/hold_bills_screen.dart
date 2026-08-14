import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../providers/hold_provider.dart';
import '../../../providers/auth_provider.dart';

class HoldBillsScreen extends ConsumerStatefulWidget {
  const HoldBillsScreen({super.key});

  @override
  ConsumerState<HoldBillsScreen> createState() => _HoldBillsScreenState();
}

class _HoldBillsScreenState extends ConsumerState<HoldBillsScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view holds')),
      );
    }

    final future = ref.watch(holdNotifierProvider.notifier).getHoldsForUser(user.id);

    return AppScaffold(
      title: 'Held Bills',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(holdNotifierProvider),
        ),
      ],
      body: FutureBuilder(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final holds = snapshot.data ?? [];
          if (holds.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No held bills'),
                  SizedBox(height: 8),
                  Text('Hold a bill from the billing screen', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: holds.length,
            itemBuilder: (_, index) {
              final hold = holds[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: Text('Held Bill #${hold.id.substring(0, 8)}'),
                  subtitle: Text(
                    DateTime.fromMillisecondsSinceEpoch(hold.createdAt * 1000).toLocal().toString().split(' ')[0],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.green),
                        onPressed: () {
                          // Resume bill: pass data back to billing screen
                          Navigator.pop(context, hold.data);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await ref.read(holdNotifierProvider.notifier).deleteHold(hold.id);
                          setState(() {});
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