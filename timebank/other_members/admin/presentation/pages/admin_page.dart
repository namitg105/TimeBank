import 'package:flutter/material.dart';
import 'package:timebank/core/di/injection.dart';
import 'package:timebank/core/network/api_client.dart';
import 'package:timebank/core/theme/app_colors.dart';
import 'package:timebank/shared/widgets/app_widgets.dart';


/// The moderator's area.
///
/// WHY THIS PAGE IS BUILT DIFFERENTLY FROM THE OTHERS
/// The three student-facing features each have the full
/// datasource -> repository -> use case -> bloc stack, because their
/// state is shared between screens and has rules worth isolating. This
/// page is a self-contained admin console: it is read-mostly, nothing
/// else in the app consumes its data, and every action is a single
/// request with no client-side rule of its own. Putting four layers
/// behind it would be ceremony, not design. It talks to [ApiClient]
/// directly and says so.
///
/// WHAT "SIGNING IN" MEANS HERE, SAID PLAINLY
/// Picking a moderator from the list is not authentication. There is no
/// password column in the ADMIN table and no session handling in the
/// API. That is a deliberate scope boundary for a database project:
/// real authentication belongs in an identity layer, and storing
/// credentials here would mean salting, hashing and rotation that teach
/// nothing about data modelling. What the schema DOES enforce is that a
/// resolved dispute must name the admin who ruled on it -- the
/// CHK_DP_RESOLVED constraint refuses a RESOLVED row with a null
/// resolved_by or a null note.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final ApiClient _api = sl<ApiClient>();

  List<dynamic> _admins = [];
  List<dynamic> _disputes = [];

  int? _adminId;
  String _filter = 'ALL';
  bool _loading = true;
  String? _error;
  String? _lastResult;

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
      final disputes = await _api.get(
        '/api/admin/disputes',
        query: _filter == 'ALL' ? null : {'status': _filter},
      ) as List;

      if (!mounted) return;
      setState(() {
        _admins = admins;
        _disputes = disputes;
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

  Future<void> _act(Future<dynamic> Function() call) async {
    try {
      final res = await call();
      final msg = res is Map
          ? (res['message'] ?? res['result'] ?? 'Done').toString()
          : res.toString();
      if (!mounted) return;
      setState(() => _lastResult = msg);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastResult = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(label: 'Reading from Oracle')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        const InfoBanner(
          'ADMIN is its own entity, not a flag on STUDENT. A moderator has '
          'no department, no credit balance and takes part in no sessions, '
          'so folding them into STUDENT would mean columns that are null '
          'for almost every row.',
          icon: Icons.admin_panel_settings_outlined,
          tint: AppColors.accent,
        ),

        // ---------------------------------------------------- who
        const SectionLabel('Signed in as'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in _admins)
                    ChoiceChip(
                      selected: _adminId == (a['adminId'] as num).toInt(),
                      onSelected: (_) => setState(
                        () => _adminId = (a['adminId'] as num).toInt(),
                      ),
                      label: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(a['name']?.toString() ?? '',
                              style: const TextStyle(fontSize: 12.5)),
                          Text(
                            a['designation']?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'A picker over the ADMIN table, not authentication — there '
                'is no password column in the schema. What the database '
                'does enforce is that a RESOLVED dispute must name who '
                'ruled on it and why.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),

        // ---------------------------------------------------- proof
        const SectionLabel('Prove the ledger cannot be edited'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deliberately tries to change a credit row. It should be '
                'refused. Not even an administrator can rewrite credit '
                'history — a mistake is corrected by posting a '
                'compensating row, exactly as in a real ledger.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.gpp_bad_outlined, size: 18),
                label: const Text('Attempt to edit the ledger'),
                onPressed: () => _act(
                  () => _api.post('/api/admin/prove-immutable'),
                ),
              ),
            ],
          ),
        ),

        if (_lastResult != null) ...[
          const SizedBox(height: 12),
          InfoBanner(
            _lastResult!,
            icon: Icons.terminal,
            tint: _lastResult!.contains('Blocked')
                ? AppColors.positive
                : AppColors.accent,
          ),
        ],

        // ---------------------------------------------------- disputes
        SectionLabel(
          'Dispute queue',
          trailing: Text(
            '${_disputes.length}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final f in ['ALL', 'OPEN', 'UNDER_REVIEW', 'RESOLVED'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f, style: const TextStyle(fontSize: 12)),
                    selected: _filter == f,
                    onSelected: (_) {
                      setState(() => _filter = f);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        if (_disputes.isEmpty)
          const Panel(
            child: Text(
              'Nothing in the queue for this filter.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else
          for (final d in _disputes) _disputeCard(d),

        const SizedBox(height: 16),
        const InfoBanner(
          'DISPUTE is a WEAK ENTITY of BOOKING: dispute_no is only a partial '
          'key, numbered within one booking, so the primary key is the pair '
          '(booking_id, dispute_no). A dispute cannot exist without the '
          'session it is about.',
          icon: Icons.link,
        ),
      ],
    );
  }

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
                Text(
                  'Booking $bookingId · dispute $disputeNo',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                StatusChip(status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${d['subjectCode']}  ·  tutor ${d['tutorName']}  ·  '
              'tutee ${d['tuteeName']}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Raised by the ${d['raisedByRole']} on ${d['raisedOn']}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              d['reason']?.toString() ?? '',
              style: const TextStyle(fontSize: 12.5),
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
                  'Ruling: ${d['resolutionNote']}',
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
                      onPressed: () => _act(() => _api.post(
                            '/api/admin/disputes/$bookingId/$disputeNo/triage',
                          )),
                      child: const Text('Mark under review',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  FilledButton(
                    onPressed: _adminId == null
                        ? null
                        : () => _askRuling(bookingId, disputeNo, 'TUTEE'),
                    child: const Text('Rule for the tutee',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  FilledButton.tonal(
                    onPressed: _adminId == null
                        ? null
                        : () => _askRuling(bookingId, disputeNo, 'TUTOR'),
                    child: const Text('Rule for the tutor',
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

  Future<void> _askRuling(int bookingId, int disputeNo, String inFavour) async {
    final controller = TextEditingController(
      text: inFavour == 'TUTEE'
          ? 'Checked the check-in log: no code was ever entered. '
            'Escrow returned, tutor penalised.'
          : 'The tutor attended and the session took place as scheduled.',
    );

    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Rule for the $inFavour'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A resolution note is required. The CHECK constraint on '
              'DISPUTE refuses a RESOLVED row without one, and without '
              'the admin who ruled.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Resolution note'),
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
            child: const Text('Resolve'),
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
