# Phase 3.5 Remediation Report

Date: 2026-08-20

---

## 1. Executive Summary

Phase 3.5 addressed 11 identified usability defects in the POS navigation, reports, purchase, billing, and stock systems. All issues were resolved without breaking existing functionality. The test count grew from 672 to 699 (27 new Phase 3.5 regression tests). Zero analyzer errors or warnings.

---

## 2. Original Issues

| # | Issue | Priority |
|---|-------|----------|
| 1 | Sign Out missing | High |
| 2 | Duplicate Settings navigation | Medium |
| 3 | Duplicate Reports (Trial Balance, P&L, Balance Sheet) | Medium |
| 4 | Commission canonical location | Low |
| 5 | Parent collapse bug | High |
| 6 | Purchase Info buried in Details tab | Medium |
| 7 | Purchase screen UX confusing | Medium |
| 8 | Last Purchase Price not displayed | Medium |
| 9 | Negative stock display bug | High |
| 10 | Zero stock product handling | High |
| 11 | Multi-bill billing workspace | High |

---

## 3. Root Causes

| Issue | Root Cause |
|-------|-----------|
| Sign Out | `AuthNotifier.logout()` existed but was never called from any UI element |
| Duplicate Settings | Not a bug — audit confirmed no duplicates exist. 7 unique children under SETTINGS parent. |
| Duplicate Reports | Intentional dual implementations: simplified (operational) vs GL-based (accounting). Confusing naming. |
| Commission | Not a bug — already correctly placed under PEOPLE with one entry. |
| Parent collapse | `effectiveExpanded = expandedId ?? activeParent?.id` — null fallback immediately re-expands active parent |
| Purchase Info | Buried in Step 0 of a 3-step wizard |
| Purchase UX | 3-step wizard (Details/Items/Totals) fragmented the workflow |
| Last Purchase Price | `PurchaseItem.last` field stored value but never displayed in UI |
| Negative stock | Not a data bug — `_confirmAddDespiteLowStock` dialog lacked differentiation between allowNegative true/false cases |
| Zero stock | Search path did not match product grid behavior (grid blocks taps, search allowed all) |
| Multi-bill | Single `cartProvider` instance with no concept of concurrent bills |

---

## 4. Fixes Implemented

### Issue 1 — Sign Out
- Added `_UserProfileSection` widget to sidebar bottom
- Shows user avatar (first letter), name, role
- PopupMenuButton with "Change Password" and "Sign Out"
- Sign Out calls `AuthNotifier.logout()` then `context.go('/login')`
- GoRouter redirect prevents back navigation into authenticated screens

### Issue 2 — Duplicate Settings
- Audit confirmed NO duplicates. PASS with no changes needed.

### Issue 3 — Duplicate Reports
- Renamed simplified versions: "Trial Balance (Summary)", "Balance Sheet (Summary)"
- Renamed GL category: "Accounting Statements (General Ledger)"
- Renamed GL reports: "Trial Balance (GL)", "Profit & Loss (GL)", "Balance Sheet (GL)"
- No reports deleted, no routes changed, no calculations modified
- Created `docs/REPORT_DUPLICATION_AUDIT.md` with full trace analysis

### Issue 4 — Commission
- Audit confirmed already correct under PEOPLE. PASS with no changes needed.

### Issue 5 — Parent Collapse Bug
- Added `_collapsedAll` sentinel constant
- Changed toggle: sets provider to `_collapsedAll` (not null) when collapsing active parent
- `effectiveExpanded` treats `_collapsedAll` as null (all collapsed) instead of falling back to active parent
- Route change resets sentinel via `addPostFrameCallback`

### Issue 6 — Purchase Info Location
- Purchase Info section now visible directly in the single scrollable layout (no longer hidden in a separate wizard step)

### Issue 7 — Purchase Screen UX
- Flattened from 3-step wizard to single scrollable layout: Supplier/Invoice -> Product Search -> Items -> Totals
- Removed `_step` state variable and `_buildStepTabs()`
- `_goToStepWithError()` replaced with `_showError()`

### Issue 8 — Last Purchase Price
- Added `_lastPriceComparison()` widget to purchase item cards
- Shows: Last Purchase Price, Current Purchase Price, Difference (+/-)
- Uses existing `PurchaseItem.last` field (already stored `product.costPrice` at add time)

### Issue 9 — Negative Stock Bug
- Enhanced `_confirmAddDespiteLowStock()` with `allowNegative` parameter
- When stock=0 and negative NOT allowed: "This product cannot be added because available stock is 0." with only OK button
- When stock=0 and negative IS allowed: "Current stock: 0" with Cancel and Add Anyway buttons
- When low stock: "Only X left in stock." with Cancel and Add Anyway buttons

### Issue 10 — Zero Stock Handling
- Same dialog changes as Issue 9
- Product grid already blocks out-of-stock taps (existing behavior preserved)
- Search path now shows proper dialog differentiating allow/block cases

### Issue 11 — Multi-Bill Workspace
- Added `BillSnapshot` class capturing full cart state (items, customer, discount, delivery, loyalty, coupon)
- Added `BillTab` class with id, snapshot, and status (active/paymentPending)
- Added `BillWorkspace` Riverpod provider managing multiple tabs
- Added `takeSnapshot()`/`restoreSnapshot()` methods to Cart provider
- Added `_BillTabBar` widget with compact bill chips
- Bill chips show: bill number, label (customer name or item count), status indicator
- Tab bar appears when >1 bill exists; single "New Bill" button when only 1

---

## 5. Navigation Changes

| Change | Detail |
|--------|--------|
| Sign Out added | User profile section at sidebar bottom with Sign Out menu |
| No parents added/removed | Still 11 parents, 40 children |
| No routes added/removed | Still 61 routes |
| No screens deleted | Still 70 screens |

