import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'admin_auth_page.dart';
import 'student_auth_page.dart';

/// The first screen: student, or administrator?
///
/// Two doors rather than one form with a role dropdown, because the two
/// routes are genuinely different. A student is a row in STUDENT and
/// signs in with the registration number that row is keyed by. An
/// administrator is not a student at all — ADMIN is its own entity, with
/// no department, no credit balance and no sessions — so there is
/// nothing to look them up by in the same way.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------------------------------------- wordmark
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.accentWash,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.accentDim),
                        ),
                        child: const Icon(Icons.hourglass_bottom,
                            color: AppColors.accent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'TimeBank',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Peer tutoring, paid for in hours rather than money.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),

                  const SizedBox(height: 44),
                  const Text(
                    'HOW ARE YOU SIGNING IN?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 18),

                  _DoorCard(
                    icon: Icons.school_outlined,
                    title: 'I am a student',
                    body: 'Sign in with your registration number, or create '
                        'an account. You start with 3 credits.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const StudentAuthPage()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DoorCard(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'I am the administrator',
                    body: 'Manage students and the subject list.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminAuthPage()),
                    ),
                  ),

                  const SizedBox(height: 36),
                  const Text(
                    'VIT  ·  peer tutoring',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      color: AppColors.textMuted,
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
}

class _DoorCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _DoorCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right,
                  color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
