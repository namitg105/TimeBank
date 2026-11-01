import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

import 'features/auth/presentation/pages/welcome_page.dart';
import 'features/auth/session.dart';
import 'features/feedback/presentation/pages/disputes_page.dart';
import 'features/feedback/presentation/pages/reviews_page.dart';
import 'features/students/presentation/bloc/student_bloc.dart';

/// TimeBank — peer tutoring credit exchange.
///
/// SCOPE OF THIS BUILD
/// This branch covers ONE of the five modules the schema supports:
///
///   Member 5  Feedback, disputes and fraud
///             FEEDBACK, DISPUTE, ADMIN.
///
///             Two weak entities with different kinds of partial key:
///             FEEDBACK is keyed on (booking_id, reviewer_role), where
///             a ROLE tells the two reviews of one session apart;
///             DISPUTE is keyed on (booking_id, dispute_no), where a
///             COUNTER tells repeated complaints apart.
///
///             The self join — FEEDBACK joined to itself twice, the
///             copies told apart by reviewer_role, both joins OUTER
///             because many sessions get only one review.
///
///             Collusion detection — pairs who tutor each other in
///             circles, netting to zero credits while collecting a
///             five-star review every time.
///
/// Onboarding, skills, bookings and the credit ledger exist in the
/// database and in sql/ — they are other members' modules — but they
/// have no screens on this branch.
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
/// Reviews of sessions they took part in, and any complaints raised.
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
          ReviewsPage(),
          DisputesPage(),
        ],
      ),
      bottomNavigationBar: _Nav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.rate_review_outlined),
            selectedIcon: Icon(Icons.rate_review),
            label: 'Reviews',
          ),
          NavigationDestination(
            icon: Icon(Icons.gavel_outlined),
            selectedIcon: Icon(Icons.gavel),
            label: 'Disputes',
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
/// The moderator's side: the complaint queue, and the pairs the
/// collusion detector has flagged.
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
          DisputesPage(),
          ReviewsPage(),
        ],
      ),
      bottomNavigationBar: _Nav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.gavel_outlined),
            selectedIcon: Icon(Icons.gavel),
            label: 'Disputes',
          ),
          NavigationDestination(
            icon: Icon(Icons.rate_review_outlined),
            selectedIcon: Icon(Icons.rate_review),
            label: 'Reviews',
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
