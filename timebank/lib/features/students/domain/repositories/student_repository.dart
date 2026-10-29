import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/student.dart';

/// The contract the domain layer depends on.
///
/// Note the direction: this interface lives in DOMAIN, but it is
/// implemented in DATA. That inversion is the whole point of clean
/// architecture -- the inner layer declares what it needs, and the outer
/// layer supplies it. The domain never imports dio, never imports a
/// model with fromJson, and never learns that Oracle exists.
///
/// Every method returns Either<Failure, T> rather than throwing, so a
/// caller cannot forget to deal with the error case: the type system
/// will not let it compile.
abstract interface class StudentRepository {
  Future<Either<Failure, List<Student>>> getAll();

  Future<Either<Failure, List<Student>>> search(String query);

  Future<Either<Failure, double>> balanceOf(int studentId);

  Future<Either<Failure, Student>> register({
    required String regNo,
    required String firstName,
    required String lastName,
    required String email,
    required DateTime dob,
    required int deptId,
    String? block,
    String? roomNo,
    String? city,
    String? phone,
  });

  /// Closes an account.
  ///
  /// This is a soft delete. A student with bookings or ledger rows can
  /// never be physically removed -- those foreign keys have no ON DELETE
  /// clause, so the database refuses in order to keep history intact.
  Future<Either<Failure, String>> deactivate(int studentId);
}
