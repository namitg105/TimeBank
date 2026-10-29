import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/booking.dart';

/// Everything the app can do with sessions.
///
/// There is no "check if the slot is free" method, and that is
/// intentional. Availability has to be decided under a database row
/// lock, inside the same transaction that writes the booking. Asking
/// first and inserting afterwards is exactly the race condition the
/// lock exists to prevent -- two tutees would both be told "free".
/// So [book] either succeeds or returns a RuleFailure explaining why.
abstract interface class BookingRepository {
  Future<Either<Failure, List<Booking>>> getAll({String? status});

  Future<Either<Failure, List<Booking>>> forStudent(int studentId);

  /// Returns the new booking id and the session code.
  ///
  /// The code goes to the TUTEE only. The tutor types it in at the start
  /// of the session, which is what proves the tutee actually attended.
  Future<Either<Failure, (int bookingId, String sessionCode)>> book({
    required int tuteeId,
    required int tutorId,
    required int subjectId,
    required int slotNo,
    required DateTime schedDate,
    required double startTime,
    required double durationHours,
    required String mode,
    required String venue,
  });

  Future<Either<Failure, String>> checkIn(int bookingId, String sessionCode);

  /// One side confirms. Credits move only when both have.
  Future<Either<Failure, String>> confirm(int bookingId, String role);

  Future<Either<Failure, String>> cancel(int bookingId, String byRole);
}
