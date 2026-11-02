import 'package:fpdart/fpdart.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/student.dart';
import '../../domain/repositories/student_repository.dart';
import '../datasources/student_remote_datasource.dart';
import '../../../../core/error/guard.dart';

/// Where exceptions stop and [Failure]s begin.
///
/// This is the boundary of the data layer. Everything above it — use
/// cases, Blocs, widgets — deals only in `Either<Failure, T>` and never
/// sees a thrown exception, a status code or an Oracle error number.
///
/// The important translation is [ServerException.isBusinessRule]. The
/// API returns 409 CONFLICT when a database rule refused the request,
/// and those messages were written inside Oracle triggers for a person
/// to read: "Overdraft limit reached", "That slot is already booked on
/// 03-NOV-2026". They are passed through untouched, because no wording
/// this app could invent would be more accurate.
class StudentRepositoryImpl implements StudentRepository {
  final StudentRemoteDataSource remote;
  const StudentRepositoryImpl(this.remote);

  @override
  Future<Either<Failure, List<Student>>> getAll() =>
      guard(() => remote.getAll());

  @override
  Future<Either<Failure, List<Student>>> search(String query) =>
      guard(() => remote.search(query));

  @override
  Future<Either<Failure, double>> balanceOf(int studentId) =>
      guard(() => remote.balanceOf(studentId));

  @override
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
  }) =>
      guard(() => remote.register({
            'regNo': regNo,
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            // The Java side parses this with LocalDate.parse, which wants
            // exactly yyyy-MM-dd.
            'dob': _isoDate(dob),
            'deptId': deptId,
            'block': block,
            'roomNo': roomNo,
            'city': city,
            'phone': phone,
          }));

  @override
  Future<Either<Failure, String>> deactivate(int studentId) =>
      guard(() => remote.deactivate(studentId));

  @override
  Future<Either<Failure, String>> reactivate(int studentId) =>
      guard(() => remote.reactivate(studentId));

  // -------------------------------------------------------------------

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
