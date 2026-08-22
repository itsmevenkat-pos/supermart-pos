import '../models/session_model.dart';
import '../repositories/session_repository.dart';
import '../repositories/cash_movement_repository.dart';

class CounterService {
  final SessionRepository _sessionRepo = SessionRepository();
  final CashMovementRepository _cashMovements = CashMovementRepository();

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

    // Every movement of notes in this shift, not just the selling. This used
    // to be `SaleRepository.getCashTotalBySession`, which counts only the
    // `sale` rows of the cash book — so the figure *persisted* on the closed
    // shift (and the shortage/overage computed from it, and the day-end
    // report printed off it) stayed blind to khata collections and cash
    // refunds even after the close screen started showing the right number.
    // Expected cash has exactly one definition: opening cash plus the net of
    // the cash movement ledger. See `MigrationV34`.
    final netCashMovements = await _cashMovements.getSessionNet(sessionId);
    final expectedCash = session.openingCash + netCashMovements;
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
