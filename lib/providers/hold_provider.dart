import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/hold_model.dart';
import '../repositories/hold_repository.dart';

part 'hold_provider.g.dart';

@riverpod
class HoldNotifier extends _$HoldNotifier {
  final HoldRepository _repo = HoldRepository();

  @override
  Future<List<Hold>> build() async {
    // Not used directly – we use methods with userId parameter.
    return [];
  }

  Future<List<Hold>> getHoldsForUser(String userId) async {
    return await _repo.getAllByUser(userId);
  }

  Future<void> saveHold(String userId, String data, {String? note}) async {
    final hold = Hold.create(userId: userId, data: data, note: note);
    await _repo.insert(hold);
    ref.invalidateSelf();
  }

  Future<void> deleteHold(String id) async {
    await _repo.delete(id);
    ref.invalidateSelf();
  }

  Future<Hold?> getHold(String id) async {
    return await _repo.getById(id);
  }
}