import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../session.dart';

/// Sign in, or sign up.
///
/// MEMBER 1 — Onboarding and profiles.
///
/// Signing in reads a row; signing up writes two. That asymmetry is the
/// interesting part and the screen says so: registering a student also
/// writes their opening credit row, in the same transaction, because
/// STUDENT has TOTAL participation in <i>posts</i> — the double line in
/// the ER diagram. A student who exists with no ledger row is a state
/// the schema does not allow to happen.
class StudentAuthPage extends StatefulWidget {
  const StudentAuthPage({super.key});

  @override
  State<StudentAuthPage> createState() => _StudentAuthPageState();
}

class _StudentAuthPageState extends State<StudentAuthPage> {
  final ApiClient _api = sl<ApiClient>();

  bool _signingUp = false;
  bool _busy = false;
  String? _error;

  // sign in
  final _loginRegNo = TextEditingController();

  // sign up
  final _regNo = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  final _block = TextEditingController();
  final _roomNo = TextEditingController();
  final _phone = TextEditingController();
  DateTime? _dob;

  List<dynamic> _departments = [];
  int _deptId = 1;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    for (final c in [
      _loginRegNo, _regNo, _firstName, _lastName,
      _email, _city, _block, _roomNo, _phone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final data = await _api.get('/api/auth/departments') as List;
      if (!mounted) return;
      setState(() {
        _departments = data;
        if (data.isNotEmpty) {
          _deptId = (data.first['deptId'] as num).toInt();
        }
      });
    } catch (_) {
      // The picker falls back to department 1, which always exists in
      // the seed. Not worth blocking the screen over.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_signingUp ? 'Create an account' : 'Sign in'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Sign in')),
                      ButtonSegment(value: true, label: Text('Sign up')),
                    ],
                    selected: {_signingUp},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() {
                      _signingUp = s.first;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 20),

                  if (_error != null) ...[
                    InfoBanner(_error!,
                        icon: Icons.error_outline, tint: AppColors.negative),
                    const SizedBox(height: 14),
                  ],

                  if (_signingUp) ..._signUpFields() else ..._signInFields(),

                  const SizedBox(height: 22),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : (_signingUp ? _doSignUp : _doSignIn),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_signingUp
                              ? 'Create my account'
                              : 'Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- sign in

  List<Widget> _signInFields() => [
        const SizedBox(height: 4),
        TextField(
          controller: _loginRegNo,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Registration number',
            hintText: '25BCE1001',
          ),
          onSubmitted: (_) => _doSignIn(),
        ),
        const SizedBox(height: 10),
        const Text(
          'Try 25BCE1001 (Aarav, a tutor), 25BCE1002 (Diya, a tutee) '
          'or 25BCE1003 (Kabir, who is both).',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ];

  Future<void> _doSignIn() async {
    final regNo = _loginRegNo.text.trim();
    if (regNo.isEmpty) {
      setState(() => _error = 'Enter your registration number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final data =
          await _api.post('/api/auth/login', body: {'regNo': regNo}) as Map;
      currentSession.value =
          Session.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _clean('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------- sign up

  List<Widget> _signUpFields() => [
        const InfoBanner(
          'You start with 3 credits. One credit buys an hour of help, and '
          'you earn them back by teaching.',
          icon: Icons.account_balance_wallet_outlined,
          tint: AppColors.accent,
        ),
        const SizedBox(height: 18),

        const SectionLabel('Identity'),
        TextField(
          controller: _regNo,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Registration number',
            hintText: '25BCE1200',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _firstName,
                decoration: const InputDecoration(labelText: 'First name'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lastName,
                decoration: const InputDecoration(labelText: 'Last name'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'name@vit.ac.in',
          ),
        ),

        const SectionLabel('Date of birth'),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 17),
          label: Text(_dob == null
              ? 'Pick a date'
              : '${_dob!.day.toString().padLeft(2, '0')}'
                  '-${_dob!.month.toString().padLeft(2, '0')}'
                  '-${_dob!.year}'),
          onPressed: _pickDob,
        ),

        const SectionLabel('Department'),
        DropdownButtonFormField<int>(
          initialValue: _deptId,
          isExpanded: true,
          items: _departments.isEmpty
              ? const [
                  DropdownMenuItem(
                      value: 1, child: Text('Computer Science and Engineering'))
                ]
              : [
                  for (final d in _departments)
                    DropdownMenuItem(
                      value: (d['deptId'] as num).toInt(),
                      child: Text(
                        '${d['school']}  ·  ${d['deptName']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
          onChanged: (v) => setState(() => _deptId = v ?? 1),
        ),

        const SectionLabel('Where to find you (optional)'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _block,
                decoration: const InputDecoration(
                    labelText: 'Block', hintText: 'A Block'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _roomNo,
                decoration: const InputDecoration(
                    labelText: 'Room', hintText: '214'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          decoration: const InputDecoration(labelText: 'Home city'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone',
            hintText: '10 digits',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'You can add more numbers later.',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ];

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 19, 1, 1),
      firstDate: DateTime(now.year - 60),
      lastDate: DateTime(now.year - 15),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _doSignUp() async {
    if (_regNo.text.trim().isEmpty ||
        _firstName.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty) {
      setState(() => _error = 'Registration number and both names are needed.');
      return;
    }
    if (!_email.text.contains('@')) {
      setState(() => _error = 'That email address does not look right.');
      return;
    }
    if (_dob == null) {
      setState(() => _error = 'Pick your date of birth.');
      return;
    }
    final phone = _phone.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
      setState(() => _error = 'A phone number must be exactly 10 digits.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final iso = '${_dob!.year.toString().padLeft(4, '0')}-'
        '${_dob!.month.toString().padLeft(2, '0')}-'
        '${_dob!.day.toString().padLeft(2, '0')}';

    try {
      final data = await _api.post('/api/auth/signup', body: {
        'regNo': _regNo.text.trim().toUpperCase(),
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'email': _email.text.trim(),
        'dob': iso,
        'deptId': _deptId,
        'block': _block.text.trim(),
        'roomNo': _roomNo.text.trim(),
        'city': _city.text.trim(),
        'phone': phone,
      }) as Map;

      currentSession.value =
          Session.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _clean('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Strips the exception wrapper so the user sees the server's sentence.
  static String _clean(String raw) {
    final i = raw.indexOf(': ');
    return i > 0 && i < 40 ? raw.substring(i + 2) : raw;
  }
}
