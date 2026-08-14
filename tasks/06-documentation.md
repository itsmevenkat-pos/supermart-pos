# Task 1.6: Documentation & PR

Depends on: 01–05, all green.

## Write

- `docs/GL_ARCHITECTURE.md` — the actual tables/classes as built (not the
  speculative design from these task files — if something changed during
  implementation, e.g. a different account for cash-vs-credit sales, the
  docs describe what's real).
- `docs/GL_USER_GUIDE.md` — short, for whoever reconciles the books: what a
  Trial Balance/P&L/Balance Sheet means here, how to read "not balanced,"
  and that closing a financial year is one-way (point at
  `financial_year_close_service.dart`'s existing behavior, don't restate
  it inaccurately).
- Update `README.md` at the repo root with a short "General Ledger" section
  linking to the above — check whether the root README already has a
  features list to slot into, rather than appending a disconnected section.

Skip a separate `GL_API.md`/`GL_DEVELOPER_GUIDE.md` split unless the
architecture doc is genuinely getting too long to hold both — this
codebase doesn't otherwise maintain per-module API references, don't
introduce a new documentation format Task 1's docs don't match.

## Open the PR

```bash
git push origin feature/phase1-gl
gh pr create --title "Phase 1: General Ledger module" --body "$(cat <<'EOF'
## Summary
- Chart of accounts + double-entry GL posting (chart_of_accounts, gl_entries, gl_balances)
- Auto-posting from sale/purchase/return completion
- Trial Balance, P&L, Balance Sheet reports + screens
- Respects existing financial-year-close lock

## Test plan
- [ ] flutter analyze clean
- [ ] flutter test (full suite) passes
- [ ] Manually verified Trial Balance balances after a few real sales/purchases in a dev build
EOF
)"
```

If `gh` isn't available in this environment, leave the branch pushed and
say so clearly in your final summary — don't fabricate a PR that wasn't
created.

## Done when

PR is open (or branch is pushed and you've said why no PR), `tasks/PROGRESS.md`
marks all 6 tasks complete, and the final message to the user summarizes
what was actually built vs. anything from the original scope that was
deliberately deferred (and why).
