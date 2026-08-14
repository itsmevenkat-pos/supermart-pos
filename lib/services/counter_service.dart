import '../models/session_model.dart';
import '../repositories/session_repository.dart';
import '../repositories/sale_repository.dart';

class CounterService {
  final SessionRepository _sessionRepo = SessionRepository();
  final SaleRepository _saleRepo = SaleRepository();

  Future<Session> openShift({
    required String userId,
    double openingCash = 0,
    Map<String, int>? denominations,
    String? notes,
  }) async {
    final active = await _sessionRepo.getActiveSession(userId);
    if (active != null) {
      throw Exception('You already have an open shift.');
    }
    final session = Session.open(
      userId: userId,
      openingCash: openingCash,
      openingDenominations: denominations,
      notes: notes,
    );
    await _sessionRepo.insert(session);
    return session;
  }

  Future<Session> closeShift({
    required String sessionId,
    required double closingCash,
    required Map<String, int>? denominations,
    String? notes,
  }) async {
    final session = await _sessionRepo.getById(sessionId);
    if (session == null) throw Exception('Session not found');
    if (session.status != 'open') throw Exception('Shift is already closed');

    final cashSales = await _saleRepo.getCashTotalBySession(sessionId);
    final expectedCash = session.openingCash + cashSales;
    final difference = closingCash - expectedCash;

    final updated = session.copyWith(
      closingTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      closingCash: closingCash,
      closingDenominations: denominations,
      expectedCash: expectedCash,
      difference: difference,
      status: 'closed',
      notes: notes,
    );
    await _sessionRepo.update(updated);
    return updated;
  }

  Future<Session?> getActiveSession(String userId) async {
    return await _sessionRepo.getActiveSession(userId);
  }
}
