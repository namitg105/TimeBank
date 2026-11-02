import 'package:flutter/foundation.dart';

import '../../core/di/injection.dart';
import '../../core/network/api_client.dart';

/// Who is signed in, for as long as the app is open.
///
/// Deliberately in memory only. Persisting it would mean storing a
/// credential on the device, and this project has no credential worth
/// storing — a student signs in with their registration number, which
/// the database treats as an identifier rather than a secret. Closing
/// the app signs you out, which is the honest behaviour.
class Session {
  final String kind;          // 'STUDENT' or 'ADMIN'
  final int? studentId;
  final String regNo;
  final String fullName;
  final String email;
  final int age;
  final String school;

  /// 'TUTOR ONLY' | 'TUTEE ONLY' | 'BOTH' | 'NEITHER YET'
  final String role;
  final String badgeLevel;
  final String needTier;

  const Session({
    required this.kind,
    required this.fullName,
    this.studentId,
    this.regNo = '',
    this.email = '',
    this.age = 0,
    this.school = '',
    this.role = '',
    this.badgeLevel = '',
    this.needTier = '',
  });

  bool get isAdmin => kind == 'ADMIN';
  bool get isTutor => role == 'TUTOR ONLY' || role == 'BOTH';
  bool get isTutee => role == 'TUTEE ONLY' || role == 'BOTH';

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        kind: j['kind']?.toString() ?? 'STUDENT',
        studentId: j['studentId'] == null
            ? null
            : (j['studentId'] as num).toInt(),
        regNo: j['regNo']?.toString() ?? '',
        fullName: (j['fullName'] ?? j['displayName'] ?? '').toString(),
        email: j['email']?.toString() ?? '',
        age: j['age'] == null ? 0 : (j['age'] as num).toInt(),
        school: j['school']?.toString() ?? '',
        role: j['role']?.toString() ?? '',
        badgeLevel: j['badgeLevel']?.toString() ?? '',
        needTier: j['needTier']?.toString() ?? '',
      );

  Session copyWith({String? role, String? badgeLevel, String? needTier}) =>
      Session(
        kind: kind,
        studentId: studentId,
        regNo: regNo,
        fullName: fullName,
        email: email,
        age: age,
        school: school,
        role: role ?? this.role,
        badgeLevel: badgeLevel ?? this.badgeLevel,
        needTier: needTier ?? this.needTier,
      );
}

/// The one place the app asks "who is signed in?".
///
/// A ValueNotifier rather than a Bloc because there is exactly one
/// value and no transitions worth modelling: you are signed in or you
/// are not.
final currentSession = ValueNotifier<Session?>(null);

/// Re-reads the signed-in student's roles from the API.
///
/// Called after anything that can change them: becoming a tutor or a
/// learner, a booking that enrols you, or a finished session that
/// raises your badge. Screens listening to [currentSession] update.
Future<void> refreshMyRole() async {
  final me = currentSession.value;
  if (me == null || me.isAdmin || me.studentId == null) return;
  try {
    final data = await sl<ApiClient>().get('/api/roles/${me.studentId}') as Map;
    currentSession.value = me.copyWith(
      role: data['label']?.toString(),
      badgeLevel: data['badgeLevel']?.toString(),
      needTier: data['needTier']?.toString(),
    );
  } catch (_) {
    // Not worth interrupting anyone over: the next refresh catches up.
  }
}
