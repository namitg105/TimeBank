import 'package:equatable/equatable.dart';

/// One tutoring session.
///
/// In the ER diagram Booking is a STRONG entity, not a relationship,
/// because it has its own identity and lifecycle and three other things
/// depend on it: feedback, disputes and ledger rows.
class Booking extends Equatable {
  final int bookingId;
  final String tuteeName;
  final String tutorName;
  final String subjectCode;
  final DateTime schedDate;

  /// A decimal hour on a 24h clock: 16.5 means 16:30.
  final double startTime;
  final double durationHours;
  final String mode;
  final String venue;
  final String status;

  /// Credits locked in escrow. They left the tutee at booking time and
  /// reach the tutor only when both sides confirm.
  final double creditsHeld;

  /// "Y/N" -- tutor first, then tutee.
  final String confirmations;

  /// True once the tutor has entered the tutee's session code, which is
  /// what proves the tutee actually turned up.
  final bool checkedIn;

  const Booking({
    required this.bookingId,
    required this.tuteeName,
    required this.tutorName,
    required this.subjectCode,
    required this.schedDate,
    required this.startTime,
    required this.durationHours,
    required this.mode,
    required this.venue,
    required this.status,
    required this.creditsHeld,
    required this.confirmations,
    required this.checkedIn,
  });

  bool get tutorConfirmed => confirmations.startsWith('Y');
  bool get tuteeConfirmed => confirmations.endsWith('Y');
  bool get isUpcoming => status == 'REQUESTED' || status == 'CONFIRMED';
  bool get isFinished => status == 'COMPLETED';

  /// 16.5 -> "16:30". The column stores a number, not a timestamp,
  /// so the clock format is reconstructed here.
  String get clockTime {
    final hour = startTime.floor();
    final minutes = ((startTime - hour) * 60).round();
    return '${hour.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  String get endClockTime {
    final end = startTime + durationHours;
    final hour = end.floor();
    final minutes = ((end - hour) * 60).round();
    return '${hour.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  /// What the user can do with this session right now.
  String get nextAction {
    if (status == 'COMPLETED') return 'Finished';
    if (status == 'CANCELLED') return 'Cancelled';
    if (status == 'DISPUTED') return 'Waiting on an admin';
    if (!checkedIn) return 'Tutor must enter the session code';
    if (!tutorConfirmed) return 'Waiting for the tutor to confirm';
    if (!tuteeConfirmed) return 'Waiting for the tutee to confirm';
    return 'Ready to complete';
  }

  @override
  List<Object?> get props => [bookingId, status, confirmations, checkedIn];
}
