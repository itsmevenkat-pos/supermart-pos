import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/utils/financial_year.dart';
import '../models/chart_of_account_model.dart';
import '../models/gl_entry_model.dart';
import '../repositories/gl_repository.dart';
import 'financial_year_close_service.dart';
import 'gl_exceptions.dart';

/// The rules of the General Ledger: what may be posted, when, and against
/// which accounts. `GLRepository` stores; this decides.
///
/// Three invariants are enforced here and nowhere else:
/// 1. Every compound entry balances — checked before the first insert, so an
///    unbalanced entry never partially lands.
/// 2. Nothing posts into a closed financial year.
/// 3. Corrections are reversals, never edits — the journal is append-only.
class GLService {
  GLService({
    GLRepository? glRepository,
    FinancialYearCloseService? closeService,
    DatabaseHelper? dbHelper,
  })  : _glRepository = glRepository ?? GLRepository(),
        _closeService = closeService ?? FinancialYearCloseService(),
        _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final GLRepository _glRepository;
  final FinancialYearCloseService _closeService;
  final DatabaseHelper _dbHelper;

  /// Rounding tolerance. Bill totals are rupees-and-paise doubles that have
  /// already been through tax and discount arithmetic, so two sides of an
  /// entry can legitimately differ in the last paisa; anything larger is a
  /// real imbalance, not floating point.
  static const double balanceTolerance = 0.01;

  // ------------------------------------------------------------------ posting

  /// Posts a single one-sided line and refreshes that account's cached balance.
  ///
  /// Useful on its own only for genuinely one-sided adjustments; a real
  /// transaction has at least two sides and should go through
  /// [postCompoundEntry], which is the method that can actually check that the
  /// two sides agree.
  Future<GLEntry> postEntry({
    required DateTime entryDate,
    required String accountId,
    required double amount,
    required bool isDebit,
    required String description,
    required String referenceType,
    String? referenceId,
    String? createdBy,
    DatabaseExecutor? executor,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('A GL entry amount must be greater than zero (got $amount). '
          'Use isDebit to choose the side rather than a negative amount.');
    }

    final financialYear = financialYearLabel(entryDate);

    return _run(executor, (db) async {
      await _requirePostable(db, [accountId], financialYear);

      final entry = await _glRepository.postEntry(
        GLEntry.post(
          entryDate: entryDate,
          accountId: accountId,
          amount: amount,
          isDebit: isDebit,
          description: description,
          referenceType: referenceType,
          referenceId: referenceId,
          createdBy: createdBy,
        ),
        executor: db,
      );
      await _glRepository.recalculateBalance(accountId, financialYear, executor: db);
      return entry;
    });
  }

  /// Posts one double-entry transaction as several lines that must agree.
  ///
  /// [accounts] maps an account id to a signed amount: **positive is a debit,
  /// negative is a credit**. The two sides are summed and compared first — if
  /// they differ by more than [balanceTolerance], [UnbalancedEntry] is thrown
  /// and nothing at all is written. Entries with a zero amount are skipped
  /// rather than rejected, so a caller can pass a computed split (e.g. the
  /// cash portion of a fully-on-credit sale) without special-casing zero.
  ///
  /// Pass [executor] to post inside a caller's transaction — that is how a
  /// sale and its ledger entries commit or roll back as one. Without it, the
  /// lines still post atomically, just in a transaction of their own.
  Future<List<GLEntry>> postCompoundEntry({
    required DateTime entryDate,
    required String description,
    required String referenceType,
    String? referenceId,
    required Map<String, double> accounts,
    String? createdBy,
    DatabaseExecutor? executor,
  }) async {
    final lines = Map.of(accounts)..removeWhere((_, amount) => amount == 0);
    if (lines.isEmpty) {
      throw const UnbalancedEntry('A compound entry needs at least one non-zero line.');
    }

    // Checked before anything is written — an unbalanced entry must never
    // reach the journal even partially.
    var debits = 0.0;
    var credits = 0.0;
    for (final amount in lines.values) {
      if (amount > 0) {
        debits += amount;
      } else {
        credits += -amount;
      }
    }
    if ((debits - credits).abs() > balanceTolerance) {
      throw UnbalancedEntry(
        'Debits and credits must agree: debits ${debits.toStringAsFixed(2)} vs '
        'credits ${credits.toStringAsFixed(2)} (difference '
        '${(debits - credits).abs().toStringAsFixed(2)}) for "$description".',
      );
    }
    if (debits == 0) {
      throw const UnbalancedEntry('A compound entry cannot be all-zero on both sides.');
    }

    final financialYear = financialYearLabel(entryDate);

    return _run(executor, (db) async {
      await _requirePostable(db, lines.keys, financialYear);

      final posted = <GLEntry>[];
      for (final entry in lines.entries) {
        posted.add(await _glRepository.postEntry(
          GLEntry.post(
            entryDate: entryDate,
            accountId: entry.key,
            amount: entry.value.abs(),
            isDebit: entry.value > 0,
            description: description,
            referenceType: referenceType,
            referenceId: referenceId,
            createdBy: createdBy,
          ),
          executor: db,
        ));
      }
      for (final accountId in lines.keys) {
        await _glRepository.recalculateBalance(accountId, financialYear, executor: db);
      }
      return posted;
    });
  }

