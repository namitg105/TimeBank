import 'package:equatable/equatable.dart';

/// A student, as the business understands one.
///
/// Pure Dart: no JSON, no HTTP, no database. That is deliberate. If the
/// backend moved from Oracle to something else tomorrow, this file would
/// not change, and neither would any use case that depends on it.
///
/// [creditBalance] and [age] are DERIVED values. The ER diagram draws
/// them as dashed ovals and the schema does not store them -- they are
/// computed from the ledger and the date of birth every time they are
/// asked for. They arrive here already computed by the database view.
class Student extends Equatable {
  final int studentId;
  final String regNo;
  final String fullName;
  final String email;
  final int age;
  final String city;
  final String accountStatus;
  final String school;
  final double creditBalance;

  /// TUTOR ONLY, TUTEE ONLY, BOTH, or NEITHER YET.
  ///
  /// BOTH is only possible because the specialization in the ER diagram
  /// is OVERLAPPING -- one person can teach and be taught. NEITHER YET
  /// is what makes it PARTIAL: a student who has just registered belongs
  /// to no subclass at all.
  final String roleInSystem;

  const Student({
    required this.studentId,
    required this.regNo,
    required this.fullName,
    required this.email,
    required this.age,
    required this.city,
    required this.accountStatus,
    required this.school,
    required this.creditBalance,
    required this.roleInSystem,
  });

  bool get isTutor => roleInSystem == 'TUTOR ONLY' || roleInSystem == 'BOTH';
  bool get isTutee => roleInSystem == 'TUTEE ONLY' || roleInSystem == 'BOTH';
  bool get isActive => accountStatus == 'ACTIVE';

  /// Running low enough to be worth nudging into tutoring.
  bool get isLowOnCredits => creditBalance <= 0.5;

  String get initials {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  List<Object?> get props => [studentId, regNo, creditBalance, roleInSystem];
}
