import '../../domain/entities/student.dart';

/// The data-layer version of [Student].
///
/// It EXTENDS the entity rather than duplicating it, so anything that
/// needs a Student accepts a StudentModel without conversion, while all
/// the JSON knowledge stays down here in the data layer.
class StudentModel extends Student {
  const StudentModel({
    required super.studentId,
    required super.regNo,
    required super.fullName,
    required super.email,
    required super.age,
    required super.city,
    required super.accountStatus,
    required super.school,
    required super.creditBalance,
    required super.roleInSystem,
  });

  /// Field names match the Java record components, which Jackson
  /// serialises as camelCase.
  factory StudentModel.fromJson(Map<String, dynamic> json) => StudentModel(
        studentId: _int(json['studentId']),
        regNo: json['regNo']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        age: _int(json['age']),
        city: json['city']?.toString() ?? '',
        accountStatus: json['accountStatus']?.toString() ?? 'ACTIVE',
        school: json['school']?.toString() ?? '',
        creditBalance: _double(json['creditBalance']),
        roleInSystem: json['roleInSystem']?.toString() ?? 'NEITHER YET',
      );

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'regNo': regNo,
        'fullName': fullName,
        'email': email,
        'city': city,
        'accountStatus': accountStatus,
        'school': school,
        'creditBalance': creditBalance,
        'roleInSystem': roleInSystem,
      };

  /// Oracle NUMBER can arrive as an int, a double or a string depending
  /// on scale, so every numeric field goes through these rather than a
  /// bare cast. A single `as double` would throw on a whole number.
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
