import 'package:flutter/material.dart';

import '../../models/user_model.dart';

class NavChild {
  final String id;
  final String label;
  final String route;
  final IconData? icon;
  final UserRole? minRole;
  final bool accountantAllowed;

  const NavChild({
    required this.id,
    required this.label,
    required this.route,
    this.icon,
    this.minRole,
    this.accountantAllowed = false,
  });

  bool isVisibleTo(UserRole role) {
    if (role == UserRole.accountant) return accountantAllowed;
    if (minRole == null) return true;
    return _roleRank(role) <= _roleRank(minRole!);
  }
}

class NavParent {
  final String id;
  final String label;
  final IconData icon;
  final List<NavChild> children;
  final String? directRoute;

  const NavParent({
    required this.id,
    required this.label,
    required this.icon,
    required this.children,
    this.directRoute,
  });

  bool isVisibleTo(UserRole role) {
    if (directRoute != null && children.isEmpty) return true;
    return children.any((c) => c.isVisibleTo(role));
  }

  List<NavChild> visibleChildren(UserRole role) {
    return children.where((c) => c.isVisibleTo(role)).toList();
  }

  bool ownsRoute(String currentRoute) {
    if (directRoute != null && currentRoute == directRoute) return true;
    return children.any((c) => currentRoute == c.route || currentRoute.startsWith('${c.route}/'));
  }

  NavChild? activeChild(String currentRoute) {
    for (final child in children) {
      if (currentRoute == child.route || currentRoute.startsWith('${child.route}/')) {
        return child;
      }
    }
    return null;
  }
}

int _roleRank(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 0;
    case UserRole.manager:
      return 1;
    case UserRole.cashier:
      return 2;
    case UserRole.accountant:
      return 3;
  }
}
