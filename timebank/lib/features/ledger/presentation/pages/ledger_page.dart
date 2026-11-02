import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../domain/entities/ledger_entry.dart';
import '../bloc/ledger_bloc.dart';
import '../widgets/ledger_tile.dart';
import '../../../auth/session.dart';

/// A student's passbook.
///
/// The balance at the top is NOT read from a column — nothing stores it.
/// It is the sum of the rows underneath, which is exactly how the
/// database computes it too. Showing both together makes the derived
/// attribute visible rather than abstract.
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key});

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  /// Always the signed-in student's own passbook. There is no box to
  /// open someone else's: credit history is private to its owner, and
  /// the administrator has the audit screen instead.
  final int? _myId = currentSession.value?.studentId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passbook'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 21),
            onPressed: _load,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocConsumer<LedgerBloc, LedgerState>(
              listenWhen: (_, s) =>
                  s is LedgerActionSuccess ||
                  (s is LedgerFailure && s.isRule),
              listener: (context, state) {
                final message = switch (state) {
                  LedgerActionSuccess(:final message) => message,
                  LedgerFailure(:final message) => message,
                  _ => null,
                };
                if (message != null) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(message)));
                }
              },
              buildWhen: (_, s) =>
                  s is LedgerLoading ||
                  s is PassbookLoaded ||
                  (s is LedgerFailure && !s.isRule),
              builder: (context, state) => switch (state) {
                LedgerLoading() =>
                  const LoadingView(label: 'Reading the ledger'),
                LedgerFailure(:final message) =>
                  ErrorView(message: message, onRetry: _load),
                PassbookLoaded(:final entries, :final balance) =>
                  entries.isEmpty
                      ? const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No transactions',
                          hint: 'Book or teach a session and it will show here.',
                        )
                      : _Passbook(entries: entries, balance: balance),
                _ => const LoadingView(),
              },
            ),
          ),
        ],
      ),
    );
  }

  void _load() {
    final id = _myId;
    if (id == null) return;
    context.read<LedgerBloc>().add(PassbookRequested(id));
  }
}

// ---------------------------------------------------------------------

class _Passbook extends StatelessWidget {
  final List<LedgerEntry> entries;
  final double balance;

  const _Passbook({required this.entries, required this.balance});

  @override
  Widget build(BuildContext context) {
    final name = entries.isEmpty ? '' : entries.first.studentName;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      itemCount: entries.length + 2,
      separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 0 : 8),
      itemBuilder: (context, i) {
        if (i == 0) return _BalanceHeader(name: name, balance: balance);
        if (i == 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: Text(
              '${entries.length} transactions, newest first',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return LedgerTile(entry: entries[i - 2]);
      },
    );
  }
}

/// The one place in the whole app where the design raises its voice.
class _BalanceHeader extends StatelessWidget {
  final String name;
  final double balance;

  const _BalanceHeader({required this.name, required this.balance});

  @override
  Widget build(BuildContext context) {
    final negative = balance < 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: negative
              ? AppColors.negative.withValues(alpha: 0.4)
              : AppColors.accentDim,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                balance.toStringAsFixed(1),
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(
                      color:
                          negative ? AppColors.negative : AppColors.accent,
                    ),
              ),
              const SizedBox(width: 9),
              const Text('credits',
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.functions,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'This is the total of everything below.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          if (negative) ...[
            const SizedBox(height: 12),
            const InfoBanner(
              'This balance is below zero. New bookings stop once it '
              'reaches -5.0.',
              icon: Icons.warning_amber_outlined,
              tint: AppColors.negative,
            ),
          ],
        ],
      ),
    );
  }
}
