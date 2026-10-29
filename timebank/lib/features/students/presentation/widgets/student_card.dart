import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/student.dart';
import '../bloc/student_bloc.dart';

/// One student in the directory.
///
/// The role badge is the interesting part. "BOTH" can only appear
/// because the specialization in the ER diagram is OVERLAPPING — the
/// same person is in the TUTOR table and the TUTEE table. "NEITHER YET"
/// appears because it is also PARTIAL: a student who has just
/// registered is in no subclass at all.
class StudentCard extends StatelessWidget {
  final Student student;
  const StudentCard({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    final dimmed = !student.isActive;

    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showDetail(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _Avatar(initials: student.initials, student: student),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                student.fullName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (dimmed) ...[
                              const SizedBox(width: 7),
                              const Text('closed',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${student.regNo}  ·  ${student.school}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 7),
                        _RoleBadge(role: student.roleInSystem),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Balance(value: student.creditBalance),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final bloc = context.read<StudentBloc>();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(student.fullName,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(student.email,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 20),
              _DetailRow('Registration', student.regNo),
              _DetailRow('School', student.school),
              _DetailRow('Age', '${student.age}'),
              _DetailRow('City', student.city.isEmpty ? '—' : student.city),
              _DetailRow('Role', student.roleInSystem),
              _DetailRow('Balance',
                  '${student.creditBalance.toStringAsFixed(1)} credits'),
              _DetailRow('Status', student.accountStatus),
              const SizedBox(height: 22),
              if (student.isActive)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.block, size: 17),
                    label: const Text('Close this account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.negative,
                      side: const BorderSide(color: AppColors.negative),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _confirmClose(context, bloc);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClose(BuildContext context, StudentBloc bloc) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
        title: const Text('Close this account?'),
        content: Text(
          '${student.fullName} will be marked INACTIVE.\n\n'
          'This is an UPDATE, not a DELETE. Their sessions and ledger rows '
          'are kept — the database refuses to remove a student who has '
          'either, so that history can never go missing.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep it open'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negative,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              bloc.add(StudentDeactivated(student.studentId));
              Navigator.pop(dialogContext);
            },
            child: const Text('Close account'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  final String initials;
  final Student student;
  const _Avatar({required this.initials, required this.student});

  @override
  Widget build(BuildContext context) {
    final tint = student.isTutor ? AppColors.accent : AppColors.info;
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: tint,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'BOTH' => ('TUTOR + TUTEE', AppColors.accent),
      'TUTOR ONLY' => ('TUTOR', AppColors.positive),
      'TUTEE ONLY' => ('TUTEE', AppColors.info),
      _ => ('NOT STARTED', AppColors.textMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// The balance. Tabular figures so a column of these lines up.
class _Balance extends StatelessWidget {
  final double value;
  const _Balance({required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.5,
              color: value <= 0.5 ? AppColors.negative : AppColors.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Text('credits',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 108,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textMuted)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13.5, color: AppColors.textPrimary)),
            ),
          ],
        ),
      );
}
