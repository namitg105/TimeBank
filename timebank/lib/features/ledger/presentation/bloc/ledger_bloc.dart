import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../../domain/entities/audit.dart';
import '../../domain/entities/ledger_entry.dart';
import '../../domain/usecases/ledger_usecases.dart';

// ----------------------------------------------------------------- events

sealed class LedgerEvent extends Equatable {
  const LedgerEvent();
  @override
  List<Object?> get props => [];
}

final class PassbookRequested extends LedgerEvent {
  final int studentId;
  const PassbookRequested(this.studentId);
  @override
  List<Object?> get props => [studentId];
}

final class AuditRequested extends LedgerEvent {
  const AuditRequested();
}

final class AdjustmentPosted extends LedgerEvent {
  final AdjustmentParams params;
  const AdjustmentPosted(this.params);
  @override
  List<Object?> get props => [params];
}

final class ReportsRequested extends LedgerEvent {
  const ReportsRequested();
}

// ----------------------------------------------------------------- states

sealed class LedgerState extends Equatable {
  const LedgerState();
  @override
  List<Object?> get props => [];
}

final class LedgerInitial extends LedgerState {
  const LedgerInitial();
}

final class LedgerLoading extends LedgerState {
  const LedgerLoading();
}

final class PassbookLoaded extends LedgerState {
  final List<LedgerEntry> entries;
  final int studentId;
  const PassbookLoaded(this.entries, this.studentId);

  /// The balance is the sum of the rows -- it is not stored anywhere.
  double get balance =>
      entries.fold<double>(0, (sum, e) => sum + e.amount);

  @override
  List<Object?> get props => [entries, studentId];
}

final class AuditLoaded extends LedgerState {
  final Audit audit;
  const AuditLoaded(this.audit);
  @override
  List<Object?> get props => [audit];
}

final class ReportsLoaded extends LedgerState {
  final List<String> leaderboard;
  final List<String> collusion;
  const ReportsLoaded(this.leaderboard, this.collusion);
  @override
  List<Object?> get props => [leaderboard, collusion];
}

final class LedgerActionSuccess extends LedgerState {
  final String message;
  const LedgerActionSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

final class LedgerFailure extends LedgerState {
  final String message;
  final bool isRule;
  const LedgerFailure(this.message, {this.isRule = false});
  @override
  List<Object?> get props => [message, isRule];
}

// ------------------------------------------------------------------ bloc

class LedgerBloc extends Bloc<LedgerEvent, LedgerState> {
  final GetPassbook getPassbook;
  final RunAudit runAudit;
  final PostAdjustment postAdjustment;
  final GetLeaderboard getLeaderboard;
  final GetCollusionReport getCollusionReport;

  LedgerBloc({
    required this.getPassbook,
    required this.runAudit,
    required this.postAdjustment,
    required this.getLeaderboard,
    required this.getCollusionReport,
  }) : super(const LedgerInitial()) {
    on<PassbookRequested>(_onPassbook);
    on<AuditRequested>(_onAudit);
    on<AdjustmentPosted>(_onAdjustment);
    on<ReportsRequested>(_onReports);
  }

  Future<void> _onPassbook(
      PassbookRequested event, Emitter<LedgerState> emit) async {
    emit(const LedgerLoading());
    final result = await getPassbook(event.studentId);
    emit(result.fold(
      (f) => LedgerFailure(f.message, isRule: _isRule(f)),
      (entries) => PassbookLoaded(entries, event.studentId),
    ));
  }

  Future<void> _onAudit(
      AuditRequested event, Emitter<LedgerState> emit) async {
    emit(const LedgerLoading());
    final result = await runAudit(const NoParams());
    emit(result.fold(
      (f) => LedgerFailure(f.message, isRule: _isRule(f)),
      (audit) => AuditLoaded(audit),
    ));
  }

  Future<void> _onAdjustment(
      AdjustmentPosted event, Emitter<LedgerState> emit) async {
    final result = await postAdjustment(event.params);
    await result.fold(
      (f) async => emit(LedgerFailure(f.message, isRule: _isRule(f))),
      (txnId) async {
        emit(LedgerActionSuccess('Posted as transaction $txnId.'));
        add(PassbookRequested(event.params.studentId));
      },
    );
  }

  Future<void> _onReports(
      ReportsRequested event, Emitter<LedgerState> emit) async {
    emit(const LedgerLoading());

    final board = await getLeaderboard(const NoParams());
    final collusion = await getCollusionReport(const NoParams());

    if (board.isLeft()) {
      final f = board.getLeft().toNullable()!;
      emit(LedgerFailure(f.message, isRule: _isRule(f)));
      return;
    }

    emit(ReportsLoaded(
      board.getRight().toNullable() ?? const [],
      collusion.getRight().toNullable() ?? const [],
    ));
  }

  static bool _isRule(Failure f) => switch (f) {
        RuleFailure() || ValidationFailure() => true,
        NetworkFailure() || ServerFailure() => false,
      };
}