  /// Corrects [entryId] by posting its mirror image — same account, same
  /// amount, opposite side — linked back via `reversalOfEntryId`.
  ///
  /// The original is neither deleted nor modified. That is the whole point:
  /// a ledger where mistakes disappear is a ledger nobody can audit, so a
  /// correction is itself a transaction with its own date and reason.
  ///
  /// The reversal is dated the same day as the original, so it lands in the
  /// same financial year and that year's totals actually net out. A
  /// consequence worth knowing: once a year is closed its entries can no
  /// longer be reversed at all ([ClosedPeriod]), which is the correct
  /// accounting outcome — a closed year's books do not move.
  Future<GLEntry> reverseEntry(
    String entryId, {
    required String reason,
    String? createdBy,
    DatabaseExecutor? executor,
  }) async {
    return _run(executor, (db) async {
      final original = await _glRepository.getEntry(entryId, executor: db);
      if (original == null) {
        throw EntryNotFound('No GL entry with id $entryId to reverse.');
      }

      await _requirePostable(db, [original.accountId], original.financialYear,
          requireActive: false);

      final reversal = await _glRepository.postEntry(
        GLEntry.post(
          entryDate: original.entryDateTime,
          accountId: original.accountId,
          amount: original.amount,
          isDebit: !original.isDebit,
          description: 'Reversal: ${original.description} ($reason)',
          referenceType: original.referenceType,
          referenceId: original.referenceId,
          createdBy: createdBy,
          reversalOfEntryId: original.id,
        ),
        executor: db,
      );
      await _glRepository.recalculateBalance(original.accountId, original.financialYear, executor: db);
      return reversal;
    });
  }

  /// Reverses every line of one source document — the counterpart to a
  /// compound post. Used when a sale is returned or cancelled: each of the
  /// sale's lines gets its own mirror, so the pair nets to zero.
  Future<List<GLEntry>> reverseByReference(
    String referenceType,
    String referenceId, {
    required String reason,
    String? createdBy,
    DatabaseExecutor? executor,
  }) async {
    return _run(executor, (db) async {
      final originals = await _glRepository.getEntriesByReference(referenceType, referenceId, executor: db);
      final reversals = <GLEntry>[];
      for (final original in originals) {
        // Already-reversed lines are skipped so reversing twice doesn't
        // double-count — the second call is a no-op rather than a new
        // opposite entry that swings the balance the wrong way.
        if (original.reversalOfEntryId != null) continue;
        if (originals.any((e) => e.reversalOfEntryId == original.id)) continue;
        reversals.add(await reverseEntry(
          original.id,
          reason: reason,
          createdBy: createdBy,
          executor: db,
        ));
      }
      return reversals;
    });
  }

  // ----------------------------------------------------------------- balances

