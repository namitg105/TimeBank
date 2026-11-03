import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../../../shared/widgets/rows_view.dart';
import '../../../auth/session.dart';

/// Subjects, who can teach them, and when.
///
/// MEMBER 2 — SUBJECT, TUTOR_SKILL, SLOT.
///
/// Three tabs, one per idea this module owns:
///
///   Matrix     the M:N relationship, with cross-department teaching
///              flagged — the fact nothing stores, because it is a
///              comparison between two other facts
///   Slots      the weak entity, where slot_no restarts per tutor
///   Catalogue  the subjects, and the gaps nobody can teach
class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  final ApiClient _api = sl<ApiClient>();

  int _tab = 0;
  bool _loading = true;
  String? _error;
  Flash? _flash;
  String _lastRole = '';

  /// The two views that answer a question about the whole catalogue
  /// rather than about one person. Each is a different shape of query,
  /// and each prints its SQL in the API window.
  static const _reports = {
    3: (
      'capacity',
      'How many tutors can teach each subject, and how many of them are '
          'experts? One pass over the catalogue with GROUP BY; the LEFT '
          'JOIN keeps subjects nobody teaches, which an inner join would '
          'drop — and those are the ones worth seeing.'
    ),
    4: (
      'ranking',
      'Each tutor ranked against the others teaching that same subject. '
          'RANK restarts for every subject, and FIRST_VALUE names the '
          'leader on every row — a window keeps all the rows, which '
          'GROUP BY could not.'
    ),
  };

  List<dynamic> _reportRows = [];
  bool _loadingReport = false;
  String? _reportError;

  Future<void> _loadReport(int tab) async {
    final key = _reports[tab]!.$1;
    setState(() {
      _loadingReport = true;
      _reportError = null;
      _reportRows = [];
    });
    try {
      final data = await _api.get('/api/skills/$key') as List;
      if (!mounted) return;
      setState(() {
        _reportRows = data;
        _loadingReport = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reportError = '$e';
        _loadingReport = false;
      });
    }
  }

  List<dynamic> _matrix = [];
  List<dynamic> _slots = [];
  List<dynamic> _subjects = [];
  List<dynamic> _gaps = [];

  Session get _me => currentSession.value!;
  bool get _isAdmin => _me.isAdmin;

  @override
  void initState() {
    super.initState();
    _lastRole = _me.role;
    currentSession.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    currentSession.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// Becoming a tutor on the Me tab changes what this screen can show,
  /// so reload when the role changes.
  void _onSessionChanged() {
    final s = currentSession.value;
    if (s == null || s.role == _lastRole) return;
    _lastRole = s.role;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // An admin sees everybody's skills; a student sees their own.
      final matrixPath = _isAdmin
          ? '/api/skills/matrix'
          : '/api/skills/matrix?tutorId=${_me.studentId}';

      final matrix = await _api.get(matrixPath) as List;
      final subjects = await _api.get('/api/skills/subjects') as List;
      final gaps = await _api.get('/api/skills/gaps') as List;

      List<dynamic> slots = [];
      if (!_isAdmin && _me.isTutor) {
        slots = await _api.get('/api/skills/slots/${_me.studentId}') as List;
      }

      if (!mounted) return;
      setState(() {
        _matrix = matrix;
        _subjects = subjects;
        _gaps = gaps;
        _slots = slots;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Subjects and skills' : 'My subjects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => currentSession.value = null,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(label: 'Loading')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            children: [
              for (final (i, label) in [
                (0, 'Subjects'),
                (1, _isAdmin ? 'Hours' : 'My hours'),
                (2, 'Browse'),
                (3, 'Capacity'),
                (4, 'Ranking'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: _tab == i,
                    onSelected: (_) {
                      setState(() {
                        _tab = i;
                        _flash = null;
                      });
                      if (_reports.containsKey(i)) _loadReport(i);
                    },
                  ),
                ),
            ],
          ),
        ),
        if (_flash != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ResultBanner(_flash!),
          ),
        Expanded(
          child: switch (_tab) {
            0 => _matrixTab(),
            1 => _slotsTab(),
            2 => _catalogueTab(),
            _ => RowsView(
                  note: _reports[_tab]!.$2,
                  loading: _loadingReport,
                  error: _reportError,
                  rows: _reportRows,
                  onRetry: () => _loadReport(_tab),
                ),
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------- matrix

  Widget _matrixTab() {
    // Count people, not rows: one tutor may teach several such subjects.
    final cross = _matrix
        .where((r) => r['note'] == 'CROSS-DEPARTMENT')
        .map((r) => r['tutorId'])
        .toSet()
        .length;
    final crossText = !_isAdmin
        ? 'You teach a subject from outside your own school.'
        : cross == 1
            ? 'One person here teaches a subject from outside their own school.'
            : '$cross people here teach a subject from outside their own school.';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        if (cross > 0)
          InfoBanner(
            '$crossText That is allowed, and often where the best help '
            'comes from.',
            icon: Icons.alt_route,
            tint: AppColors.accent,
          ),
        if (!_isAdmin && _me.isTutor) ...[
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a subject I teach'),
            onPressed: _addSubject,
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a subject to change your level in it.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: 14),

        if (_matrix.isEmpty)
          const EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'Nothing here yet',
            hint: 'Become a tutor on the Me tab and pick a subject.',
          )
        else
          for (final r in _matrix) _skillRow(r),
      ],
    );
  }

  Widget _skillRow(dynamic r) {
    final isCross = r['note'] == 'CROSS-DEPARTMENT';

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r['subjectCode']}  ·  ${r['subjectName']}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
                StatusChip(r['competencyLevel']?.toString() ?? ''),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${r['tutorName']}  ·  ${r['tutorSchool']}'
              '   →   subject owned by ${r['subjectSchool']}',
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'grade ${r['gradeProof']}   ·   certified '
                  '${r['certifiedOn']}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
                const Spacer(),
                if (isCross)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentWash,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.accentDim),
                    ),
                    child: const Text(
                      'OUTSIDE THEIR SCHOOL',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 0.6,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    // A tutor can change their own level; the admin only reads.
    if (_isAdmin) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _changeLevel(r),
      child: row,
    );
  }

  // ------------------------------------------------------------ slots

  Widget _slotsTab() {
    if (_isAdmin) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: InfoBanner(
          'Hours belong to the person teaching. Sign in as a student to '
          'set yours.',
          icon: Icons.info_outline,
        ),
      );
    }

    if (!_me.isTutor) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'You are not teaching yet',
          hint: 'Become a tutor on the Me tab, then add the hours you '
              'are free.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        const InfoBanner(
          'These are the hours you are free to teach. People can only book '
          'you inside them.',
          icon: Icons.schedule,
        ),

        const SizedBox(height: 14),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add free hours'),
          onPressed: _addSlot,
        ),
        const SizedBox(height: 16),

        if (_slots.isEmpty)
          const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No hours added',
            hint: 'Nobody can book you until you add some.',
          )
        else
          for (final s in _slots)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      alignment: Alignment.center,
                      child: Text(
                        s['dayOfWeek']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_hhmm(s['startTime'])} – ${_hhmm(s['endTime'])}',
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          Text(
                            s['state'] == 'free'
                                ? 'No upcoming sessions'
                                : 'Has an upcoming session',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 19),
                      tooltip: 'Withdraw',
                      onPressed: () => _removeSlot(s),
                    ),
                  ],
                ),
              ),
            ),

        const SizedBox(height: 10),
        const InfoBanner(
          'Hours that have ever had a session booked stay on record, so '
          'they cannot be removed. You can always add new hours.',
        ),
      ],
    );
  }

  // -------------------------------------------------------- catalogue

  Widget _catalogueTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        if (_gaps.isNotEmpty) ...[
          const SectionLabel('Nobody teaches these yet'),
          const InfoBanner(
            'If you know one of these, you would be the first.',
            icon: Icons.lightbulb_outline,
          ),
          const SizedBox(height: 10),
          for (final g in _gaps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${g['subjectCode']}  ·  ${g['subjectName']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      g['owningSchool']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
        ],

        const SectionLabel('All subjects'),
        for (final s in _subjects)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${s['code']}  ·  ${s['name']}',
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              '${s['category']}  ·  ${s['school']}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------- actions

  Future<void> _addSlot() async {
    String day = 'MON';
    int start = 16;
    int end = 18;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('When are you free?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Which day, and between what times?',
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                children: [
                  for (final d in ['MON','TUE','WED','THU','FRI','SAT'])
                    ChoiceChip(
                      label: Text(d, style: const TextStyle(fontSize: 11.5)),
                      selected: day == d,
                      onSelected: (_) => setLocal(() => day = d),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Start  ${_hhmm(start)}',
                  style: const TextStyle(fontSize: 12.5)),
              Slider(
                value: start.toDouble(),
                min: 6,
                max: 21,
                divisions: 15,
                onChanged: (v) => setLocal(() {
                  start = v.round();
                  if (end <= start) end = start + 1;
                }),
              ),
              Text('End  ${_hhmm(end)}',
                  style: const TextStyle(fontSize: 12.5)),
              Slider(
                value: end.toDouble(),
                min: 7,
                max: 22,
                divisions: 15,
                onChanged: (v) => setLocal(() {
                  end = v.round();
                  if (end <= start) start = end - 1;
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    await _act(
      () => _api.post('/api/skills/slots/${_me.studentId}', body: {
        'dayOfWeek': day,
        'startTime': start,
        'endTime': end,
      }),
      'Free hours added. People can book you then.',
    );
  }

  Future<void> _removeSlot(dynamic slot) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove these hours?'),
        content: Text(
          '${slot['dayOfWeek']}  ${_hhmm(slot['startTime'])} – '
          '${_hhmm(slot['endTime'])}\n\nNobody will be able to book you then.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;

    await _act(
      () => _api.delete('/api/skills/slots/${_me.studentId}/'
          '${(slot['slotNo'] as num).toInt()}'),
      'Free hours removed.',
    );
  }

  /// Runs one change, reloads, then reports what happened.
  Future<void> _act(Future<dynamic> Function() call, String ok) async {
    try {
      await call();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _flash = Flash.ok(ok));
    } catch (e) {
      if (!mounted) return;
      setState(() => _flash = Flash.error(e));
    }
  }

  static const _levels = [
    ('BEGINNER', 'Beginner'),
    ('PROFICIENT', 'Proficient'),
    ('EXPERT', 'Expert'),
  ];
  static const _grades = ['S', 'A', 'B', 'C'];

  /// Asks for a level and a grade, starting from [level] and [grade].
  Future<(String, String)?> _askLevel(
      String title, String level, String grade) {
    return showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How well do you know it?',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final (v, label) in _levels)
                  ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: level == v,
                    onSelected: (_) => setLocal(() => level = v),
                  ),
              ]),
              const SizedBox(height: 14),
              const Text('Your grade in it',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final g in _grades)
                  ChoiceChip(
                    label: Text(g, style: const TextStyle(fontSize: 12)),
                    selected: grade == g,
                    onSelected: (_) => setLocal(() => grade = g),
                  ),
              ]),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (level, grade)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSubject() async {
    final taught =
        _matrix.map((r) => (r['subjectId'] as num).toInt()).toSet();
    final choices = _subjects
        .where((s) => !taught.contains((s['subjectId'] as num).toInt()))
        .toList();
    if (choices.isEmpty) {
      setState(() => _flash =
          const Flash.ok('You already teach every subject on the list.'));
      return;
    }

    final subject = await showDialog<dynamic>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Which subject?'),
        children: [
          for (final s in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, s),
              child: Text('${s['code']}  ·  ${s['name']}',
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
    if (subject == null || !mounted) return;

    final picked = await _askLevel(
        '${subject['code']}  ·  ${subject['name']}', 'PROFICIENT', 'A');
    if (picked == null) return;

    await _act(
      () => _api.post('/api/skills/${_me.studentId}', body: {
        'subjectId': (subject['subjectId'] as num).toInt(),
        'competency': picked.$1,
        'grade': picked.$2,
      }),
      'Subject added. People can now book you for it.',
    );
  }

  Future<void> _changeLevel(dynamic row) async {
    final picked = await _askLevel(
      '${row['subjectCode']}  ·  ${row['subjectName']}',
      row['competencyLevel']?.toString() ?? 'PROFICIENT',
      row['gradeProof']?.toString() ?? 'A',
    );
    if (picked == null) return;

    await _act(
      () => _api.put(
          '/api/skills/${_me.studentId}/${(row['subjectId'] as num).toInt()}',
          body: {'competency': picked.$1, 'grade': picked.$2}),
      'Level updated.',
    );
  }

  static String _hhmm(Object? t) {
    final v = t is num ? t.toDouble() : double.tryParse('$t') ?? 0;
    final h = v.floor();
    final m = ((v - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