---

## 6. Report Duplication Audit

See `docs/REPORT_DUPLICATION_AUDIT.md` for full details.

Summary: Trial Balance, Balance Sheet, and P&L each have two intentionally different implementations (simplified operational vs GL-based accounting). All KEPT with clarified naming. No reports deleted.

---

## 7. Purchase UX Changes

| Before | After |
|--------|-------|
| 3-step wizard (Details / Items / Totals) | Single scrollable layout |
| Purchase Info in Step 0 only | Visible inline in main flow |
| Last Purchase Price stored but hidden | Displayed with price comparison (+/-) |
| Step navigation with tabs | Direct scroll to any section |

---

## 8. Billing UX Changes

| Before | After |
|--------|-------|
| Generic low stock dialog for all cases | Differentiated Out of Stock / Low Stock dialog |
| No negative stock differentiation | Blocks add when negative not allowed; warns when allowed |
| Single bill at a time | Multi-bill workspace with tab switching |
| F12 only way to "start new" (destructive) | Tab bar + button adds new bill (non-destructive) |

---

## 9. Multi-Bill Implementation

- Architecture: In-memory state via Riverpod `BillWorkspace` provider
- Cart provider remains single source of truth for active bill
- `takeSnapshot()` saves full state; `restoreSnapshot()` loads it
- Switching bills: save current -> load target
- No database changes required
- Hold system (F3/F4) continues to work independently
- Keyboard shortcuts (F1-F12) unmodified — they operate on the active bill

---

## 10. Permission Verification

| Role | Access Unchanged |
|------|-----------------|
| Admin | All 11 parents, all 40 children |
| Manager | 10-11 parents (as before) |
| Cashier | HOME, SALES, CUSTOMERS, DOCUMENTS, EXPENSES & CASH |
| Accountant | Limited parents with accountantAllowed flag |

Report permissions: manager+ and accountant. No changes.

---

## 11. Keyboard Shortcut Verification

All 18 keyboard shortcuts preserved. No conflicts introduced.

| F1-F12 | Unchanged | Multi-bill does not steal any shortcut |
|--------|-----------|---------------------------------------|

---

## 12. Route Verification

61 / 61 routes remain valid. No routes added, removed, or renamed.

---

## 13. Database Verification

NO database changes. Multi-bill uses in-memory state. No migrations added.

---

## 14. Tests Added

27 new regression tests in `test/phase3_5/remediation_test.dart`:

| Group | Count | Covers |
|-------|-------|--------|
| Navigation | 9 | Settings uniqueness, commission location, parent collapse, child nav, report routes, permissions, parent/child counts |
| Multi-bill | 7 | BillSnapshot state, isEmpty, label (customer/items), BillTab defaults, workspace state, data isolation |
| Stock display | 3 | Zero stock, low stock, allowNegativeStock flag |
| Purchase | 1 | Last purchase price field |
| Regression safety | 7 | No duplicate routes, parent icons, findParentForRoute, role visibility |

---

## 15. Regression Test Results

```
699 tests passed, 0 failures
- 672 existing tests: all passing
- 27 new Phase 3.5 tests: all passing
```

---

## 16. Analyzer Result

```
0 errors
0 warnings
Info-level issues only (pre-existing: prefer_const_constructors, etc.)
```

---

## 17. Build Result

- `flutter test`: 699/699 passed
- `dart analyze`: 0 errors, 0 warnings on modified files

---

## 18. Files Modified

| File | Change |
|------|--------|
| `lib/core/widgets/app_scaffold.dart` | Added `_collapsedAll` sentinel for collapse fix, route-change reset, `_UserProfileSection` widget with Sign Out |
| `lib/features/reports/screens/reports_screen.dart` | Renamed simplified reports to "(Summary)", GL reports to "(GL)", category to "Accounting Statements" |
| `lib/providers/cart_provider.dart` | Added `BillSnapshot`, `BillTab`, `BillWorkspace` classes; `takeSnapshot()`/`restoreSnapshot()` on Cart |
| `lib/features/billing/screens/billing_screen.dart` | Added `_BillTabBar`, `_BillChip` widgets; enhanced `_confirmAddDespiteLowStock` with allowNegative; multi-bill tab bar in layout |
| `lib/features/purchases/screens/purchase_form_screen.dart` | Flattened 3-step wizard to single scroll; added last purchase price comparison |

---

## 19. Files Created

| File | Purpose |
|------|---------|
| `test/phase3_5/remediation_test.dart` | 27 Phase 3.5 regression tests |
| `docs/REPORT_DUPLICATION_AUDIT.md` | Report duplication analysis |
| `docs/PHASE_3_5_REMEDIATION_REPORT.md` | This report |
| `lib/providers/cart_provider.g.dart` | Regenerated Riverpod code for BillWorkspace |

---

## 20. Files Deleted

None.

---

## 21. Remaining Known Issues

| Issue | Priority | Notes |
|-------|----------|-------|
| Visual testing on desktop | Medium | App requires desktop launch (sqflite). Browser preview unavailable. |
| GL P&L COGS account reads zero | Low | Account 5000 has no postings — fix belongs on the posting side, not the report side |
| Hold restore adds to existing cart | Low | Restoring a held bill into a non-empty cart merges them instead of replacing |
| Category-level allowNegativeStock vs product-level | Low | Category flag only checked in UI; product flag enforced in DB. Could cause confusion. |
| Scroll-to-active sidebar child | Low | Deferred from Phase 3 |

---

## 22. Final Verdict

All 11 issues addressed. Zero regressions. PASS.
