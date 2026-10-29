import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/audit.dart';
import '../entities/ledger_entry.dart';
import '../repositories/ledger_repository.dart';

final class GetPassbook implements UseCase<List<LedgerEntry>, int> {
  final LedgerRepository repository;
  const GetPassbook(this.repository);

  @override
  Future<Either<Failure, List<LedgerEntry>>> call(int studentId) =>
      repository.passbook(studentId);
}

/// Runs the closed-economy check.
final class RunAudit implements UseCase<Audit, NoParams> {
  final LedgerRepository repository;
  const RunAudit(this.repository);

  @override
  Future<Either<Failure, Audit>> call(NoParams params) => repository.audit();
}

/// Posts a manual credit or penalty.
///
/// A PENALTY is the only way credits ever leave the economy, so the sign
/// is checked here before the request is sent: a PENALTY of +5 would
/// invent credits from nothing, and the database CHECK constraint would
/// reject it anyway. Catching it early gives a better message.
final class PostAdjustment implements UseCase<int, AdjustmentParams> {
  final LedgerRepository repository;
  const PostAdjustment(this.repository);

  @override
  Future<Either<Failure, int>> call(AdjustmentParams p) async {
    if (p.amount == 0) {
      return const Left(ValidationFailure('The amount cannot be zero.'));
    }
    if (p.type == 'GRANT' && p.amount < 0) {
      return const Left(ValidationFailure('A grant has to be positive.'));
    }
    if (p.type == 'PENALTY' && p.amount > 0) {
      return const Left(ValidationFailure('A penalty has to be negative.'));
    }
    if (p.remarks.trim().isEmpty) {
      return const Left(
          ValidationFailure('Give a reason — this row is permanent.'));
    }

    return repository.postAdjustment(
      studentId: p.studentId,
      type: p.type,
      amount: p.amount,
      remarks: p.remarks.trim(),
    );
  }
}

final class AdjustmentParams extends Equatable {
  final int studentId;
  final String type;
  final double amount;
  final String remarks;

  const AdjustmentParams({
    required this.studentId,
    required this.type,
    required this.amount,
    required this.remarks,
  });

  @override
  List<Object?> get props => [studentId, type, amount];
}

final class GetLeaderboard implements UseCase<List<String>, NoParams> {
  final LedgerRepository repository;
  const GetLeaderboard(this.repository);

  @override
  Future<Either<Failure, List<String>>> call(NoParams params) =>
      repository.leaderboard();
}

final class GetCollusionReport implements UseCase<List<String>, NoParams> {
  final LedgerRepository repository;
  const GetCollusionReport(this.repository);

  @override
  Future<Either<Failure, List<String>>> call(NoParams params) =>
      repository.collusionReport();
}
