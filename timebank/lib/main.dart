import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

import 'features/auth/presentation/pages/welcome_page.dart';
import 'features/auth/session.dart';
import 'features/profile/presentation/pages/profile_page.dart';
import 'features/skills/presentation/pages/skills_page.dart';
import 'features/students/presentation/bloc/student_bloc.dart';
import 'features/students/presentation/pages/students_page.dart';

/// TimeBank — peer tutoring credit exchange.
///
/// SCOPE OF THIS BUILD
/// This app covers two of the five modules the schema supports:
///
///   Member 1  Onboarding and profiles
///             STUDENT, STUDENT_PHONE, TUTOR, TUTEE, TUTEE_PREFTIME,
///             DEPARTMENT. The overlapping-partial specialization,
///             derived attributes, and soft delete.
///
///   Member 2  Skills and availability
///             SUBJECT, TUTOR_SKILL, SLOT. The M:N relationship,
///             weak entities with partial keys, and cross-department
///             tutoring.
///
/// Bookings, the credit ledger, feedback and disputes exist in the
/// database and in sql/ — they are other members' modules — but they
/// have no screens here.
///
/// ARCHITECTURE
///
///     Flutter  --HTTP/JSON-->  Spring Boot  --JDBC-->  Oracle
///
/// Flutter cannot reach Oracle directly: JDBC is a Java API and there
/// is no Oracle driver for Dart. The Spring Boot service in ../api is
/// the bridge, and that is where the real JDBC work happens.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await initDependencies();

  runApp(const TimeBankApp());
}

class TimeBankApp extends StatelessWidget {
  const TimeBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<StudentBloc>(),
      child: MaterialApp(
        title: 'TimeBank',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,

        // One listener decides the whole route: signed out, signed in as
        // a student, or signed in as the administrator.
        home: ValueListenableBuilder<Session?>(
          valueListenable: currentSession,
          builder: (context, session, _) {
            if (session == null) {
              return const WelcomePage();
            }
            return session.isAdmin
                ? const AdminShell()
                : const StudentShell();
          },
        ),
      ),
    );
  }
}

// =====================================================================
//  STUDENT
// =====================================================================

/// What a signed-in student sees.
///
/// Two tabs, one per module: their own profile and role (Member 1), and
/// the subjects and availability they can teach (Member 2).
class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ProfilePage(),
          SkillsPage(),
        ],
      ),
      bottomNavigationBar: _Nav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'My profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Skills',
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  ADMINISTRATOR
// =====================================================================

/// What the administrator sees.
///
/// The same two modules, from the other side: the whole student
/// directory with onboarding and account closure (Member 1), and the
/// subject catalogue with the skill matrix (Member 2).
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          StudentsPage(),
          SkillsPage(),
        ],
      ),
      bottomNavigationBar: _Nav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Directory',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Subjects',
          ),
        ],
      ),
    );
  }
}

// =====================================================================

class _Nav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<NavigationDestination> destinations;

  const _Nav({
    required this.index,
    required this.onTap,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onTap,
        destinations: destinations,
      ),
    );
  }
}
