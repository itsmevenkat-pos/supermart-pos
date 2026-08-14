import '../core/security/password_hasher.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';

class AuthService {
  AuthService({UserRepository? userRepo}) : _userRepo = userRepo ?? UserRepository();

  final UserRepository _userRepo;

  Future<User?> login(String username, String password) async {
    // No blanket try/catch here anymore: if `ensureAdminExists` or the
    // lookup throws (a DB init/migration problem, for example), that
    // exception now propagates up to AuthNotifier, which shows the real
    // message instead of the generic "Invalid username or password" that
    // used to hide it — that message is now reserved for an actual
    // wrong username/password.
    await _userRepo.ensureAdminExists();
    final user = await _userRepo.getByUsername(username.trim());
    if (user == null || !user.isActive) return null;

    final stored = user.passwordHash;

    if (PasswordHasher.isHashed(stored)) {
      final matches = PasswordHasher.verify(password, stored);
      return matches ? user : null;
    }

    // Legacy account created before password hashing was introduced —
    // `stored` is the plaintext password. Verify directly, then
    // transparently upgrade it to a proper hash so this branch is never
    // taken again for this user.
    if (stored == password) {
      final upgraded = user.copyWith(passwordHash: PasswordHasher.hash(password));
      await _userRepo.update(upgraded);
      return upgraded;
    }

    return null;
  }

  Future<bool> changePassword(String userId, String newPassword) async {
    try {
      final user = await _userRepo.getById(userId);
      if (user == null) return false;
      final updated = user.copyWith(
        passwordHash: PasswordHasher.hash(newPassword),
        mustChangePassword: false,
      );
      await _userRepo.update(updated);
      return true;
    } catch (e) {
      print('AuthService.changePassword error: $e');
      return false;
    }
  }

  Future<User?> getCurrentUser(String userId) async {
    try {
      return await _userRepo.getById(userId);
    } catch (e) {
      return null;
    }
  }
}