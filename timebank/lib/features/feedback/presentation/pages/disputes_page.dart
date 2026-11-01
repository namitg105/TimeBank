import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../../auth/session.dart';

/// Disputes and suspicious patterns.
///
/// MEMBER 5 — DISPUTE, ADMIN, and the collusion detector.
class DisputesPage extends StatefulWidget {
  const DisputesPage({super.key});

  @override
  State<DisputesPage> createState() => _DisputesPageState();
}

class _DisputesPageState extends State<DisputesPage> {
  final ApiClient _api = sl<ApiClient>();

  int _tab = 0;
  bool _loading = true;
  String? _error;
  String? _flash;
  int? _adminId;

  List<dynamic> _admins = [];
  List<dynamic> _disputes = [];
  List<dynamic> _collusion = [];
  List<dynamic> _trend = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admins = await _api.get('/api/admin/accounts') as List;
      final disputes = await _api.get('/api/admin/disputes') as List;
      final collusion = await _api.get('/api/feedback/collusion') as List;
      final trend = await _api.get('/api/feedback/trend') as List;

      if (!mounted) return;
      setState(() {
        _admins = admins;
        _disputes = disputes;
        _collusion = collusion;
        _trend = trend;
        _adminId ??= admins.isEmpty
            ? null
            : (admins.first['adminId'] as num).toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Disputes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => currentSession.value = null,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(label: 'Reading from Oracle')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Queue')),
                          ButtonSegment(value: 1, label: Text('Suspicious')),
                          ButtonSegment(value: 2, label: Text('Trends')),
                        ],
                        selected: {_tab},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _tab = s.first),
                      ),
                    ),
                    Expanded(
                      child: switch (_tab) {
                        0 => _queueTab(),
                        1 => _collusionTab(),
                        _ => _trendTab(),
                      },
                    ),
                  ],
                ),
    );
  }

  // ------------------------------------------------------------ queue

  Widget _queueTab() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          const SectionLabel('Handling these as'),
          Panel(
            padding: const EdgeInsets.all(13),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _admins)
                  ChoiceChip(
                    selected: _adminId == (a['adminId'] as num).toInt(),
                    onSelected: (_) => setState(
                      () => _adminId = (a['adminId'] as num).toInt(),
                    ),
                    label: Text(
                      a['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
            ),
          ),

          if (_flash != null) ...[
            const SizedBox(height: 12),
            InfoBanner(_flash!, icon: Icons.check_circle_outline),
          ],

          const SectionLabel('Open complaints'),
          if (_disputes.isEmpty)
            const EmptyState(
              icon: Icons.verified_outlined,
              title: 'Nothing to handle',
              hint: 'No complaints have been raised.',
            )
          else
            for (final d in _disputes) _disputeCard(d),
        ],
      );

  Widget _disputeCard(dynamic d) {
    final bookingId = (d['bookingId'] as num).toInt();
    final disputeNo = (d['disputeNo'] as num).toInt();
    final status = d['status']?.toString() ?? '';
    final open = status != 'RESOLVED';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${d['subjectCode']}  ·  session $bookingId',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
                StatusChip(status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${d['tutorName']}  taught  ${d['tuteeName']}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Raised by the ${d['raisedByRole'] == 'TUTEE'
                  ? 'student' : 'tutor'} on ${d['raisedOn']}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              d['reason']?.toString() ?? '',
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
            if (d['resolutionNote'] != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Outcome: ${d['resolutionNote']}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
            if (open) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'OPEN')
                    OutlinedButton(
                      onPressed: () => _act(
                        () => _api.post(
                          '/api/admin/disputes/$bookingId/$disputeNo/triage',
                        ),
                      ),
                      child: const Text('Looking into it',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  FilledButton(
                    onPressed: _adminId == null
                        ? null
                        : () => _rule(bookingId, disputeNo, 'TUTEE'),
                    child: const Text('Side with the student',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  FilledButton.tonal(
                    onPressed: _adminId == null
                        ? null
                        : () => _rule(bookingId, disputeNo, 'TUTOR'),
                    child: const Text('Side with the tutor',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------- collusion

  Widget _collusionTab() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          const InfoBanner(
            'Pairs who keep tutoring each other back and forth. Their '
            'credits cancel out, but they collect a glowing review every '
            'time — so the ratings go up and nothing is actually taught.',
            icon: Icons.sync_problem_outlined,
            tint: AppColors.accent,
          ),
          const SizedBox(height: 14),
          if (_collusion.isEmpty)
            const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Nothing suspicious',
              hint: 'No pair is tutoring each other in circles.',
            )
          else
            for (final c in _collusion)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${c['studentA']}  ⇄  ${c['studentB']}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x22E0564E),
                              borderRadius: BorderRadius.circular(6),
                              border:
                                  Border.all(color: AppColors.negative),
                            ),
                            child: const Text(
                              'CHECK THIS',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  letterSpacing: 0.5,
                                  color: AppColors.negative),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${c['studentA']} taught ${c['studentB']} '
                        '${c['aTaughtB']} time(s), and it went the other '
                        'way ${c['bTaughtA']} time(s).',
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Average rating between them: '
                        '${c['avgBetweenThem'] ?? '—'}',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      );

  // ----------------------------------------------------------- trends

  Widget _trendTab() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          const InfoBanner(
            'How each tutor is doing over time — whether their ratings are '
            'going up or down.',
            icon: Icons.trending_up,
          ),
          const SizedBox(height: 14),
          for (final t in _trend)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(t['tutor']?.toString() ?? '',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text(
                      t['sessionDate']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    Text('${t['rating']}',
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 14),
                    _trendChip(t['trend']?.toString() ?? ''),
                  ],
                ),
              ),
            ),
        ],
      );

  Widget _trendChip(String trend) {
    final c = switch (trend) {
      'improving' => AppColors.positive,
      'slipping' => AppColors.negative,
      _ => AppColors.textMuted,
    };
    return SizedBox(
      width: 80,
      child: Text(
        trend,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 11, color: c),
      ),
    );
  }

  // --------------------------------------------------------- actions

  Future<void> _act(Future<dynamic> Function() call) async {
    try {
      final res = await call();
      final msg = res is Map
          ? (res['message'] ?? 'Done').toString()
          : res.toString();
      if (!mounted) return;
      setState(() => _flash = msg);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final raw = '$e';
      final i = raw.indexOf(': ');
      setState(() => _flash = i > 0 && i < 40 ? raw.substring(i + 2) : raw);
    }
  }

  Future<void> _rule(int bookingId, int disputeNo, String inFavour) async {
    final controller = TextEditingController(
      text: inFavour == 'TUTEE'
          ? 'Nobody checked in, so the session did not happen. Credits '
            'returned to the student.'
          : 'The tutor was there and the session went ahead as arranged.',
    );

    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(inFavour == 'TUTEE'
            ? 'Side with the student'
            : 'Side with the tutor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Say why. This is kept with the complaint.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Close the complaint'),
          ),
        ],
      ),
    );

    if (note == null || note.isEmpty) return;

    await _act(() => _api.post(
          '/api/admin/disputes/$bookingId/$disputeNo/resolve',
          body: {
            'adminId': _adminId,
            'inFavour': inFavour,
            'note': note,
          },
        ));
  }
}
