import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../domain/entities/ledger_entry.dart';
import '../bloc/ledger_bloc.dart';
import '../widgets/ledger_tile.dart';

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
  final _idController = TextEditingController(text: '102');

  @override
  void initState() {
    super.initState();
    context.read<LedgerBloc>().add(const PassbookRequested(102));
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Passbook')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14.5),
                    decoration: const InputDecoration(
                      labelText: 'Student id',
                      hintText: '101 to 112',
                      prefixIcon: Icon(Icons.badge_outlined,
                          size: 19, color: AppColors.textMuted),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _load,
                    child: const Text('Open'),
                  ),
                ),
              ],
            ),
          ),
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
                          hint: 'Check the student id — every registered '
                              'student has at least a starter grant.',
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
    final id = int.tryParse(_idController.text.trim());
    if (id == null) return;
    FocusScope.of(context).unfocus();
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
                  'Nothing stores this number. It is the sum of the rows '
                  'below, recomputed every time it is asked for.',
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
              'Below zero. This student has borrowed against future '
              'tutoring. The floor is -5.0, after which the database '
              'refuses new bookings.',
              icon: Icons.warning_amber_outlined,
              tint: AppColors.negative,
            ),
          ],
        ],
      ),
    );
  }
}
