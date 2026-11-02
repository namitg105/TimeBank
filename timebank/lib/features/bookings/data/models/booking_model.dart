import '../../domain/entities/booking.dart';

class BookingModel extends Booking {
  const BookingModel({
    required super.bookingId,
    required super.tuteeName,
    required super.tutorName,
    required super.subjectCode,
    required super.schedDate,
    required super.startTime,
    required super.durationHours,
    required super.mode,
    required super.venue,
    required super.status,
    required super.creditsHeld,
    required super.confirmations,
    required super.checkedIn,
  });

  factory BookingModel.fromJson(Map<String, dynamic> json) => BookingModel(
        bookingId: _int(json['bookingId']),
        tuteeName: json['tuteeName']?.toString() ?? '',
        tutorName: json['tutorName']?.toString() ?? '',
        subjectCode: json['subjectCode']?.toString() ?? '',
        // Java LocalDate serialises as "2026-11-03".
        schedDate: DateTime.tryParse(json['schedDate']?.toString() ?? '') ??
            DateTime.now(),
        startTime: _double(json['startTime']),
        durationHours: _double(json['durationHours']),
        mode: json['mode']?.toString() ?? 'ONLINE',
        venue: json['venue']?.toString() ?? '',
        status: json['status']?.toString() ?? 'REQUESTED',
        creditsHeld: _double(json['creditsHeld']),
        confirmations: json['confirmations']?.toString() ?? 'N/N',
        checkedIn: json['checkedIn'] == true,
      );

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
