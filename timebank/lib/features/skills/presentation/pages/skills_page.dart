import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
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
  String? _flash;

  List<dynamic> _matrix = [];
  List<dynamic> _slots = [];
  List<dynamic> _subjects = [];
  List<dynamic> _gaps = [];

  Session get _me => currentSession.value!;
  bool get _isAdmin => _me.isAdmin;

  @override
  void initState() {
    super.initState();
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
          ? const LoadingView(label: 'Reading from Oracle')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Subjects')),
              ButtonSegment(value: 1, label: Text('My hours')),
              ButtonSegment(value: 2, label: Text('Browse')),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(
          child: switch (_tab) {
            0 => _matrixTab(),
            1 => _slotsTab(),
            _ => _catalogueTab(),
          },
        ),
      ],
    );
  }

  // ----------------------------------------------------------- matrix

  Widget _matrixTab() {
    final cross = _matrix.where((r) => r['note'] == 'CROSS-DEPARTMENT').length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        if (cross > 0)
          InfoBanner(
            cross == 1
                ? 'One person here teaches a subject from outside their own '
                  'school. That is allowed, and often where the best help '
                  'comes from.'
                : '$cross people here teach a subject from outside their own '
                  'school. That is allowed, and often where the best help '
                  'comes from.',
            icon: Icons.alt_route,
            tint: AppColors.accent,
          ),
        const SizedBox(height: 14),

        if (_matrix.isEmpty)
          const EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'Nothing here yet',
            hint: 'Become a mentor on your profile and pick a subject.',
          )
        else
          for (final r in _matrix) _skillRow(r),
      ],
    );
  }

  Widget _skillRow(dynamic r) {
    final isCross = r['note'] == 'CROSS-DEPARTMENT';

    return Padding(
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
          hint: 'Become a mentor on your profile, then add the hours you '
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

        if (_flash != null) ...[
          const SizedBox(height: 12),
          InfoBanner(_flash!, icon: Icons.check_circle_outline),
        ],

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
                            'slot ${s['slotNo']}  ·  ${s['state']}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 19),
                      tooltip: 'Withdraw',
                      onPressed: () => _removeSlot(
                        (s['slotNo'] as num).toInt(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

        const SizedBox(height: 10),
        const InfoBanner(
          'An hour somebody has already booked cannot be removed — cancel '
          'the session first.',
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

    try {
      await _api.post('/api/skills/slots/${_me.studentId}', body: {
        'dayOfWeek': day,
        'startTime': start,
        'endTime': end,
      });
      if (!mounted) return;
      setState(() => _flash = 'Added. People can book you then.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _flash = '$e');
    }
  }

  Future<void> _removeSlot(int slotNo) async {
    try {
      final res = await _api
          .delete('/api/skills/slots/${_me.studentId}/$slotNo') as Map;
      if (!mounted) return;
      setState(() => _flash = res['message']?.toString() ?? 'Done.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _flash = '$e');
    }
  }

  static String _hhmm(Object? t) {
    final v = t is num ? t.toDouble() : double.tryParse('$t') ?? 0;
    final h = v.floor();
    final m = ((v - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
