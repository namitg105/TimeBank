import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/student.dart';
import '../repositories/student_repository.dart';

/// One class per action the app can perform on students.
///
/// Splitting them up looks verbose for a method that only forwards a
/// call, and for [GetStudents] it genuinely is. The value shows up the
/// moment a rule appears: [RegisterStudent] below validates before it
/// touches the network, and that rule now lives in exactly one place
/// instead of being copied into every screen that registers someone.

final class GetStudents implements UseCase<List<Student>, NoParams> {
  final StudentRepository repository;
  const GetStudents(this.repository);

  @override
  Future<Either<Failure, List<Student>>> call(NoParams params) =>
      repository.getAll();
}

final class SearchStudents implements UseCase<List<Student>, String> {
  final StudentRepository repository;
  const SearchStudents(this.repository);

  @override
  Future<Either<Failure, List<Student>>> call(String query) =>
      repository.search(query);
}

/// The balance is a DERIVED value: nothing stores it, so every call
/// re-sums the student's ledger rows.
final class GetBalance implements UseCase<double, int> {
  final StudentRepository repository;
  const GetBalance(this.repository);

  @override
  Future<Either<Failure, double>> call(int studentId) =>
      repository.balanceOf(studentId);
}

final class RegisterStudent
    implements UseCase<Student, RegisterStudentParams> {
  final StudentRepository repository;
  const RegisterStudent(this.repository);

  @override
  Future<Either<Failure, Student>> call(RegisterStudentParams p) async {
    // Validate here, not in the widget. A second screen that registers
    // someone gets these rules for free.
    if (p.regNo.trim().isEmpty) {
      return const Left(ValidationFailure('Registration number is required.'));
    }
    if (p.firstName.trim().isEmpty || p.lastName.trim().isEmpty) {
      return const Left(ValidationFailure('Both names are required.'));
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(p.email.trim())) {
      return const Left(ValidationFailure('That email address is not valid.'));
    }
    final age = DateTime.now().difference(p.dob).inDays / 365.25;
    if (age < 15 || age > 80) {
      return const Left(
          ValidationFailure('Check the date of birth — that age looks wrong.'));
    }
    if (p.phone != null &&
        p.phone!.isNotEmpty &&
        !RegExp(r'^[0-9]{10}$').hasMatch(p.phone!)) {
      return const Left(ValidationFailure('A phone number must be 10 digits.'));
    }

    return repository.register(
      regNo: p.regNo.trim(),
      firstName: p.firstName.trim(),
      lastName: p.lastName.trim(),
      email: p.email.trim(),
      dob: p.dob,
      deptId: p.deptId,
      block: p.block,
      roomNo: p.roomNo,
      city: p.city,
      phone: p.phone,
    );
  }
}

final class RegisterStudentParams extends Equatable {
  final String regNo;
  final String firstName;
  final String lastName;
  final String email;
  final DateTime dob;
  final int deptId;
  final String? block;
  final String? roomNo;
  final String? city;
  final String? phone;

  const RegisterStudentParams({
    required this.regNo,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.dob,
    required this.deptId,
    this.block,
    this.roomNo,
    this.city,
    this.phone,
  });

  @override
  List<Object?> get props => [regNo, email, deptId];
}

final class DeactivateStudent implements UseCase<String, int> {
  final StudentRepository repository;
  const DeactivateStudent(this.repository);

  @override
  Future<Either<Failure, String>> call(int studentId) =>
      repository.deactivate(studentId);
}
