import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';

/// Shown once, immediately after a booking is made.
///
/// The session code is the project's answer to a tutor claiming credits
/// for a session that never happened. It is issued to the TUTEE only;
/// the tutor has to type it in at the start, and a database trigger
/// refuses to let the session be confirmed until that has happened.
///
/// It is deliberately hard to dismiss by accident: there is no barrier
/// tap, and the only way out is the button.
class SessionCodeDialog extends StatelessWidget {
  final int bookingId;
  final String sessionCode;
  final double creditsHeld;

  const SessionCodeDialog({
    super.key,
    required this.bookingId,
    required this.sessionCode,
    required this.creditsHeld,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.positive, size: 21),
          const SizedBox(width: 10),
          Text('Session #$bookingId booked'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Give this code to the tutee, and nobody else.',
            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),

          // The code itself, widely spaced so it can be read aloud.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.accentWash,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accentDim),
            ),
            child: Column(
              children: [
                SelectableText(
                  sessionCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 7,
                    color: AppColors.accent,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 15),
                  label: const Text('Copy', style: TextStyle(fontSize: 12.5)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: sessionCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied.')),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          _Line(Icons.lock_outline,
              '${creditsHeld.toStringAsFixed(1)} credits are now held in escrow.'),
          const _Line(Icons.login,
              'The tutor types this code in at the start of the session.'),
          const _Line(Icons.how_to_reg_outlined,
              'Credits reach the tutor only when both sides confirm.'),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('I have written it down'),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
}
