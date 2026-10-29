import '../../../../core/network/api_client.dart';
import '../models/student_model.dart';

/// Talks to the Spring Boot API. Nothing above this layer knows that
/// HTTP, JSON or Oracle exist.
abstract interface class StudentRemoteDataSource {
  Future<List<StudentModel>> getAll();
  Future<List<StudentModel>> search(String query);
  Future<double> balanceOf(int studentId);
  Future<StudentModel> register(Map<String, dynamic> body);
  Future<String> deactivate(int studentId);
}

class StudentRemoteDataSourceImpl implements StudentRemoteDataSource {
  final ApiClient client;
  const StudentRemoteDataSourceImpl(this.client);

  @override
  Future<List<StudentModel>> getAll() async {
    final data = await client.get('/api/students');
    return (data as List)
        .map((e) => StudentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<StudentModel>> search(String query) async {
    final data = await client.get('/api/students/search', query: {'q': query});
    return (data as List)
        .map((e) => StudentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<double> balanceOf(int studentId) async {
    final data = await client.get('/api/students/$studentId/balance');
    final raw = (data as Map)['creditBalance'];
    return raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
  }

  @override
  Future<StudentModel> register(Map<String, dynamic> body) async {
    final data = await client.post('/api/students', body: body);
    return StudentModel.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<String> deactivate(int studentId) async {
    final data = await client.delete('/api/students/$studentId');
    return (data as Map)['message']?.toString() ?? 'Account closed.';
  }
}
