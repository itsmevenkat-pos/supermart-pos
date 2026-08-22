import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ui_state_provider.dart';
import '../navigation/app_navigation.dart';
import '../navigation/navigation_item.dart';

const _sidebarWidth = 260.0;
const _sidebarBg = Color(0xFF1E2433);
const _sidebarSelectedBg = Color(0xFF2A3245);
const _sidebarHoverBg = Color(0xFF252D3D);
const _sidebarParentActiveBg = Color(0xFF232B3A);
const _accentColor = Color(0xFF5C6BC0);

String? _safeMatchedLocation(BuildContext context) {
  try {
    return GoRouterState.of(context).matchedLocation;
  } catch (_) {
    return null;
  }
}

const _collapsedAll = '__collapsed__';
final _expandedParentProvider = StateProvider<String?>((ref) => null);

class AppScaffold extends ConsumerWidget {
  final Widget body;
  final String title;
  final bool showBackButton;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const AppScaffold({
    super.key,
    required this.body,
    required this.title,
    this.showBackButton = true,
    this.actions,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSidebarOpen = ref.watch(sidebarOpenProvider);

    return Scaffold(
      body: Row(
        children: [
          if (isSidebarOpen)
            SizedBox(
              width: _sidebarWidth,
              child: _Sidebar(currentRoute: _safeMatchedLocation(context)),
            ),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: Text(title),
                leading: showBackButton
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/dashboard');
                          }
                        },
                      )
                    : null,
                actions: [
                  IconButton(
                    icon: Icon(isSidebarOpen ? Icons.menu_open : Icons.menu),
                    tooltip: isSidebarOpen ? 'Hide sidebar' : 'Show sidebar',
                    onPressed: () => ref.read(sidebarOpenProvider.notifier).state = !isSidebarOpen,
                  ),
                  ...?actions,
                ],
              ),
              body: body,
              floatingActionButton: floatingActionButton,
              floatingActionButtonLocation: floatingActionButtonLocation,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerStatefulWidget {
  final String? currentRoute;

  const _Sidebar({required this.currentRoute});

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  final ScrollController _scrollController = ScrollController();

  String? _previousRoute;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).user?.role;
    if (role == null) return const SizedBox.shrink();

    final currentRoute = widget.currentRoute ?? '';
    final expandedId = ref.watch(_expandedParentProvider);

    if (_previousRoute != null && _previousRoute != currentRoute) {
      if (expandedId == _collapsedAll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(_expandedParentProvider.notifier).state = null;
        });
      }
    }
    _previousRoute = currentRoute;

    final activeParent = findParentForRoute(currentRoute);
    final effectiveExpanded =
        expandedId == _collapsedAll ? null : (expandedId ?? activeParent?.id);

    return Container(
      color: _sidebarBg,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SuperMart POS',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
                  for (final parent in appNavigation)
                    if (parent.isVisibleTo(role))
                      _ParentSection(
                        parent: parent,
                        role: role,
                        currentRoute: currentRoute,
                        isExpanded: effectiveExpanded == parent.id,
                        onToggle: () {
                          final eff = effectiveExpanded;
                          ref.read(_expandedParentProvider.notifier).state =
                              eff == parent.id ? _collapsedAll : parent.id;
                        },
                      ),
                ],
              ),
            ),
            _UserProfileSection(
              user: ref.watch(authProvider).user!,
              onSignOut: () {
                ref.read(authProvider.notifier).logout();
                context.go('/login');
              },
              onChangePassword: () => context.go('/change-password'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentSection extends StatelessWidget {
  final NavParent parent;
  final UserRole role;
  final String currentRoute;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _ParentSection({
    required this.parent,
    required this.role,
    required this.currentRoute,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = parent.ownsRoute(currentRoute);
    final visibleChildren = parent.visibleChildren(role);
    final isLeaf = parent.directRoute != null && visibleChildren.length <= 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParentTile(
          parent: parent,
          isActive: isActive,
          isExpanded: isExpanded,
          isLeaf: isLeaf,
          onTap: () {
            if (isLeaf) {
              context.go(parent.directRoute ?? visibleChildren.first.route);
            } else {
              onToggle();
            }
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: isExpanded && !isLeaf
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final child in visibleChildren)
                      _ChildTile(
                        child: child,
                        isActive: currentRoute == child.route ||
                            currentRoute.startsWith('${child.route}/'),
                        onTap: () => context.go(child.route),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ParentTile extends StatefulWidget {
  final NavParent parent;
  final bool isActive;
  final bool isExpanded;
  final bool isLeaf;
  final VoidCallback onTap;

  const _ParentTile({
    required this.parent,
    required this.isActive,
    required this.isExpanded,
    required this.isLeaf,
    required this.onTap,
  });

  @override
  State<_ParentTile> createState() => _ParentTileState();
}

class _ParentTileState extends State<_ParentTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    Color bg;
    if (widget.isActive && widget.isExpanded) {
      bg = _sidebarParentActiveBg;
    } else if (_hovering) {
      bg = _sidebarHoverBg;
    } else {
      bg = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        color: bg,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  widget.parent.icon,
                  size: 20,
                  color: widget.isActive ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.parent.label,
                    style: TextStyle(
                      color: widget.isActive ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!widget.isLeaf)
                  AnimatedRotation(
                    turns: widget.isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: widget.isActive ? Colors.white : Colors.white54,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildTile extends StatefulWidget {
  final NavChild child;
  final bool isActive;
  final VoidCallback onTap;

  const _ChildTile({
    required this.child,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ChildTile> createState() => _ChildTileState();
}

class _ChildTileState extends State<_ChildTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    Color bg;
    if (widget.isActive) {
      bg = _sidebarSelectedBg;
    } else if (_hovering) {
      bg = _sidebarHoverBg;
    } else {
      bg = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: widget.isActive
              ? const Border(left: BorderSide(color: _accentColor, width: 3))
              : null,
        ),
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.isActive ? 37 : 40,
              right: 16,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                if (widget.child.icon != null) ...[
                  Icon(
                    widget.child.icon,
                    size: 16,
                    color: widget.isActive ? Colors.white : Colors.white60,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    widget.child.label,
                    style: TextStyle(
                      color: widget.isActive ? Colors.white : Colors.white60,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserProfileSection extends StatelessWidget {
  final User user;
  final VoidCallback onSignOut;
  final VoidCallback onChangePassword;

  const _UserProfileSection({
    required this.user,
    required this.onSignOut,
    required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    final roleName = user.role.name[0].toUpperCase() + user.role.name.substring(1);
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _accentColor,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.name.isNotEmpty ? user.name : user.username,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  roleName,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white60, size: 20),
            color: const Color(0xFF2A3245),
            onSelected: (value) {
              if (value == 'password') onChangePassword();
              if (value == 'signout') onSignOut();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'password',
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Change Password', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
