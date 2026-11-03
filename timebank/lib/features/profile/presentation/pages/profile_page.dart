import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../../auth/session.dart';

/// The signed-in student's own profile and roles.
///
/// MEMBER 1 — Onboarding and profiles.
///
/// This is where the overlapping, partial specialization is visible as
/// something you can act on rather than just read. The two role buttons
/// are independent: joining one subclass never leaves the other, which
/// is exactly what "overlapping" means. And a student who presses
/// neither stays in neither table, which is "partial".
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ApiClient _api = sl<ApiClient>();

  List<String> _phones = [];
  List<dynamic> _subjects = [];
  bool _busy = false;
  Flash? _flash;

  Session get _me => currentSession.value!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// My phone numbers, and my roles as the database has them now (a
  /// booking may have changed them).
  ///
  /// The subject catalogue is deliberately NOT fetched here. It is only
  /// needed if you tap Tutor, and the Subjects tab loads it anyway — so
  /// fetching it on every visit just put the same query in the API
  /// window twice for no reason. [_pickSubject] fetches it on demand.
  Future<void> _load() async {
    await refreshMyRole();
    try {
      final phones =
          await _api.get('/api/students/${_me.studentId}/phones') as List;
      if (!mounted) return;
      setState(() => _phones = phones.map((p) => p.toString()).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _flash = Flash.error(e));
    }
  }

  Future<void> _loadSubjects() async {
    final subjects = await _api.get('/api/skills/subjects') as List;
    if (!mounted) return;
    setState(() => _subjects = subjects);
  }

  /// Runs one action, then shows what happened and reloads.
  Future<void> _run(Future<dynamic> Function() call, String ok) async {
    setState(() {
      _busy = true;
      _flash = null;
    });
    try {
      await call();
      if (!mounted) return;
      setState(() => _flash = Flash.ok(ok));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _flash = Flash.error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _busy ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => currentSession.value = null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          // ------------------------------------------------ identity
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me.fullName,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${me.regNo}  ·  ${me.school}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stat(label: 'AGE', value: '${me.age}'),
                    const SizedBox(width: 24),
                    _Stat(label: 'ROLE', value: roleLabel(me.role)),
                    if (me.badgeLevel.isNotEmpty) ...[
                      const SizedBox(width: 24),
                      _Stat(label: 'BADGE', value: titleCase(me.badgeLevel)),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          if (_flash != null) ...[
            const SizedBox(height: 14),
            ResultBanner(_flash!),
          ],

          // ------------------------------------------------ roles
          const SectionLabel('What I do here'),
          const InfoBanner(
            'You can teach, learn, or both. Pick whichever fits — you can '
            'always add the other one later.',
            icon: Icons.lightbulb_outline,
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _RoleCard(
                  icon: Icons.co_present_outlined,
                  title: 'Tutor',
                  subtitle: me.isTutor
                      ? 'Joined · ${titleCase(me.badgeLevel)} badge'
                      : 'Teach a subject',
                  joined: me.isTutor,
                  onTap: _busy || me.isTutor ? null : _becomeTutor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RoleCard(
                  icon: Icons.school_outlined,
                  title: 'Learner',
                  subtitle: me.isTutee
                      ? 'Joined · ${titleCase(me.needTier)} help'
                      : 'Get help with a subject',
                  joined: me.isTutee,
                  onTap: _busy || me.isTutee ? null : _becomeLearner,
                ),
              ),
            ],
          ),

          if (me.isTutor) ...[
            const SizedBox(height: 10),
            const InfoBanner(
              'Your badge goes up on its own as you teach more hours. '
              'Bronze, then Silver at 10 hours, then Gold at 25.',
              icon: Icons.workspace_premium_outlined,
            ),
          ],

          // ------------------------------------------------ phones
          const SectionLabel('My phone numbers'),
          const InfoBanner(
            'Add as many as you like — a hostel number and a mobile, say.',
            icon: Icons.phone_outlined,
          ),
          const SizedBox(height: 6),
          for (final p in _phones)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone, size: 18),
              title: Text(p),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 19),
                tooltip: 'Remove this number',
                onPressed: _busy ? null : () => _removePhone(p),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                  _phones.isEmpty ? 'Add a number' : 'Add another number'),
              onPressed: _busy ? null : _addPhone,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- actions

  Future<void> _becomeTutor() async {
    final subjectId = await _pickSubject(
      'Which subject will you teach?',
      'Pick the one you know best. You can add more on the Subjects tab.',
    );
    if (subjectId == null) return;

    await _run(
      () => _api.post('/api/roles/${_me.studentId}/tutor', body: {
        'verificationDocNo': 'VIT-${_me.regNo}',
        'subjectId': subjectId,
        'competency': 'PROFICIENT',
        'grade': 'A',
      }),
      'You are a tutor now. Add the hours you are free on the Subjects '
      'tab, under My hours, so people can book you.',
    );
  }

  Future<void> _becomeLearner() async {
    const tiers = [
      ('BASIC', 'Basic', 'A little help now and then'),
      ('INTERMEDIATE', 'Intermediate', 'Regular help with a subject'),
      ('ADVANCED', 'Advanced', 'A lot of help, often'),
    ];

    final tier = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('How much help do you need?'),
        children: [
          for (final (value, label, hint) in tiers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, value),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  Text(hint,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
    if (tier == null) return;

    await _run(
      () => _api.post('/api/roles/${_me.studentId}/tutee', body: {
        'needTier': tier,
        'timeBands': ['EVENING'],
      }),
      'You are a learner now. Book a session on the Sessions tab.',
    );
  }

  Future<void> _addPhone() async {
    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Add a phone number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          decoration: const InputDecoration(hintText: '10 digits'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (phone == null || !mounted) return; // cancelled
    if (!RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
      setState(() => _flash =
          const Flash.error('A phone number must be exactly 10 digits.'));
      return;
    }

    await _run(
      () => _api.post('/api/students/${_me.studentId}/phones',
          body: {'phone': phone}),
      'Number added.',
    );
  }

  Future<void> _removePhone(String phone) => _run(
        () => _api.delete('/api/students/${_me.studentId}/phones/$phone'),
        'Number removed.',
      );

  Future<int?> _pickSubject(String title, String note) async {
    if (_subjects.isEmpty) {
      try {
        await _loadSubjects();
      } catch (e) {
        if (!mounted) return null;
        setState(() => _flash = Flash.error(e));
        return null;
      }
    }
    if (!mounted) return null;
    if (_subjects.isEmpty) {
      setState(() => _flash = const Flash.error(
          'The subject list could not be loaded. Press reload and try again.'));
      return null;
    }

    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in _subjects)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${s['code']}  ·  ${s['name']}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          s['school']?.toString() ?? '',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => Navigator.pop(
                            dialogContext, (s['subjectId'] as num).toInt()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      );
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool joined;
  final VoidCallback? onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.joined,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: joined ? AppColors.accentWash : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: joined ? AppColors.accentDim : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon,
                      size: 20,
                      color: joined
                          ? AppColors.accent
                          : AppColors.textSecondary),
                  const Spacer(),
                  if (joined)
                    const Icon(Icons.check_circle,
                        size: 16, color: AppColors.positive),
                ],
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
