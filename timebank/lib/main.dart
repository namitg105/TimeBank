import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

import 'features/admin/presentation/pages/admin_page.dart';
import 'features/bookings/presentation/bloc/booking_bloc.dart';
import 'features/bookings/presentation/pages/bookings_page.dart';
import 'features/ledger/presentation/bloc/ledger_bloc.dart';
import 'features/ledger/presentation/pages/audit_page.dart';
import 'features/ledger/presentation/pages/ledger_page.dart';
import 'features/students/presentation/bloc/student_bloc.dart';
import 'features/students/presentation/pages/students_page.dart';

/// TimeBank — peer tutoring credit exchange.
///
/// ARCHITECTURE
///
///     Flutter  --HTTP/JSON-->  Spring Boot  --JDBC-->  Oracle
///
/// Flutter cannot reach Oracle on its own: JDBC is a Java API and no
/// Oracle driver exists for Dart. The Spring Boot service in ../api is
/// the bridge, and that is where the real JDBC work happens. This app is
/// the presentation half of the project.
///
/// Inside the app, the layers run inward:
///
///     presentation  ->  domain  <-  data
///
/// Both outer layers depend on the domain and the domain depends on
/// neither, which is why the entities and use cases contain no mention
/// of HTTP, JSON or Oracle.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is dark only. Forcing the status bar to match stops a white
  // strip appearing above a black screen on Android.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await initDependencies();

  runApp(const TimeBankApp());
}

class TimeBankApp extends StatelessWidget {
  const TimeBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The three Blocs are provided once, above the navigation shell, so
    // state survives switching tabs. A Bloc created per page would
    // refetch everything on every tap.
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
        home: const AppShell(),
      ),
    );
  }
}

/// Bottom navigation between the four screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _pages = [
    StudentsPage(),
    BookingsPage(),
    LedgerPage(),
    AuditPage(),
    AdminPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack, not a plain switch: each page keeps its scroll
      // position and its loaded data when the user moves between tabs.
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Students',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note),
              label: 'Sessions',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Passbook',
            ),
            NavigationDestination(
              icon: Icon(Icons.verified_outlined),
              selectedIcon: Icon(Icons.verified),
              label: 'Audit',
            ),
            NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: 'Admin',
            ),
          ],
        ),
      ),
    );
  }
}
