import '../../domain/entities/audit.dart';
import '../../domain/entities/ledger_entry.dart';

class LedgerEntryModel extends LedgerEntry {
  const LedgerEntryModel({
    required super.txnId,
    required super.studentName,
    required super.txnType,
    required super.amount,
    required super.balanceAfter,
    required super.postedAt,
    required super.bookingId,
    required super.remarks,
  });

  factory LedgerEntryModel.fromJson(Map<String, dynamic> json) =>
      LedgerEntryModel(
        txnId: _int(json['txnId']),
        studentName: json['studentName']?.toString() ?? '',
        txnType: json['txnType']?.toString() ?? '',
        amount: _double(json['amount']),
        balanceAfter: _double(json['balanceAfter']),
        postedAt: DateTime.tryParse(json['postedAt']?.toString() ?? '') ??
            DateTime.now(),
        // Stays null on purpose. GRANT and PENALTY rows have no booking,
        // and turning that into 0 would claim booking #0 caused them.
        bookingId: json['bookingId'] == null ? null : _int(json['bookingId']),
        remarks: json['remarks']?.toString() ?? '',
      );

  static double _double(dynamic v) => switch (v) {
        null => 0.0,
        num n => n.toDouble(),
        String s => double.tryParse(s) ?? 0.0,
        _ => 0.0,
      };

  static int _int(dynamic v) => switch (v) {
        null => 0,
        num n => n.toInt(),
        String s => int.tryParse(s) ?? 0,
        _ => 0,
      };
}

class AuditModel extends Audit {
  const AuditModel({
    required super.balances,
    required super.escrow,
    required super.grantsLessPenalties,
    required super.drift,
    required super.balanced,
  });

  factory AuditModel.fromJson(Map<String, dynamic> json) => AuditModel(
        balances: LedgerEntryModel._double(json['balances']),
        escrow: LedgerEntryModel._double(json['escrow']),
        grantsLessPenalties:
            LedgerEntryModel._double(json['grantsLessPenalties']),
        drift: LedgerEntryModel._double(json['drift']),
        balanced: json['balanced'] == true,
      );
}
