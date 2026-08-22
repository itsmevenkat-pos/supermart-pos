# Navigation Changelog — Phase 3

Date: 2026-08-18

---

## Files Created

| File | Reason | Change | Risk | Tested |
|------|--------|--------|------|--------|
| `lib/core/navigation/navigation_item.dart` | Centralized navigation data model | Added `NavParent`, `NavChild` classes with permission checks, active state detection, prefix-based route matching | Low — new file, no existing code affected | Navigation regression tests (40 tests) |
| `lib/core/navigation/app_navigation.dart` | Complete 11-parent navigation tree | Static `appNavigation` list with all 40 sidebar children, stable IDs, route mappings, role-based visibility, `findParentForRoute()` helper | Low — new file, declarative data | Navigation regression tests (40 tests) |
| `test/core/navigation/navigation_model_test.dart` | Navigation regression tests | 40 tests covering structure, permissions, active state, route completeness, utility migration | None — test file only | Self-verifying |

## Files Modified

| File | Reason | Change | Risk | Tested |
|------|--------|--------|------|--------|
| `lib/core/widgets/app_scaffold.dart` | Replace flat sidebar + Utilities flyout with parent→child expandable sidebar | Removed: flat `_tile()` list (22 items), `_UtilitiesFlyoutTile` widget (lines 173–306), `_flyoutWidth` constant, `OverlayEntry`/`CompositedTransformFollower` flyout mechanism. Added: `_Sidebar` as `ConsumerStatefulWidget` with `ScrollController`, `_ParentSection` with `AnimatedSize` expand/collapse, `_ParentTile` with hover state and chevron rotation, `_ChildTile` with active accent bar, `_expandedParentProvider` for accordion state. Preserved: `_sidebarWidth` (260px), `_sidebarBg` (#1E2433), `_sidebarSelectedBg` (#2A3245), `_safeMatchedLocation()`, `AppScaffold` public API (body, title, showBackButton, actions, FAB), sidebar toggle via `sidebarOpenProvider` | Medium — core navigation widget rewritten; visual regression possible | flutter test (672 passed), flutter analyze (0 errors), navigation regression tests (40 tests) |
| `lib/core/routes/app_router.dart` | Fix GoRouter redirect loop for `/change-password` | Added early return `if (changingPassword) { return null; }` after the `mustChangePassword` check and before the accountant/role-rank checks. Prevents infinite redirect loop when a user with `must_change_password: 1` (e.g., seed admin) hits the accountant allowlist check, which rejected `/change-password` and bounced to `/dashboard`, which forced back to `/change-password`. | Low — adds one guard clause; no route definitions, `_routeMinRole`, or `_accountantAllowedRoutes` changed | flutter test (672 passed), flutter analyze (0 errors) |

## Files Deleted

None.

## Files NOT Modified (safety verification)

| Category | Files | Verified |
|----------|-------|----------|
| Routes | `lib/core/routes/app_router.dart` | Minimally modified — one guard clause added to fix redirect loop. All 64 GoRoute definitions, `_routeMinRole`, `_accountantAllowedRoutes` unchanged. |
| Business logic | All repositories, services, providers | Not modified. |
| Database | `database_helper.dart`, all migrations | Not modified. |
| Screens | All 70 screen files under `lib/features/` | Not modified. |
| Billing | `billing_screen.dart` including keyboard shortcuts | Not modified. F1–F12 shortcuts unchanged. |
| Reports | `reports_screen.dart` | Not modified. 6-tab structure preserved. |
| Settings | `settings_screen.dart` | Not modified. 18-item flat list preserved. |
| Tests | All existing test files | Not modified. All 632 existing tests still pass. |
