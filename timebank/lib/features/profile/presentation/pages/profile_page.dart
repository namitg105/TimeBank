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

  List<dynamic> _phones = [];
  List<dynamic> _subjects = [];
  bool _busy = false;
  String? _flash;

  Session get _me => currentSession.value!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final subjects = await _api.get('/api/skills/subjects') as List;
      if (!mounted) return;
      setState(() => _subjects = subjects);
    } catch (_) {
      // The subject picker degrades to empty; the rest of the page works.
    }
  }

  Future<void> _refreshRole() async {
    final data = await _api.get('/api/roles/${_me.studentId}') as Map;
    currentSession.value = _me.copyWith(
      role: data['label']?.toString(),
      badgeLevel: data['badgeLevel']?.toString(),
      needTier: data['needTier']?.toString(),
    );
  }

  Future<void> _run(Future<dynamic> Function() call, String ok) async {
    setState(() {
      _busy = true;
      _flash = null;
    });
    try {
      await call();
      await _refreshRole();
      if (!mounted) return;
      setState(() => _flash = ok);
    } catch (e) {
      if (!mounted) return;
      final raw = '$e';
      final i = raw.indexOf(': ');
      setState(() => _flash = i > 0 && i < 40 ? raw.substring(i + 2) : raw);
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
                    _Stat(label: 'ROLE', value: me.role),
                    if (me.badgeLevel.isNotEmpty) ...[
                      const SizedBox(width: 24),
                      _Stat(label: 'BADGE', value: me.badgeLevel),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          if (_flash != null) ...[
            const SizedBox(height: 14),
            InfoBanner(_flash!, icon: Icons.check_circle_outline),
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
                  title: 'Mentor',
                  subtitle: me.isTutor
                      ? 'Joined · ${me.badgeLevel}'
                      : 'Teach a subject',
                  joined: me.isTutor,
                  onTap: _busy || me.isTutor ? null : _becomeMentor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RoleCard(
                  icon: Icons.school_outlined,
                  title: 'Mentee',
                  subtitle: me.isTutee
                      ? 'Joined · ${me.needTier}'
                      : 'Get help with a subject',
                  joined: me.isTutee,
                  onTap: _busy || me.isTutee ? null : _becomeMentee,
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
          const SizedBox(height: 10),
          if (_phones.isEmpty)
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a number'),
              onPressed: _busy ? null : _addPhone,
            )
          else
            for (final p in _phones)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone, size: 18),
                title: Text(p.toString()),
              ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- actions

  Future<void> _becomeMentor() async {
    final subjectId = await _pickSubject(
      'Which subject will you teach?',
      'Pick the one you know best. You can add more afterwards.',
    );
    if (subjectId == null) return;

    await _run(
      () => _api.post('/api/roles/${_me.studentId}/tutor', body: {
        'verificationDocNo': 'VIT-${_me.regNo}',
        'subjectId': subjectId,
        'competency': 'PROFICIENT',
        'grade': 'A',
      }),
      'You are a mentor now. Publish the hours you are free on the '
      'Skills screen so people can find you.',
    );
  }

  Future<void> _becomeMentee() async {
    final tier = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('How much help do you need?'),
        children: [
          for (final t in ['BASIC', 'INTERMEDIATE', 'ADVANCED'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, t),
              child: Text(t),
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
      'You are a mentee now. Browse the subjects and find someone to '
      'help you.',
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
          keyboardType: TextInputType.phone,
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

    if (phone == null || !RegExp(r'^[0-9]{10}$').hasMatch(phone)) return;

    await _run(
      () => _api.post('/api/students/${_me.studentId}/phones',
          body: {'phone': phone}),
      'Number added.',
    );
    if (mounted) setState(() => _phones = [..._phones, phone]);
  }

  Future<int?> _pickSubject(String title, String note) async {
    if (_subjects.isEmpty) {
      await _load();
    }
    if (!mounted || _subjects.isEmpty) return null;

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
