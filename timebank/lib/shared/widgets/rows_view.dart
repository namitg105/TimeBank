import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'app_widgets.dart';

/// One row of a query result, drawn as a small card.
///
/// A table was the obvious choice and the wrong one: these queries
/// return up to eight columns, and a table that wide needs sideways
/// scrolling, which is awkward to read out over someone's shoulder.
/// Each row gets its own card instead, with the most identifying column
/// as the heading and the rest as labelled values underneath.
class RowCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const RowCard({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final entries = row.entries.toList();
    final heading = _heading(entries);
    final rest = entries.where((e) => e.key != heading.key).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Panel(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${heading.value}',
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                for (final e in rest)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label(e.key),
                        style: const TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('${e.value}', style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Which column to use as the card's title.
  ///
  /// A name if the query returned one, otherwise the first column that
  /// is not a bare number — an id or a count makes a poor heading, and
  /// every one of these queries has something better.
  static MapEntry<String, dynamic> _heading(
      List<MapEntry<String, dynamic>> entries) {
    final named = entries
        .where((e) => e.key.toLowerCase().contains('name'))
        .toList();
    if (named.isNotEmpty) return named.first;

    final worded = entries
        .where((e) => num.tryParse('${e.value}') == null)
        .toList();
    if (worded.isNotEmpty) return worded.first;

    return entries.first;
  }

  /// A column name as a label: subject_code and subjectCode both become
  /// SUBJECT CODE, so queries written either way read the same.
  static String _label(String key) => key
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
      .toUpperCase();
}

/// The result of one query: what it asks, then the rows it returned.
///
/// Every screen that offers these views shows them the same way, so the
/// shape lives here once rather than three times.
class RowsView extends StatelessWidget {
  /// One line saying what the query answers, and why it is written so.
  final String note;
  final bool loading;
  final String? error;
  final List<dynamic> rows;
  final VoidCallback onRetry;

  /// Shown instead of "no rows" where emptiness is the good answer.
  final String? emptyIsGood;

  const RowsView({
    super.key,
    required this.note,
    required this.loading,
    required this.error,
    required this.rows,
    required this.onRetry,
    this.emptyIsGood,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        InfoBanner(note, icon: Icons.help_outline),
        const SizedBox(height: 12),
        if (loading)
          const LoadingView(label: 'Asking Oracle')
        else if (error != null)
          ErrorView(message: error!, onRetry: onRetry)
        else if (rows.isEmpty)
          emptyIsGood != null
              ? InfoBanner(emptyIsGood!,
                  icon: Icons.check_circle_outline, tint: AppColors.positive)
              : const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No rows',
                  hint: 'Nothing matched this question.',
                )
        else ...[
          Text(
            plural(rows.length, 'row'),
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            RowCard(row: Map<String, dynamic>.from(row as Map)),
        ],
      ],
    );
  }
}
