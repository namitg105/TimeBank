import '../../../../core/network/api_client.dart';
import '../models/booking_model.dart';

abstract interface class BookingRemoteDataSource {
  Future<List<BookingModel>> getAll({String? status});
  Future<List<BookingModel>> forStudent(int studentId);
  Future<(int, String)> book(Map<String, dynamic> body);
  Future<String> checkIn(int bookingId, String code);
  Future<String> confirm(int bookingId, String role);
  Future<String> cancel(int bookingId, String byRole);
}

class BookingRemoteDataSourceImpl implements BookingRemoteDataSource {
  final ApiClient client;
  const BookingRemoteDataSourceImpl(this.client);

  @override
  Future<List<BookingModel>> getAll({String? status}) async {
    final data = await client.get('/api/bookings',
        query: status == null ? null : {'status': status});
    return (data as List)
        .map((e) => BookingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<BookingModel>> forStudent(int studentId) async {
    final data = await client.get('/api/bookings/student/$studentId');
    return (data as List)
        .map((e) => BookingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<(int, String)> book(Map<String, dynamic> body) async {
    final data = await client.post('/api/bookings', body: body) as Map;
    return (
      (data['bookingId'] as num).toInt(),
      data['sessionCode']?.toString() ?? '',
    );
  }

  @override
  Future<String> checkIn(int bookingId, String code) async {
    final data = await client.post('/api/bookings/$bookingId/checkin',
        body: {'sessionCode': code});
    return (data as Map)['message']?.toString() ?? 'Checked in.';
  }

  @override
  Future<String> confirm(int bookingId, String role) async {
    final data = await client
        .post('/api/bookings/$bookingId/confirm', body: {'role': role});
    return (data as Map)['message']?.toString() ?? 'Confirmed.';
  }

  @override
  Future<String> cancel(int bookingId, String byRole) async {
    final data = await client
        .post('/api/bookings/$bookingId/cancel', body: {'byRole': byRole});
    return (data as Map)['message']?.toString() ?? 'Cancelled.';
  }
}
