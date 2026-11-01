import 'package:equatable/equatable.dart';

/// One immutable row of the credit ledger.
///
/// The ledger is append-only and a database trigger enforces it, so
/// there is no edit or delete anywhere in this feature. A mistake is
/// corrected by posting a compensating row, exactly like real
/// accounting. If rows could be edited, the audit would prove nothing.
class LedgerEntry extends Equatable {
  final int txnId;
  final String studentName;

  /// GRANT, HOLD, RELEASE, TRANSFER or PENALTY.
  final String txnType;

  /// Signed: positive is credits in, negative is credits out. Using a
  /// sign rather than a separate direction flag is what makes a balance
  /// a plain SUM instead of a CASE expression.
  final double amount;

  /// The balance immediately after this row, frozen for ever.
  ///
  /// Strictly this is redundant -- it could be recomputed -- but it is
  /// kept deliberately: each snapshot must equal the previous one plus
  /// this amount, so a broken chain reveals tampering.
  final double balanceAfter;

  final DateTime postedAt;

  /// Null for GRANT and PENALTY, which have no originating session.
  /// This is the only nullable foreign key in the whole database, and it
  /// is the partial participation of CREDIT_TXN in "generates".
  final int? bookingId;

  final String remarks;

  const LedgerEntry({
    required this.txnId,
    required this.studentName,
    required this.txnType,
    required this.amount,
    required this.balanceAfter,
    required this.postedAt,
    required this.bookingId,
    required this.remarks,
  });

  bool get isSystemCredit => bookingId == null;
  bool get isIncoming => amount > 0;

  String get origin =>
      bookingId == null ? 'System credit' : 'Session #$bookingId';

  /// Plain-language explanation of what this row did.
  String get explanation => switch (txnType) {
        'GRANT'    => 'Credits added to the account',
        'HOLD'     => 'Credits locked in escrow for a booking',
        'RELEASE'  => 'Escrow returned after a cancellation',
        'TRANSFER' => 'Payment for a completed session',
        'PENALTY'  => 'Deduction after a dispute',
        _          => remarks,
      };

  @override
  List<Object?> get props => [txnId, amount, balanceAfter];
}
