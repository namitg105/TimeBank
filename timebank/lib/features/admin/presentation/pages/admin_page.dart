import 'package:flutter/material.dart';
import 'package:timebank/core/di/injection.dart';
import 'package:timebank/core/network/api_client.dart';
import 'package:timebank/core/theme/app_colors.dart';
import 'package:timebank/shared/widgets/app_widgets.dart';
import 'package:timebank/shared/widgets/rows_view.dart';


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

  /// What has been written about sessions, four ways. Complaints are
  /// what an administrator settles; these are what they read first, and
  /// each is a different shape of query.
  static const _views = [
    (null, 'Complaints', ''),
    (
      'sessions',
      'Both sides of every session',
      'Did the two sides agree? Both halves of the review come from the '
          'SAME table, so FEEDBACK is joined to itself and the copies are '
          'told apart by reviewer_role — only possible because the role is '
          'part of the key. Both joins are OUTER, because many sessions '
          'get only one review.'
    ),
    (
      'top-rated',
      'Top rated',
      'Tutors rated above the campus average. Three levels deep: average '
          'each tutor, average those averages, keep the ones above it. It '
          'is the average OF averages, so a tutor with 20 sessions cannot '
          'drown out one with 2.'
    ),
    (
      'by-subject',
      'By subject',
      'How each subject is rated. STDDEV matters more than it looks: a '
          '4.0 from 4,4,4 is a very different tutor from a 4.0 from 5,5,2. '
          'ROLLUP adds the all-subjects row in the same pass.'
    ),
    (
      'trend',
      'Trend',
      'Is each tutor improving or slipping? LAG gives the rating before, '
          'and a moving average smooths the last three. A GROUP BY would '
          'collapse the history into one number and lose the trend — which '
          'is the whole question.'
    ),
  ];

  String? _view;
  List<dynamic> _viewRows = [];
  bool _loadingView = false;
  String? _viewError;

  Future<void> _openView(String? key) async {
    setState(() {
      _view = key;
      _viewRows = [];
      _viewError = null;
      _loadingView = key != null;
    });
    if (key == null) return;

    try {
      final data = await _api.get('/api/feedback/$key') as List;
      if (!mounted) return;
      setState(() {
        _viewRows = data;
        _loadingView = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _viewError = '$e';
        _loadingView = false;
      });
    }
  }
  bool _loading = true;
  String? _error;

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

  /// Runs one action and reports the outcome at the bottom of the
  /// screen, so it is seen wherever on the page the button was.
  Future<void> _act(Future<dynamic> Function() call) async {
    try {
      final res = await call();
      final msg = res is Map && res['message'] != null
          ? res['message'].toString()
          : 'Done.';
      if (!mounted) return;
      _show(Flash.ok(msg));
      await _load();
    } catch (e) {
      if (!mounted) return;
      _show(Flash.error(e));
    }
  }

  void _show(Flash flash) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(flash.ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: flash.ok ? AppColors.positive : AppColors.negative),
            const SizedBox(width: 10),
            Expanded(child: Text(flash.text)),
          ],
        ),
        duration: const Duration(seconds: 5),
      ));
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
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              children: [
                for (final (key, label, _) in _views)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _view == key,
                      onSelected: (_) => _openView(key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _view != null
                ? RowsView(
                    note: _views.firstWhere((v) => v.$1 == _view).$3,
                    loading: _loadingView,
                    error: _viewError,
                    rows: _viewRows,
                    onRetry: () => _openView(_view),
                  )
                : _loading
                    ? const LoadingView(label: 'Loading')
                    : _error != null
                        ? ErrorView(message: _error!, onRetry: _load)
                        : _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        const InfoBanner(
          'Complaints raised by students and tutors come here to be '
          'settled.',
          icon: Icons.admin_panel_settings_outlined,
          tint: AppColors.accent,
        ),

        // ---------------------------------------------------- who
        const SectionLabel('Rulings are recorded as'),
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
                'Pick whose name goes on the rulings you make here.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),

        // ---------------------------------------------------- proof
        const SectionLabel('Credit history'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Credit history cannot be changed by anyone, including '
                'you. Press this to check that protection is working.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.gpp_bad_outlined, size: 18),
                label: const Text('Check the protection'),
                onPressed: () => _act(
                  () => _api.post('/api/admin/prove-immutable'),
                ),
              ),
            ],
          ),
        ),

        // ---------------------------------------------------- disputes
        SectionLabel(
          'Complaints',
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
                    label: Text(readableStatus(f), style: const TextStyle(fontSize: 12)),
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
              'Nothing here.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else
          for (final d in _disputes) _disputeCard(d),


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
                  'Session $bookingId  ·  complaint $disputeNo',
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
              'learner ${d['tuteeName']}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Raised by the ${d['raisedByRole'] == 'TUTOR' ? 'tutor' : 'learner'} on ${d['raisedOn']}',
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
                      child: const Text('Looking into it',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  FilledButton(
                    onPressed: _adminId == null
                        ? null
                        : () => _askRuling(bookingId, disputeNo, 'TUTEE'),
                    child: const Text('Side with the learner',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  FilledButton.tonal(
                    onPressed: _adminId == null
                        ? null
                        : () => _askRuling(bookingId, disputeNo, 'TUTOR'),
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

  Future<void> _askRuling(int bookingId, int disputeNo, String inFavour) async {
    final controller = TextEditingController(
      text: inFavour == 'TUTEE'
          ? 'Nobody checked in, so the session did not take place. '
            'Credits returned to the learner.'
          : 'The tutor was there and the session went ahead as arranged.',
    );

    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(inFavour == 'TUTEE' ? 'Side with the learner' : 'Side with the tutor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Say why. This is kept with the complaint.',
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
            child: const Text('Close the complaint'),
          ),
        ],
      ),
    );

    if (note == null) return; // cancelled
    if (note.isEmpty) {
      _show(const Flash.error('Write a short note explaining the ruling.'));
      return;
    }

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
