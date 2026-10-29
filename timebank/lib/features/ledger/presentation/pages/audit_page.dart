import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../domain/entities/audit.dart';
import '../bloc/ledger_bloc.dart';

/// The closed-economy audit and the two fraud reports.
///
/// This page is the argument that the whole design works:
///
///     sum of all balances + credits in escrow = granted − penalised
///
/// Every session writes one HOLD and one TRANSFER that cancel out, so
/// the only things that can move the total are a new starter grant or a
/// penalty. If the two sides ever disagree, credits were created or
/// destroyed outside the ledger.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  bool _showingReports = false;

  @override
  void initState() {
    super.initState();
    context.read<LedgerBloc>().add(const AuditRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => context.read<LedgerBloc>().add(
                  _showingReports
                      ? const ReportsRequested()
                      : const AuditRequested(),
                ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: _Tab(
                    label: 'Economy',
                    active: !_showingReports,
                    onTap: () {
                      setState(() => _showingReports = false);
                      context
                          .read<LedgerBloc>()
                          .add(const AuditRequested());
                    },
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _Tab(
                    label: 'Reports',
                    active: _showingReports,
                    onTap: () {
                      setState(() => _showingReports = true);
                      context
                          .read<LedgerBloc>()
                          .add(const ReportsRequested());
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<LedgerBloc, LedgerState>(
              buildWhen: (_, s) =>
                  s is LedgerLoading ||
                  s is AuditLoaded ||
                  s is ReportsLoaded ||
                  s is LedgerFailure,
              builder: (context, state) => switch (state) {
                LedgerLoading() => const LoadingView(label: 'Checking'),
                LedgerFailure(:final message) => ErrorView(
                    message: message,
                    onRetry: () => context
                        .read<LedgerBloc>()
                        .add(const AuditRequested()),
                  ),
                AuditLoaded(:final audit) => _AuditView(audit: audit),
                ReportsLoaded(:final leaderboard, :final collusion) =>
                  _ReportsView(leaderboard: leaderboard, collusion: collusion),
                _ => const LoadingView(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Tab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.accentWash : AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active ? AppColors.accentDim : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      );
}

class _AuditView extends StatelessWidget {
  final Audit audit;
  const _AuditView({required this.audit});

  @override
  Widget build(BuildContext context) {
    final ok = audit.balanced;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        // The verdict, large and unambiguous.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: (ok ? AppColors.positive : AppColors.negative)
                .withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (ok ? AppColors.positive : AppColors.negative)
                  .withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              Icon(
                ok ? Icons.verified_outlined : Icons.report_problem_outlined,
                size: 34,
                color: ok ? AppColors.positive : AppColors.negative,
              ),
              const SizedBox(height: 14),
              Text(
                ok ? 'BALANCED' : 'BROKEN',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: ok ? AppColors.positive : AppColors.negative,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ok
                    ? 'No credits have been created or lost.'
                    : 'Credits appeared or vanished outside the ledger.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),

        const SectionLabel('The equation'),
        Panel(
          child: Column(
            children: [
              _Row('Sum of all balances', audit.balances),
              const SizedBox(height: 11),
              _Row('Held in escrow', audit.escrow, prefix: '+'),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Divider(height: 1),
              ),
              _Row('Grants minus penalties', audit.grantsLessPenalties,
                  prefix: '='),
              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHover,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _Row('Drift', audit.drift, emphasise: true),
              ),
            ],
          ),
        ),

        const SectionLabel('Why this holds'),
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Explain('1',
                  'Booking writes one HOLD: the tutee is debited straight away.'),
              _Explain('2',
                  'Completion writes one TRANSFER: the tutor is credited the same amount.'),
              _Explain('3',
                  'Those two cancel out, so a finished session changes the total by nothing.'),
              _Explain('4',
                  'Only a starter GRANT adds credits, and only a PENALTY removes them.'),
            ],
          ),
        ),

        const SizedBox(height: 16),
        const InfoBanner(
          'The ledger is append-only — a database trigger blocks UPDATE and '
          'DELETE on it entirely. Without that this check would prove '
          'nothing, because the numbers could simply be edited to agree.',
          icon: Icons.lock_outline,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double value;
  final String? prefix;
  final bool emphasise;

  const _Row(this.label, this.value, {this.prefix, this.emphasise = false});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              prefix ?? '',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: emphasise
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: emphasise ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: emphasise ? 16 : 14.5,
              fontWeight: FontWeight.w600,
              color: emphasise
                  ? (value == 0 ? AppColors.positive : AppColors.negative)
                  : AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class _Explain extends StatelessWidget {
  final String number;
  final String text;
  const _Explain(this.number, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentWash,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
}

class _ReportsView extends StatelessWidget {
  final List<String> leaderboard;
  final List<String> collusion;

  const _ReportsView({required this.leaderboard, required this.collusion});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          const SectionLabel('Tutors by hours taught'),
          if (leaderboard.isEmpty)
            const Panel(
              child: Text('Nobody has completed a session yet.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textMuted)),
            )
          else
            ...leaderboard.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                )),

          const SectionLabel('Credit-loop collusion'),
          const InfoBanner(
            'Two friends who repeatedly tutor each other net out to zero '
            'credits but collect a review every time. No database can stop '
            'people who agree to lie — it can only make the pattern easy to '
            'see.',
            icon: Icons.visibility_outlined,
          ),
          const SizedBox(height: 12),
          if (collusion.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.positive.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: AppColors.positive.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 18, color: AppColors.positive),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'No reciprocal pairs found.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.positive),
                    ),
                  ),
                ],
              ),
            )
          else
            ...collusion.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.negative.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color:
                              AppColors.negative.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_outlined,
                            size: 17, color: AppColors.negative),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(line,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      );
}
