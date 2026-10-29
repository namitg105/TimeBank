import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/ledger_entry.dart';

/// One row of the passbook.
///
/// Three things are shown together on purpose: the signed amount, the
/// balance that resulted, and where the row came from. A reader can
/// check the chain by eye — each balance should be the one above it plus
/// this amount. That is the same arithmetic the tamper-detection query
/// runs in SQL.
class LedgerTile extends StatelessWidget {
  final LedgerEntry entry;
  const LedgerTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forAmount(entry.amount);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypeIcon(txnType: entry.txnType, tint: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.txnType,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '#${entry.txnId}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  entry.explanation,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      entry.isSystemCredit
                          ? Icons.settings_outlined
                          : Icons.school_outlined,
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${entry.origin}  ·  ${_when(entry.postedAt)}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.amount > 0 ? '+' : ''}'
                '${entry.amount.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'bal ${entry.balanceAfter.toStringAsFixed(1)}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _when(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

class _TypeIcon extends StatelessWidget {
  final String txnType;
  final Color tint;
  const _TypeIcon({required this.txnType, required this.tint});

  @override
  Widget build(BuildContext context) {
    final icon = switch (txnType) {
      'GRANT'    => Icons.card_giftcard,
      'HOLD'     => Icons.lock_outline,
      'RELEASE'  => Icons.lock_open_outlined,
      'TRANSFER' => Icons.arrow_outward,
      'PENALTY'  => Icons.gavel,
      _          => Icons.circle_outlined,
    };

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 16, color: tint),
    );
  }
}