  /// The account's balance in its own natural direction (see [signedBalance]),
  /// for [financialYear] or the current one.
  ///
  /// Reads the `gl_balances` cache, recalculating first when the cache is
  /// missing or older than the newest entry for that account and year — so a
  /// caller never has to know whether the cache is warm.
  Future<double> getRunningBalance(
    String accountId, {
    String? financialYear,
    DatabaseExecutor? executor,
  }) async {
    final year = financialYear ?? financialYearLabel(DateTime.now());

    return _run(executor, (db) async {
      final account = await _glRepository.getAccount(accountId, executor: db);
      if (account == null) {
        throw AccountNotFound('No account with id $accountId.');
      }

      var cached = await _glRepository.getAccountBalance(accountId, year, executor: db);
      if (cached == null || await _isStale(db, accountId, year, cached.lastUpdated)) {
        cached = await _glRepository.recalculateBalance(accountId, year, executor: db);
      }
      return cached.balance;
    });
  }

  /// Rebuilds every cached balance for [financialYear] from the journal.
  /// A repair tool: nothing in normal operation needs it, because each post
  /// refreshes the accounts it touched.
  Future<void> recalculateAllBalances(String financialYear, {DatabaseExecutor? executor}) async {
    return _run(executor, (db) async {
      for (final account in await _glRepository.getAllAccounts(executor: db)) {
        await _glRepository.recalculateBalance(account.id, financialYear, executor: db);
      }
    });
  }

