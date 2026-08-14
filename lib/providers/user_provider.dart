import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';

/// Plain FutureProvider (no build_runner codegen needed) backing the Users
/// screen. Refresh with `ref.invalidate(userListProvider)` after any
/// add/update, same pattern customer_list_screen.dart uses for customers.
final userListProvider = FutureProvider<List<User>>((ref) async {
  return UserRepository().getAll();
});
