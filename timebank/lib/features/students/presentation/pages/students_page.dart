import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../../../shared/widgets/rows_view.dart';
import '../../domain/entities/student.dart';
import '../bloc/student_bloc.dart';
import '../widgets/student_card.dart';
import 'register_student_page.dart';

/// The student directory: search, browse, register, close an account.
///
/// Everything on screen comes from a [StudentState]. The widget never
/// calls a repository, never awaits a future, and holds no data of its
/// own beyond the text in the search box.
class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key});

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  final _searchController = TextEditingController();
  final ApiClient _api = sl<ApiClient>();

  /// The views of the directory, beyond the plain list.
  ///
  /// Each answers a question an administrator actually asks, and each is
  /// a different kind of SELECT — which is also what makes them worth
  /// showing at the review. The SQL for each appears in the API window.
  static const _views = [
    (null, 'Everyone', ''),
    ('low-balance', 'Low on credits',
        'Students below the campus average balance, so they can be nudged '
        'to teach. The inner query averages every balance; the outer keeps '
        'those below it.'),
    ('never-booked', 'Never booked',
        'Registered over 30 days ago and still never booked. NOT EXISTS is '
        're-run for each student, against that student\'s own id.'),
    ('by-department', 'By department',
        'Students, tutors and learners per department. WHERE filters rows '
        'before grouping; HAVING filters the groups after it.'),
    ('ranking', 'Ranking',
        'Each student ranked inside their own department. The window keeps '
        'every row, which GROUP BY cannot, so everyone appears with their '
        'own place.'),
  ];

  String? _view;
  List<dynamic> _rows = [];
  bool _loadingView = false;
  String? _viewError;

  Future<void> _openView(String? key) async {
    setState(() {
      _view = key;
      _rows = [];
      _viewError = null;
      _loadingView = key != null;
    });
    if (key == null) return;

    try {
      final data = await _api.get('/api/students/views/$key') as List;
      if (!mounted) return;
      setState(() {
        _rows = data;
        _loadingView = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _viewError = '$e';
        _loadingView = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<StudentBloc>().add(const StudentsRequested());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
        actions: [
          IconButton(
            tooltip: 'Register a student',
            icon: const Icon(Icons.person_add_alt, size: 20),
            onPressed: _openRegister,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              children: [
                for (final (key, label, _) in _views)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _view == key,
                      onSelected: (_) => _openView(key),
                    ),
                  ),
              ],
            ),
          ),
          if (_view == null)
            _SearchField(
              controller: _searchController,
              onSearch: (q) => context.read<StudentBloc>().add(
                    q.isEmpty
                        ? const StudentsRequested()
                        : StudentsSearched(q),
                  ),
            ),
          if (_view != null) _viewBody(),
          if (_view == null) Expanded(
            child: BlocConsumer<StudentBloc, StudentState>(
              // listenWhen keeps one-shot states (snackbars) out of the
              // builder, so the list is not rebuilt for a toast.
              listenWhen: (_, s) =>
                  s is StudentActionSuccess || s is StudentFailure,
              listener: (context, state) {
                // While the register form is open on top, it reports its
                // own result; reacting here too would double the message.
                if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
                if (state is StudentActionSuccess) {
                  _toast(state.message, AppColors.positive);
                } else if (state is StudentFailure && state.isRule) {
                  _toast(state.message, AppColors.negative);
                }
              },
              buildWhen: (_, s) =>
                  s is StudentLoading ||
                  s is StudentsLoaded ||
                  (s is StudentFailure && !s.isRule),
              builder: (context, state) => switch (state) {
                StudentLoading() =>
                  const LoadingView(label: 'Loading'),
                StudentFailure(:final message) => ErrorView(
                    message: message,
                    onRetry: () => context
                        .read<StudentBloc>()
                        .add(const StudentsRequested()),
                  ),
                StudentsLoaded(:final students) => _StudentList(
                    students: students,
                    onRefresh: () async => context
                        .read<StudentBloc>()
                        .add(const StudentsRequested()),
                  ),
                _ => const LoadingView(),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// One of the four views: its question, then the rows it returned.
  Widget _viewBody() {
    return Expanded(
      child: RowsView(
        note: _views.firstWhere((v) => v.$1 == _view).$3,
        loading: _loadingView,
        error: _viewError,
        rows: _rows,
        onRetry: () => _openView(_view),
      ),
    );
  }

  void _openRegister() {
    final bloc = context.read<StudentBloc>();
    Navigator.of(context).push(MaterialPageRoute(
      // BlocProvider.value, not a new BlocProvider: the registration page
      // must talk to the SAME bloc so the list refreshes behind it.
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: const RegisterStudentPage(),
      ),
    ));
  }

  void _toast(String message, Color tint) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(
              tint == AppColors.positive
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 17,
              color: tint,
            ),
            const SizedBox(width: 11),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 4),
      ));
  }
}

// ---------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSearch;

  const _SearchField({required this.controller, required this.onSearch});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 14.5),
          decoration: InputDecoration(
            hintText: 'Name or registration number',
            prefixIcon:
                const Icon(Icons.search, size: 19, color: AppColors.textMuted),
            suffixIcon: ValueListenableBuilder(
              valueListenable: controller,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.close, size: 17),
                      onPressed: () {
                        controller.clear();
                        onSearch('');
                      },
                    ),
            ),
          ),
          onSubmitted: onSearch,
          onChanged: (v) {
            // Search as you type, but only once there is enough to go on.
            if (v.isEmpty || v.length >= 2) onSearch(v);
          },
        ),
      );
}

class _StudentList extends StatelessWidget {
  final List<Student> students;
  final Future<void> Function() onRefresh;

  const _StudentList({required this.students, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search_outlined,
        title: 'No students matched',
        hint: 'Try part of a name, or a registration number like 25BCE.',
      );
    }

    final tutors = students.where((s) => s.isTutor).length;
    final both = students.where((s) => s.isTutor && s.isTutee).length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        itemCount: students.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${plural(students.length, 'student')}  ·  '
                '$tutors tutoring  ·  $both doing both',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          return StudentCard(student: students[i - 1]);
        },
      ),
    );
  }
}
