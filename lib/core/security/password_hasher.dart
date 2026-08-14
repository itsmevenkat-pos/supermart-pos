import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Salted, iterated password hashing (PBKDF2-HMAC-SHA256).
///
/// Stored format: `iterations:base64(salt):base64(hash)`
/// e.g. `100000:qk3f...==:h8sD...==`
///
/// This is deliberately dependency-light (no native bcrypt binding needed —
/// `crypto` is pure Dart and works identically on every platform this app
/// targets). 100,000 iterations costs roughly 50-100ms per hash/verify on
/// desktop hardware, which is an acceptable login-time cost while making
/// brute-force attempts on a stolen database expensive.
class PasswordHasher {
  static const int _iterations = 100000;
  static const int _saltLength = 16;
  static const int _keyLength = 32;

  /// Hash a plaintext password into the stored format above.
  static String hash(String password) {
    final salt = _generateSalt();
    final derived = _pbkdf2(password, salt, _iterations, _keyLength);
    return '$_iterations:${base64Encode(salt)}:${base64Encode(derived)}';
  }

  /// Verify a plaintext password against a previously stored hash.
  /// Returns false (never throws) for malformed/corrupt stored values.
  static bool verify(String password, String stored) {
    try {
      final parts = stored.split(':');
      if (parts.length != 3) return false;
      final iterations = int.parse(parts[0]);
      final salt = base64Decode(parts[1]);
      final expected = base64Decode(parts[2]);
      final actual = _pbkdf2(password, salt, iterations, expected.length);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  /// True if [stored] looks like our hash format, as opposed to a legacy
  /// plaintext value from before hashing was introduced.
  static bool isHashed(String stored) => stored.split(':').length == 3;

  static Uint8List _generateSalt() {
    final rand = Random.secure();
    return Uint8List.fromList(List<int>.generate(_saltLength, (_) => rand.nextInt(256)));
  }

  static Uint8List _pbkdf2(String password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final blockCount = (keyLength / 32).ceil();
    final output = BytesBuilder();

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      var u = hmac.convert([...salt, ..._intToBytes(blockIndex)]).bytes;
      final block = Uint8List.fromList(u);
      for (var iter = 1; iter < iterations; iter++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < block.length; k++) {
          block[k] ^= u[k];
        }
      }
      output.add(block);
    }

    return Uint8List.fromList(output.toBytes().sublist(0, keyLength));
  }

  static Uint8List _intToBytes(int i) {
    return Uint8List(4)..buffer.asByteData().setUint32(0, i, Endian.big);
  }

  /// Constant-time comparison to avoid leaking hash-match info via timing.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}