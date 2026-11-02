import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

import 'features/admin/presentation/pages/admin_page.dart';
import 'features/auth/presentation/pages/welcome_page.dart';
import 'features/auth/session.dart';
import 'features/bookings/presentation/bloc/booking_bloc.dart';
import 'features/bookings/presentation/pages/bookings_page.dart';
import 'features/ledger/presentation/bloc/ledger_bloc.dart';
import 'features/ledger/presentation/pages/audit_page.dart';
import 'features/ledger/presentation/pages/ledger_page.dart';
import 'features/profile/presentation/pages/profile_page.dart';
import 'features/skills/presentation/pages/skills_page.dart';
import 'features/students/presentation/bloc/student_bloc.dart';
import 'features/students/presentation/pages/students_page.dart';

/// TimeBank — peer tutoring, paid for in hours rather than money.
///
/// ARCHITECTURE
///
///     Flutter  --HTTP/JSON-->  Spring Boot  --JDBC-->  Oracle
///
/// Flutter cannot reach Oracle on its own: JDBC is a Java API and there
/// is no Oracle driver for Dart. The Spring Boot service in ../api is
/// the bridge, and that is where the real JDBC work happens.
///
/// WHAT EACH TAB COVERS
///
///   Profile / Students   Member 1  onboarding, roles, soft delete
///   Subjects             Member 2  skills, availability, the catalogue
///   Sessions             Member 3  booking, check-in, confirmation
///   Credits / Audit      Member 4  escrow, the ledger, the audit
///   Admin                Member 5  feedback, disputes, fraud
///
/// Nothing in the UI explains any of that. A student sees an app; the
/// database reasoning lives in these comments and in the API console,
/// where every click prints the statement it ran.
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
    // The Blocs are provided once, above the navigation shell, so state
    // survives switching tabs. A Bloc created per page would refetch
    // everything on every tap.
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<StudentBloc>()),
        BlocProvider(create: (_) => sl<BookingBloc>()),
        BlocProvider(create: (_) => sl<LedgerBloc>()),
      ],
      child: MaterialApp(
        title: 'TimeBank',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
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

/// What a signed-in student sees: themselves, what they can teach, the
/// sessions they are part of, and what their credits have done.
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
      // IndexedStack, not a plain switch: each page keeps its scroll
      // position and its loaded data when the user moves between tabs.
      body: IndexedStack(
        index: _index,
        children: const [
          ProfilePage(),
          SkillsPage(),
          BookingsPage(),
          LedgerPage(),
        ],
      ),
      bottomNavigationBar: _Nav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Me',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Subjects',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Sessions',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Credits',
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  ADMINISTRATOR
// =====================================================================

/// What the administrator sees: everyone, everything they teach, every
/// session, the books, and the complaints.
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
          BookingsPage(),
          AuditPage(),
          AdminPage(),
        ],
      ),
      bottomNavigationBar: _Nav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Students',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Subjects',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Sessions',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_outlined),
            selectedIcon: Icon(Icons.verified),
            label: 'Credits',
          ),
          NavigationDestination(
            icon: Icon(Icons.gavel_outlined),
            selectedIcon: Icon(Icons.gavel),
            label: 'Complaints',
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
