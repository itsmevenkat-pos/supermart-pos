import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ui_state_provider.dart';

const _sidebarWidth = 260.0;
const _sidebarBg = Color(0xFF1E2433);
const _sidebarSelectedBg = Color(0xFF2A3245);
const _flyoutWidth = 240.0;

/// `GoRouterState.of(context)` only works when this widget is built as part
/// of a page go_router itself pushed — it throws "The parent route must be
/// a page route to have a GoRouterState" when `AppScaffold` ends up inside a
/// screen pushed via a plain `Navigator.push(MaterialPageRoute(...))`
/// instead of `context.push()` (as a couple of screens do). That's only used
/// here to highlight the current item in the sidebar, so on failure this
/// falls back to "nothing highlighted" instead of taking down the whole app.
String? _safeMatchedLocation(BuildContext context) {
  try {
    return GoRouterState.of(context).matchedLocation;
  } catch (_) {
    return null;
  }
}

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

/// The persistent left navigation panel — replaces the old tap-to-open
/// overlay `Drawer` with an always-visible column that stays open across
/// navigations until the user collapses it via the AppBar toggle.
class _Sidebar extends ConsumerWidget {
  final String? currentRoute;

  const _Sidebar({required this.currentRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authProvider).user?.role;
    final isAdmin = role == UserRole.admin;
    final isManager = role == UserRole.manager || isAdmin;
    // Accountant is a narrow allowlist (see _accountantAllowedRoutes in
    // app_router.dart), not a rank between manager and cashier — it needs
    // its own visibility checks below rather than folding into isManager.
    final isAccountant = role == UserRole.accountant;

    return Container(
      color: _sidebarBg,
      child: SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text(
                'SuperMart POS',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            _tile(context, 'Dashboard', Icons.dashboard, '/dashboard'),
            _tile(context, 'Billing', Icons.point_of_sale, '/billing'),
            if (isManager) _tile(context, 'Products', Icons.inventory, '/products'),
            if (isManager) _tile(context, 'Promotions', Icons.local_offer, '/promotions'),
            if (isManager) _tile(context, 'Coupons', Icons.confirmation_number, '/coupons'),
            if (isManager) _tile(context, 'Stock Groups', Icons.merge_type, '/stock-groups'),
            _tile(context, 'Customers', Icons.people, '/customers'),
            if (isManager || isAccountant) _tile(context, 'Suppliers', Icons.business, '/suppliers'),
            if (isManager) _tile(context, 'Purchases', Icons.receipt_long, '/purchases'),
            _tile(context, 'Returns', Icons.assignment_return, '/returns'),
            _tile(context, 'Sale Cancellations', Icons.cancel_outlined, '/sales-cancellations'),
            _tile(context, 'Exchanges', Icons.swap_horiz, '/exchanges'),
            // Sales History, Sales Summary, and Quotations moved into
            // Reports → Sales ("Detailed Reports") instead of living here —
            // they were duplicated in both places before.
            if (isManager || isAccountant) _tile(context, 'Reports', Icons.assessment, '/reports'),
            if (isAdmin) _tile(context, 'Users', Icons.people_outline, '/users'),
            if (isManager) _tile(context, 'Settings', Icons.settings, '/settings'),
            if (isManager || isAccountant)
              _UtilitiesFlyoutTile(isAdmin: isAdmin, isManager: isManager, isAccountant: isAccountant),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, String title, IconData icon, String route) {
    final isSelected = currentRoute == route;
    return Container(
      color: isSelected ? _sidebarSelectedBg : Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Colors.white : Colors.white70),
        title: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70)),
        onTap: () => context.go(route),
      ),
    );
  }
}

/// "Utilities" as a flyout submenu that opens to the right of the sidebar,
/// instead of an `ExpansionTile` that pushed every item below it down the
/// column — with 12 sub-items that made the rest of the sidebar hard to
/// reach without scrolling.
class _UtilitiesFlyoutTile extends StatefulWidget {
  final bool isAdmin;
  final bool isManager;
  final bool isAccountant;

  const _UtilitiesFlyoutTile({
    required this.isAdmin,
    required this.isManager,
    required this.isAccountant,
  });

  @override
  State<_UtilitiesFlyoutTile> createState() => _UtilitiesFlyoutTileState();
}

class _UtilitiesFlyoutTileState extends State<_UtilitiesFlyoutTile> {
  final _layerLink = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      setState(_removeOverlay);
      return;
    }
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Invisible full-screen barrier so tapping anywhere outside the
          // flyout closes it, without blocking the app underneath visually.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(_removeOverlay),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            // The "Utilities" tile sits at the bottom of the sidebar list, so
            // anchoring the flyout to its top (as a naive follower would)
            // pushes the menu downward off the bottom of the window. Anchor
            // bottom-of-flyout to bottom-of-tile instead, so it opens upward
            // and stays fully on screen.
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.bottomLeft,
            child: Material(
              color: _sidebarBg,
              elevation: 8,
              child: SizedBox(
                width: _flyoutWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (widget.isManager)
                        _flyoutItem(context, 'Import Items', Icons.upload_file, '/utilities/import-items'),
                      if (widget.isManager)
                        _flyoutItem(context, 'Set Up My Business', Icons.store, '/settings/business-profile'),
                      if (widget.isAdmin)
                        _flyoutItem(context, 'Accountant Access', Icons.badge, '/utilities/accountant-access'),
                      if (widget.isManager)
                        _flyoutItem(context, 'Barcode Generator', Icons.qr_code, '/utilities/barcode-generator'),
                      if (widget.isManager)
                        _flyoutItem(
                            context, 'Festival Calendar', Icons.celebration_outlined, '/utilities/festival-calendar'),
                      if (widget.isManager)
                        _flyoutItem(
                            context, 'Update Items In Bulk', Icons.edit_note, '/utilities/bulk-update-items'),
                      if (widget.isAdmin)
                        _flyoutItem(context, 'Import From Tally', Icons.file_download, '/utilities/import-tally'),
                      if (widget.isManager)
                        _flyoutItem(context, 'Import Parties', Icons.group_add, '/utilities/import-parties'),
                      if (widget.isManager)
                        _flyoutItem(
                            context, 'Track Your Salesmen', Icons.badge_outlined, '/utilities/track-salesmen'),
                      if (widget.isAdmin || widget.isAccountant)
                        _flyoutItem(context, 'Exports To Tally', Icons.file_upload, '/utilities/export-tally'),
                      if (widget.isManager || widget.isAccountant)
                        _flyoutItem(context, 'Export Items', Icons.download, '/utilities/export-items'),
                      if (widget.isManager || widget.isAccountant)
                        _flyoutItem(context, 'Verify My Data', Icons.fact_check, '/utilities/verify-data'),
                      if (widget.isAdmin)
                        _flyoutItem(
                            context, 'Close Financial Year', Icons.event_busy, '/utilities/close-financial-year'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    setState(() {});
  }

  Widget _flyoutItem(BuildContext context, String title, IconData icon, String route) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white70)),
      onTap: () {
        setState(_removeOverlay);
        context.go(route);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _entry != null;
    return CompositedTransformTarget(
      link: _layerLink,
      child: ListTile(
        leading: const Icon(Icons.build, color: Colors.white70),
        title: const Text('Utilities', style: TextStyle(color: Colors.white)),
        trailing: Icon(isOpen ? Icons.chevron_left : Icons.chevron_right, color: Colors.white70),
        onTap: _toggle,
      ),
    );
  }
}
