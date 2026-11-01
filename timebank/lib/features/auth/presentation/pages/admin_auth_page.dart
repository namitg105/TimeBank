import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../session.dart';

/// The administrator's door.
///
/// One credential, because there is one administrator on this
/// deployment. It is checked against application.properties, not
/// against a table, and the screen says so rather than pretending
/// otherwise.
///
/// WHY NO PASSWORD COLUMN IN THE SCHEMA
/// Credentials are not a data-modelling problem. Storing them properly
/// means salting, hashing and rotation; storing them casually in a
/// VARCHAR2 would be worse than not modelling them at all, and would
/// teach the wrong lesson. What the ADMIN table does carry is what the
/// database genuinely needs to know: who the moderators are, and which
/// of them ruled on a given dispute — enforced by FK_DP_ADMIN and
/// CHK_DP_RESOLVED.
class AdminAuthPage extends StatefulWidget {
  const AdminAuthPage({super.key});

  @override
  State<AdminAuthPage> createState() => _AdminAuthPageState();
}

class _AdminAuthPageState extends State<AdminAuthPage> {
  final ApiClient _api = sl<ApiClient>();

  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administrator')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentWash,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.accentDim),
                    ),
                    child: const Icon(Icons.admin_panel_settings_outlined,
                        color: AppColors.accent, size: 26),
                  ),
                  const SizedBox(height: 18),

                  if (_error != null) ...[
                    InfoBanner(_error!,
                        icon: Icons.lock_outline, tint: AppColors.negative),
                    const SizedBox(height: 14),
                  ],

                  TextField(
                    controller: _username,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _hide,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _hide
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
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

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Both fields are needed.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final data = await _api.post('/api/auth/admin', body: {
        'username': _username.text.trim(),
        'password': _password.text,
      }) as Map;

      currentSession.value =
          Session.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (!mounted) return;
      final raw = '$e';
      final i = raw.indexOf(': ');
      setState(() => _error =
          i > 0 && i < 40 ? raw.substring(i + 2) : raw);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
