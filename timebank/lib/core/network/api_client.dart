import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../error/exceptions.dart';

/// The one place the app talks to the network.
///
/// WHY THIS EXISTS AT ALL
/// Flutter cannot use JDBC. JDBC is a Java API, and there is no Oracle
/// driver for Dart, so a Dart program has no way to open an Oracle
/// connection. The architecture is therefore:
///
///   Flutter  --HTTP/JSON-->  Spring Boot  --JDBC-->  Oracle
///
/// The JDBC work is real and happens in the Java service; this class is
/// how the app reaches it.
class ApiClient {
  late final Dio _dio;

  ApiClient({String? baseUrl}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl ?? defaultBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'Content-Type': 'application/json'},
      // Do not throw on 4xx: those carry a message the user should read,
      // and _unwrap below turns them into a typed exception instead.
      validateStatus: (status) => status != null && status < 500,
    ));

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint('[api] $o'),
      ));
    }
  }

  /// Where the Spring Boot service is, which depends on where the app runs.
  ///
  /// The Android emulator is the one that catches people out: inside the
  /// emulator `localhost` means the emulator itself, not the computer
  /// hosting it. 10.0.2.2 is the special address Android maps back to
  /// the host machine.
  ///
  /// On a real phone, replace this with the computer's LAN address, e.g.
  /// `http://192.168.1.14:8080` — and make sure the Spring Boot service
  /// is bound to 0.0.0.0, which application.properties already does.
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:8080';
    if (Platform.isAndroid) return 'http://10.0.2.2:8080';
    return 'http://localhost:8080';
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) async =>
      _send(() => _dio.post(path, data: body));

  Future<dynamic> delete(String path) async =>
      _send(() => _dio.delete(path));

  // -------------------------------------------------------------------

  Future<dynamic> _send(Future<Response> Function() call) async {
    try {
      final response = await call();
      return _unwrap(response);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  /// Turns a non-2xx response into a typed exception.
  ///
  /// The API returns 409 CONFLICT when a database rule refused the
  /// request — an overdraft limit, a double booking, a session that has
  /// not finished yet. Those messages were written inside Oracle
  /// triggers for a person to read, so they are passed straight through.
  dynamic _unwrap(Response response) {
    final code = response.statusCode ?? 0;
    if (code >= 200 && code < 300) return response.data;

    final data = response.data;
    final message = data is Map && data['message'] != null
        ? data['message'].toString()
        : 'Request failed with status $code.';
    final oracleCode = data is Map && data['code'] is int ? data['code'] as int : 0;

    throw ServerException(message, statusCode: code, oracleCode: oracleCode);
  }

  Exception _translate(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        const NetworkException('The server took too long to answer.'),
      DioExceptionType.connectionError => const NetworkException(
          'Cannot reach the server. Is the Spring Boot API running?'),
      _ => ServerException(
          e.message ?? 'Unexpected network error.',
          statusCode: e.response?.statusCode ?? 0,
        ),
    };
  }
}
