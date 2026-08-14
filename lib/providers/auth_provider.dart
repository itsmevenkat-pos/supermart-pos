import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

/// Sentinel used so [AuthState.copyWith] can tell "field not passed" apart
/// from "field explicitly passed as null" — without this, `error: null`
/// silently keeps whatever error was already there (`null ?? old` == old).
class _Unset {
  const _Unset();
}

const _unset = _Unset();

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  AuthState copyWith({
    Object? user = _unset,
    bool? isLoading,
    Object? error = _unset,
  }) {
    return AuthState(
      user: identical(user, _unset) ? this.user : user as User?,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({AuthService? authService})
      : _authService = authService ?? AuthService(),
        super(const AuthState());

  final AuthService _authService;

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _authService.login(username, password);
      if (user != null) {
        state = state.copyWith(user: user, isLoading: false, error: null);
        return true;
      } else {
        state = state.copyWith(isLoading: false, error: 'Invalid username or password');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  void logout() {
    state = const AuthState();
  }

  Future<bool> changePassword(String newPassword) async {
    final currentUser = state.user;
    if (currentUser == null) {
      state = state.copyWith(error: 'No user logged in');
      return false;
    }
    try {
      final success = await _authService.changePassword(currentUser.id, newPassword);
      if (success) {
        final updatedUser = currentUser.copyWith(mustChangePassword: false);
        state = state.copyWith(user: updatedUser, error: null);
        return true;
      } else {
        state = state.copyWith(error: 'Failed to change password');
        return false;
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  User? get currentUser => state.user;
  bool get isLoggedIn => state.user != null;
  bool get isAdmin => state.user?.role == UserRole.admin;
  bool get isManager => state.user?.role == UserRole.manager || isAdmin;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});