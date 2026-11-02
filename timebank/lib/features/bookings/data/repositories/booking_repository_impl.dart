import 'package:fpdart/fpdart.dart';
import 'package:timebank/core/error/failure.dart';
import '../../domain/entities/booking.dart';
import '../../domain/repositories/booking_repository.dart';
import '../datasources/booking_remote_datasource.dart';
import '../../../../core/error/guard.dart';

class BookingRepositoryImpl implements BookingRepository {
  final BookingRemoteDataSource remote;
  const BookingRepositoryImpl(this.remote);

  @override
  Future<Either<Failure, List<Booking>>> getAll({String? status}) =>
      guard(() => remote.getAll(status: status));

  @override
  Future<Either<Failure, List<Booking>>> forStudent(int studentId) =>
      guard(() => remote.forStudent(studentId));

  @override
  Future<Either<Failure, (int, String)>> book({
    required String tuteeRef,
    required String tutorRef,
    required int subjectId,
    required int slotNo,
    required DateTime schedDate,
    required double startTime,
    required double durationHours,
    required String mode,
    required String venue,
    String? intent,
    String? studentRef,
  }) {
    // No intent: the plain endpoint, which assumes both people are
    // already in the right subclass tables.
    if (intent == null || studentRef == null) {
      return guard(() => remote.book({
            'tuteeId': tuteeRef,
            'tutorId': tutorRef,
            'subjectId': subjectId,
            'slotNo': slotNo,
            'schedDate': _isoDate(schedDate),
            'startTime': startTime,
            'durationHours': durationHours,
            'mode': mode,
            'venue': venue,
          }));
    }

    // With an intent, the API enrols the student into TUTOR or TUTEE
    // first if they are not already there, then books. The counterpart
    // is whoever is on the other side of the session.
    final counterpartRef = intent == 'LEARN' ? tutorRef : tuteeRef;

    return guard(() async {
      final (id, code, _) = await remote.bookGuided({
        'studentId': studentRef,
        'intent': intent,
        'counterpartId': counterpartRef,
        'subjectId': subjectId,
        'slotNo': slotNo,
        'schedDate': _isoDate(schedDate),
        'startTime': startTime,
        'durationHours': durationHours,
        'mode': mode,
        'venue': venue,
      });
      return (id, code);
    });
  }

  @override
  Future<Either<Failure, String>> checkIn(int bookingId, String sessionCode) =>
      guard(() => remote.checkIn(bookingId, sessionCode));

  @override
  Future<Either<Failure, String>> confirm(int bookingId, String role) =>
      guard(() => remote.confirm(bookingId, role));

  @override
  Future<Either<Failure, String>> cancel(int bookingId, String byRole) =>
      guard(() => remote.cancel(bookingId, byRole));

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
