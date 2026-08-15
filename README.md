# supermart_pos_clean

A new Flutter project.

For what is and isn't built across the whole app, see
[FEATURE_STATUS.md](FEATURE_STATUS.md) — that is the live reference.

## General Ledger

Double-entry bookkeeping. Every completed sale, purchase and sales return
posts its own balanced journal entries inside the same database transaction as
the transaction itself, against a seeded chart of accounts. Trial Balance,
Profit & Loss and Balance Sheet are under **Reports → More → Accounts (General
Ledger)**.

- [docs/GL_ARCHITECTURE.md](docs/GL_ARCHITECTURE.md) — schema, classes, where
  each posting happens, and the known gaps.
- [docs/GL_USER_GUIDE.md](docs/GL_USER_GUIDE.md) — reading the three reports,
  what "NOT balanced" means, and why closing a financial year is permanent.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
