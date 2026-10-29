import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Small building blocks shared by every page.
///
/// They exist so the pages stay readable: a page should describe what it
/// shows, not spend forty lines styling a loading spinner.

/// A small uppercase label above a group of content.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(
          children: [
            Text(text.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Booking status as a coloured pill.
///
/// The colour is a secondary cue only — the word is always shown, so the
/// meaning does not depend on being able to distinguish the colours.
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: c,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Shown while a Bloc is loading.
class LoadingView extends StatelessWidget {
  final String? label;
  const LoadingView({super.key, this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            if (label != null) ...[
              const SizedBox(height: 16),
              Text(label!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      );
}

/// Shown when a query succeeded but found nothing.
///
/// An empty screen is an invitation to act, so this always says what to
/// do next rather than only reporting the absence.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: AppColors.textMuted),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              if (action != null) ...[const SizedBox(height: 22), action!],
            ],
          ),
        ),
      );
}

/// Shown when something failed.
///
/// A message that came from a database rule is the user's to act on, so
/// it is displayed plainly with no apology and no stack trace. Errors do
/// not say sorry; they say what happened and what to do.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 32, color: AppColors.negative),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
}

/// A one-line note explaining something non-obvious on screen.
class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? tint;

  const InfoBanner(this.text,
      {super.key, this.icon = Icons.info_outline, this.tint});

  @override
  Widget build(BuildContext context) {
    final c = tint ?? AppColors.info;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bordered panel. Used instead of Card where the content needs to
/// control its own padding.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}
