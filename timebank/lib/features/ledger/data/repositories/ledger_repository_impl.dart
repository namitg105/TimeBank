import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/audit.dart';
import '../../domain/entities/ledger_entry.dart';
import '../../domain/repositories/ledger_repository.dart';
import '../datasources/ledger_remote_datasource.dart';
import '../../../../core/error/guard.dart';

class LedgerRepositoryImpl implements LedgerRepository {
  final LedgerRemoteDataSource remote;
  const LedgerRepositoryImpl(this.remote);

  @override
  Future<Either<Failure, List<LedgerEntry>>> passbook(int studentId) =>
      guard(() => remote.passbook(studentId));

  @override
  Future<Either<Failure, Audit>> audit() => guard(() => remote.audit());

  @override
  Future<Either<Failure, int>> postAdjustment({
    required int studentId,
    required String type,
    required double amount,
    required String remarks,
  }) =>
      guard(() => remote.postAdjustment({
            'studentId': studentId,
            'type': type,
            'amount': amount,
            'remarks': remarks,
          }));

  @override
  Future<Either<Failure, List<String>>> leaderboard() =>
      guard(() => remote.leaderboard());

  @override
  Future<Either<Failure, List<String>>> collusionReport() =>
      guard(() => remote.collusion());

}
