import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/audit.dart';
import '../entities/ledger_entry.dart';

/// The ledger, read-only apart from posting new rows.
///
/// There is deliberately no update and no delete. CREDIT_TXN is
/// append-only and a trigger enforces it in the database, so offering
/// those methods here would only produce errors at runtime.
abstract interface class LedgerRepository {
  Future<Either<Failure, List<LedgerEntry>>> passbook(int studentId);

  Future<Either<Failure, Audit>> audit();

  Future<Either<Failure, int>> postAdjustment({
    required int studentId,
    required String type,       // GRANT or PENALTY
    required double amount,
    required String remarks,
  });

  Future<Either<Failure, List<String>>> leaderboard();

  Future<Either<Failure, List<String>>> collusionReport();
}
