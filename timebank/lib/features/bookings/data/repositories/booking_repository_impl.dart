import 'package:fpdart/fpdart.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/booking.dart';
import '../../domain/repositories/booking_repository.dart';
import '../datasources/booking_remote_datasource.dart';

class BookingRepositoryImpl implements BookingRepository {
  final BookingRemoteDataSource remote;
  const BookingRepositoryImpl(this.remote);

  @override
  Future<Either<Failure, List<Booking>>> getAll({String? status}) =>
      _guard(() => remote.getAll(status: status));

  @override
  Future<Either<Failure, List<Booking>>> forStudent(int studentId) =>
      _guard(() => remote.forStudent(studentId));

  @override
  Future<Either<Failure, (int, String)>> book({
    required int tuteeId,
    required int tutorId,
    required int subjectId,
    required int slotNo,
    required DateTime schedDate,
    required double startTime,
    required double durationHours,
    required String mode,
    required String venue,
  }) =>
      _guard(() => remote.book({
            'tuteeId': tuteeId,
            'tutorId': tutorId,
            'subjectId': subjectId,
            'slotNo': slotNo,
            'schedDate': _isoDate(schedDate),
            'startTime': startTime,
            'durationHours': durationHours,
            'mode': mode,
            'venue': venue,
          }));

  @override
  Future<Either<Failure, String>> checkIn(int bookingId, String sessionCode) =>
      _guard(() => remote.checkIn(bookingId, sessionCode));

  @override
  Future<Either<Failure, String>> confirm(int bookingId, String role) =>
      _guard(() => remote.confirm(bookingId, role));

  @override
  Future<Either<Failure, String>> cancel(int bookingId, String byRole) =>
      _guard(() => remote.cancel(bookingId, byRole));

  // Most failures from this feature are RuleFailures, because almost
  // every booking rule lives in a database trigger: the slot is taken,
  // the session has not ended yet, nobody checked in, the pair has hit
  // its weekly cap. Those messages go straight to the user.
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
