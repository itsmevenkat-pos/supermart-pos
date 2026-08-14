import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../models/coupon_model.dart';

class CouponValidationResult {
  final bool isValid;
  final Coupon? coupon;
  final double discountAmount;
  final String? errorMessage;

  const CouponValidationResult._({
    required this.isValid,
    this.coupon,
    this.discountAmount = 0,
    this.errorMessage,
  });

  factory CouponValidationResult.valid(Coupon coupon, double discountAmount) =>
      CouponValidationResult._(isValid: true, coupon: coupon, discountAmount: discountAmount);

  factory CouponValidationResult.invalid(String message) =>
      CouponValidationResult._(isValid: false, errorMessage: message);
}

class CouponRepository {
  CouponRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Coupon>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query('coupons', orderBy: 'created_at DESC');
    return result.map((e) => Coupon.fromJson(e)).toList();
  }

  Future<Coupon?> getByCode(String code) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'coupons',
      where: 'code = ?',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return Coupon.fromJson(result.first);
  }

  Future<void> insert(Coupon coupon) async {
    final db = await _dbHelper.database;
    await db.insert('coupons', coupon.toJson());
  }

  Future<void> update(Coupon coupon) async {
    final db = await _dbHelper.database;
    await db.update('coupons', coupon.toJson(), where: 'id = ?', whereArgs: [coupon.id]);
  }

  Future<void> setActive(String id, bool isActive) async {
    final db = await _dbHelper.database;
    await db.update('coupons', {'is_active': isActive ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('coupons', where: 'id = ?', whereArgs: [id]);
  }

  /// Checks a code against every rule (exists, active, date range, usage
  /// cap, minimum bill) and returns the ₹ discount it computes to against
  /// [billAmount] — everything a "Apply Coupon" UI needs in one call rather
  /// than re-deriving the same checks at the call site.
  Future<CouponValidationResult> validate({required String code, required double billAmount}) async {
    final coupon = await getByCode(code);
    if (coupon == null) return CouponValidationResult.invalid('No coupon found for "$code"');
    if (!coupon.isActive) return CouponValidationResult.invalid('This coupon is no longer active');

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (coupon.startDate != null && now < coupon.startDate!) {
      return CouponValidationResult.invalid('This coupon isn\'t active yet');
    }
    if (coupon.endDate != null && now > coupon.endDate!) {
      return CouponValidationResult.invalid('This coupon has expired');
    }
    if (coupon.maxUses != null && coupon.timesUsed >= coupon.maxUses!) {
      return CouponValidationResult.invalid('This coupon has already reached its usage limit');
    }
    if (billAmount < coupon.minBillAmount) {
      return CouponValidationResult.invalid(
        'Bill must be at least ₹${coupon.minBillAmount.toStringAsFixed(2)} to use this coupon',
      );
    }

    final discount = coupon.type == CouponType.percentage
        ? (billAmount * coupon.value / 100).clamp(0, billAmount).toDouble()
        : coupon.value.clamp(0, billAmount).toDouble();

    return CouponValidationResult.valid(coupon, discount);
  }

  /// Called once a sale that used this coupon actually completes — not at
  /// validation time, so a coupon that's checked but the sale is then
  /// abandoned/cancelled before checkout doesn't burn a use.
  Future<void> recordUsage(String couponId) async {
    final db = await _dbHelper.database;
    await db.rawUpdate('UPDATE coupons SET times_used = times_used + 1 WHERE id = ?', [couponId]);
  }
}

final couponRepositoryProvider = Provider<CouponRepository>((ref) {
  return CouponRepository();
});