  /// Whether the journal has moved since the cached balance was written.
  Future<bool> _isStale(DatabaseExecutor db, String accountId, String year, int lastUpdated) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM gl_entries WHERE account_id = ? AND financial_year = ? AND created_at > ?',
      [accountId, year, lastUpdated],
    );
    return (rows.first['n'] as int) > 0;
  }

  // ------------------------------------------------------------------ helpers

  /// Every guard that has to hold before a line is written: the accounts exist
  /// and are usable, and the year is still open.
  ///
  /// [requireActive] is relaxed for reversals — an account can be deactivated
  /// after it was posted to, and refusing to correct history on that basis
  /// would leave a wrong balance permanently wrong.
  Future<void> _requirePostable(
    DatabaseExecutor db,
    Iterable<String> accountIds,
    String financialYear, {
    bool requireActive = true,
  }) async {
    if (await _closeService.isFinancialYearClosed(financialYear, executor: db)) {
      throw ClosedPeriod(
        'Financial year $financialYear is closed — no further entries can be posted to it.',
      );
    }
    for (final accountId in accountIds) {
      final account = await _glRepository.getAccount(accountId, executor: db);
      if (account == null) {
        throw AccountNotFound('No account with id $accountId.');
      }
      if (requireActive && !account.isActive) {
        throw AccountNotFound('Account ${account.code} (${account.name}) is deactivated and cannot be posted to.');
      }
    }
  }

  /// Runs [action] inside [executor] if the caller gave one, otherwise inside
  /// a transaction of its own — so a multi-line post is atomic either way and
  /// callers never have to think about which case they are in.
  Future<T> _run<T>(DatabaseExecutor? executor, Future<T> Function(DatabaseExecutor db) action) async {
    if (executor != null) return action(executor);
    final db = await _dbHelper.database;
    return db.transaction((txn) async => action(txn));
  }

  // ------------------------------------------------- sale/purchase posting

  /// Account codes the sale and purchase integrations post against. Named
  /// here so the rest of the app never has a bare '1000' in it, and so
  /// renaming an account in the UI can't quietly break posting.
  static const String cashAccountCode = '1000';
  static const String receivableAccountCode = '1100';
  static const String inventoryAccountCode = '1200';
  static const String payableAccountCode = '2000';
  static const String salesRevenueAccountCode = '4000';

  static const String saleReferenceType = 'Sale';
  static const String purchaseReferenceType = 'Purchase';

  /// The ledger side of a completed sale: debit what the shop received
  /// (cash now, a receivable for whatever the customer still owes), credit
  /// Sales Revenue for the full amount of the bill.
  ///
  /// [receivableAmount] is the part of [netAmount] not settled at the till —
  /// `creditUsed` plus any unpaid remainder. It is clamped into
  /// `[0, netAmount]` so a caller passing an inconsistent pair produces a
  /// balanced (if imperfectly split) entry rather than an unbalanced one that
  /// would block the sale.
  ///
  /// Returns an empty list for a zero-value bill — there is nothing to record,
  /// and it is not an error.
  ///
  /// Note on tax: the whole bill including GST credits Sales Revenue, because
  /// the default chart of accounts has no output-tax liability account. That
  /// is a deliberate Phase 1 simplification, not an oversight — splitting GST
  /// out means adding a tax account and reworking the sale split, which is
  /// its own change.
  Future<List<GLEntry>> postSaleEntries({
    required String saleId,
    required DateTime saleDate,
    required double netAmount,
    double receivableAmount = 0,
    String? description,
    String? createdBy,
    DatabaseExecutor? executor,
  }) async {
    if (netAmount == 0) return const [];

    return _run(executor, (db) async {
      final receivable = receivableAmount.clamp(0, netAmount).toDouble();
      final cash = netAmount - receivable;

      final cashAccount = await requireAccountByCode(cashAccountCode, executor: db);
      final receivableAccount = await requireAccountByCode(receivableAccountCode, executor: db);
      final revenueAccount = await requireAccountByCode(salesRevenueAccountCode, executor: db);

      return postCompoundEntry(
        entryDate: saleDate,
        description: description ?? 'Sale $saleId',
        referenceType: saleReferenceType,
        referenceId: saleId,
        accounts: {
          cashAccount.id: cash,
          receivableAccount.id: receivable,
          revenueAccount.id: -netAmount,
        },
        createdBy: createdBy,
        executor: db,
      );
    });
  }

  /// The ledger side of a received purchase: stock came in on the supplier's
  /// account, so debit Inventory and credit Accounts Payable.
  Future<List<GLEntry>> postPurchaseEntries({
    required String purchaseId,
    required DateTime purchaseDate,
    required double netAmount,
    String? description,
    String? createdBy,
    DatabaseExecutor? executor,
  }) async {
    if (netAmount == 0) return const [];

    return _run(executor, (db) async {
      final inventoryAccount = await requireAccountByCode(inventoryAccountCode, executor: db);
      final payableAccount = await requireAccountByCode(payableAccountCode, executor: db);

      return postCompoundEntry(
        entryDate: purchaseDate,
        description: description ?? 'Purchase $purchaseId',
        referenceType: purchaseReferenceType,
        referenceId: purchaseId,
        accounts: {
          inventoryAccount.id: netAmount,
          payableAccount.id: -netAmount,
        },
        createdBy: createdBy,
        executor: db,
      );
    });
  }

  static const String returnReferenceType = 'Return';

  /// The ledger side of a sales return: revenue the shop no longer earned, so
  /// debit Sales Revenue and credit whatever gave the money back — Cash for a
  /// cash refund, Accounts Receivable when the refund is adjusted against what
  /// the customer owes.
  ///
  /// **Why this is a fresh entry rather than `reverseEntry` on the sale's
  /// lines.** Task 1.3 suggested reversing the original sale line by line, and
  /// that is right for a full void — but a return is very often partial (two
  /// of five items come back). Reversing the sale's lines reverses the sale's
  /// *whole* amount, which would credit back more than was ever refunded and
  /// quietly overstate the reversal on every partial return. Posting
  /// [refundAmount] as its own balanced entry is correct for a partial and a
  /// full return alike, and the link back to the sale is preserved in the
  /// description plus the return row's own `sale_id`.
  ///
  /// `reverseEntry`/`reverseByReference` remain the right tool for an actual
  /// full void, which is what they are there for.
  Future<List<GLEntry>> postSalesReturnEntries({
    required String returnId,
    String? saleId,
    required DateTime returnDate,
    required double refundAmount,
    required bool refundedAgainstCredit,
    String? createdBy,
    DatabaseExecutor? executor,
  }) async {
    if (refundAmount == 0) return const [];

    return _run(executor, (db) async {
      final revenueAccount = await requireAccountByCode(salesRevenueAccountCode, executor: db);
      final refundAccount = await requireAccountByCode(
        refundedAgainstCredit ? receivableAccountCode : cashAccountCode,
        executor: db,
      );

      return postCompoundEntry(
        entryDate: returnDate,
        description: saleId == null ? 'Sales return $returnId' : 'Sales return $returnId against sale $saleId',
        referenceType: returnReferenceType,
        referenceId: returnId,
        accounts: {
          revenueAccount.id: refundAmount, // debit: revenue reduced
          refundAccount.id: -refundAmount, // credit: money/receivable given back
        },
        createdBy: createdBy,
        executor: db,
      );
    });
  }

  static const String bankAccountCode = '1010';
  static const String gatewayPaymentReferenceType = 'GatewayPayment';

  /// The ledger side of a payment collected through a payment gateway.
  ///
  /// **This posts no revenue.** The sale's own entries (see [postSaleEntries])
  /// already credited Sales Revenue for the whole bill when the sale
  /// completed; a gateway payment is not a second sale, it is the shop
  /// learning *how* that amount was settled. Posting revenue again here would
  /// double the day's takings — which is why this only ever moves the same
  /// money between two asset accounts.
  ///
  /// What moves depends on what the sale recorded at the till:
  /// - [settlesReceivable] false — the sale counted this amount as cash in
  ///   hand (account `1000`), because that is what `postSaleEntries` debits
  ///   for anything not left owing. The money is really in the bank, so debit
  ///   Bank `1010` and credit Cash `1000`. Net effect on total assets: nil,
  ///   which is correct — nothing new was earned, the cash was only ever in
  ///   the wrong account.
  /// - [settlesReceivable] true — the sale left the amount owing (account
  ///   `1100`) and the customer has now paid it. Debit Bank `1010`, credit
  ///   Accounts Receivable `1100`.
  ///
  /// Returns an empty list for a zero-value payment, matching
  /// [postSaleEntries] — there is nothing to record and it is not an error.
  Future<List<GLEntry>> postGatewayPaymentEntries({
    required String paymentId,
    required DateTime paymentDate,
    required double amount,
    bool settlesReceivable = false,
    String? saleId,
    String? description,
    String? createdBy,
    DatabaseExecutor? executor,
  }) async {
    if (amount == 0) return const [];
    if (amount < 0) {
      throw UnbalancedEntry(
        'A gateway payment cannot be negative (got ${amount.toStringAsFixed(2)}). '
        'Use reverseByReference to undo a payment.',
      );
    }

    return _run(executor, (db) async {
      final bank = await requireAccountByCode(bankAccountCode, executor: db);
      final settled = await requireAccountByCode(
        settlesReceivable ? receivableAccountCode : cashAccountCode,
        executor: db,
      );

      return postCompoundEntry(
        entryDate: paymentDate,
        description: description ??
            (saleId == null
                ? 'Gateway payment $paymentId'
                : 'Gateway payment $paymentId for sale $saleId'),
        referenceType: gatewayPaymentReferenceType,
        referenceId: paymentId,
        accounts: {
          bank.id: amount, // debit: money is in the bank
          settled.id: -amount, // credit: cash at till / receivable cleared
        },
        createdBy: createdBy,
        executor: db,
      );
    });
  }

  // --------------------------------------------------------- account lookup

  /// Resolves a chart-of-accounts code (e.g. '1000') to its account.
  /// The sale/purchase integrations post against codes, not ids.
  Future<ChartOfAccount> requireAccountByCode(String code, {DatabaseExecutor? executor}) async {
    final account = await _glRepository.getAccountByCode(code, executor: executor);
    if (account == null) {
      throw AccountNotFound('No account with code $code — the default chart of accounts may not be seeded.');
    }
    return account;
  }
}

final glServiceProvider = Provider<GLService>((ref) {
  return GLService();
});
