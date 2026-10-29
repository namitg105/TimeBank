import 'package:fpdart/fpdart.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/student.dart';
import '../../domain/repositories/student_repository.dart';
import '../datasources/student_remote_datasource.dart';

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
      _guard(() => remote.getAll());

  @override
  Future<Either<Failure, List<Student>>> search(String query) =>
      _guard(() => remote.search(query));

  @override
  Future<Either<Failure, double>> balanceOf(int studentId) =>
      _guard(() => remote.balanceOf(studentId));

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
      _guard(() => remote.register({
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
      _guard(() => remote.deactivate(studentId));

  // -------------------------------------------------------------------

  /// Runs a data-source call and converts anything thrown into a Failure.
  ///
  /// Writing it once here means no repository method needs its own
  /// try/catch, and none of them can accidentally let an exception
  /// escape into the domain layer.
  Future<Either<Failure, T>> _guard<T>(Future<T> Function() call) async {
    try {
      return Right(await call());
    } on ServerException catch (e) {
      return Left(e.isBusinessRule
          ? RuleFailure(e.message, oracleCode: e.oracleCode)
          : ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
