import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/booking.dart';
import '../repositories/booking_repository.dart';

final class GetBookings implements UseCase<List<Booking>, String?> {
  final BookingRepository repository;
  const GetBookings(this.repository);

  @override
  Future<Either<Failure, List<Booking>>> call(String? status) =>
      repository.getAll(status: status);
}

final class GetStudentBookings implements UseCase<List<Booking>, int> {
  final BookingRepository repository;
  const GetStudentBookings(this.repository);

  @override
  Future<Either<Failure, List<Booking>>> call(int studentId) =>
      repository.forStudent(studentId);
}

/// Books a session.
///
/// Only the checks that can be made WITHOUT the database live here.
/// Slot availability, the overdraft floor and the collusion cap are all
/// decided by Oracle under a row lock, because checking them from the
/// app would be a race: two tutees could both be told the slot is free
/// before either had written anything.
final class BookSession implements UseCase<(int, String), BookSessionParams> {
  final BookingRepository repository;
  const BookSession(this.repository);

  @override
  Future<Either<Failure, (int, String)>> call(BookSessionParams p) async {
    if (p.tutorId == p.tuteeId) {
      return const Left(
          ValidationFailure('You cannot book a session with yourself.'));
    }
    if (![0.5, 1.0, 1.5, 2.0].contains(p.durationHours)) {
      return const Left(
          ValidationFailure('Duration must be 0.5, 1, 1.5 or 2 hours.'));
    }
    if (p.startTime < 0 || p.startTime + p.durationHours > 24) {
      return const Left(ValidationFailure('That time runs past midnight.'));
    }

    return repository.book(
      tuteeId: p.tuteeId,
      tutorId: p.tutorId,
      subjectId: p.subjectId,
      slotNo: p.slotNo,
      schedDate: p.schedDate,
      startTime: p.startTime,
      durationHours: p.durationHours,
      mode: p.mode,
      venue: p.venue,
      intent: p.intent,
      studentId: p.studentId,
    );
  }
}

final class BookSessionParams extends Equatable {
  final int tuteeId;
  final int tutorId;
  final int subjectId;
  final int slotNo;
  final DateTime schedDate;
  final double startTime;
  final double durationHours;
  final String mode;
  final String venue;

  /// 'LEARN' or 'TEACH', or null to skip enrolment entirely.
  ///
  /// Set from the role picker on the booking form. When present the
  /// student is added to TUTEE or TUTOR first if they are not already
  /// in it -- and never removed from the other one, because the
  /// specialization is overlapping.
  final String? intent;

  /// The student doing the booking, whose role may need creating.
  final int? studentId;

  const BookSessionParams({
    required this.tuteeId,
    required this.tutorId,
    required this.subjectId,
    required this.slotNo,
    required this.schedDate,
    required this.startTime,
    required this.durationHours,
    required this.mode,
    required this.venue,
    this.intent,
    this.studentId,
  });

  @override
  List<Object?> get props =>
      [tuteeId, tutorId, subjectId, slotNo, schedDate, startTime, intent];
}

/// The tutor enters the code the tutee was given.
final class CheckInSession implements UseCase<String, (int, String)> {
  final BookingRepository repository;
  const CheckInSession(this.repository);

  @override
  Future<Either<Failure, String>> call((int, String) params) {
    final (bookingId, code) = params;
    if (code.trim().length != 8) {
      return Future.value(
          const Left(ValidationFailure('A session code is 8 characters.')));
    }
    return repository.checkIn(bookingId, code.trim().toUpperCase());
  }
}

final class ConfirmSession implements UseCase<String, (int, String)> {
  final BookingRepository repository;
  const ConfirmSession(this.repository);

  @override
  Future<Either<Failure, String>> call((int, String) params) {
    final (bookingId, role) = params;
    return repository.confirm(bookingId, role.toUpperCase());
  }
}

final class CancelSession implements UseCase<String, (int, String)> {
  final BookingRepository repository;
  const CancelSession(this.repository);

  @override
  Future<Either<Failure, String>> call((int, String) params) {
    final (bookingId, role) = params;
    return repository.cancel(bookingId, role.toUpperCase());
  }
}
