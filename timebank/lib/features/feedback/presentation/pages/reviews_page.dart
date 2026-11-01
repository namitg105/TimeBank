import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../../auth/session.dart';

/// Reviews — leave one, read them, see how tutors are rated.
///
/// MEMBER 5 — FEEDBACK.
class ReviewsPage extends StatefulWidget {
  const ReviewsPage({super.key});

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  final ApiClient _api = sl<ApiClient>();

  int _tab = 0;
  bool _loading = true;
  String? _error;
  String? _flash;

  List<dynamic> _reviewable = [];
  List<dynamic> _bothSides = [];
  List<dynamic> _topTutors = [];
  List<dynamic> _bySubject = [];

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
      final reviewable = await _api.get('/api/feedback/reviewable') as List;
      final both = await _api.get('/api/feedback/both-sides') as List;
      final top = await _api.get('/api/feedback/top-tutors') as List;
      final subj = await _api.get('/api/feedback/by-subject') as List;

      if (!mounted) return;
      setState(() {
        _reviewable = reviewable;
        _bothSides = both;
        _topTutors = top;
        _bySubject = subj;
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
        title: const Text('Reviews'),
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
                          ButtonSegment(value: 0, label: Text('Sessions')),
                          ButtonSegment(value: 1, label: Text('Both sides')),
                          ButtonSegment(value: 2, label: Text('Top rated')),
                        ],
                        selected: {_tab},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _tab = s.first),
                      ),
                    ),
                    Expanded(
                      child: switch (_tab) {
                        0 => _sessionsTab(),
                        1 => _bothSidesTab(),
                        _ => _topTab(),
                      },
                    ),
                  ],
                ),
    );
  }

  // -------------------------------------------------------- sessions

  Widget _sessionsTab() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          const InfoBanner(
            'Finished sessions. Each one can take one review from the '
            'student and one from the tutor.',
            icon: Icons.rate_review_outlined,
          ),
          if (_flash != null) ...[
            const SizedBox(height: 12),
            InfoBanner(_flash!, icon: Icons.check_circle_outline),
          ],
          const SizedBox(height: 14),
          if (_reviewable.isEmpty)
            const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No finished sessions',
              hint: 'Reviews can only be left once a session is complete.',
            )
          else
            for (final r in _reviewable) _sessionCard(r),
        ],
      );

  Widget _sessionCard(dynamic r) {
    final bookingId = int.parse('${r['bookingId']}'.split('.').first);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r['subjectCode']}  ·  session $bookingId',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  r['sessionDate']?.toString() ?? '',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${r['tutor']}  taught  ${r['tutee']}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _side(
                    label: 'Student\'s review',
                    done: r['tuteeReview'] == 'done',
                    onLeave: () => _leave(bookingId, 'TUTEE'),
                    onRetract: () => _retract(bookingId, 'TUTEE'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _side(
                    label: 'Tutor\'s review',
                    done: r['tutorReview'] == 'done',
                    onLeave: () => _leave(bookingId, 'TUTOR'),
                    onRetract: () => _retract(bookingId, 'TUTOR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _side({
    required String label,
    required bool done,
    required VoidCallback onLeave,
    required VoidCallback onRetract,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.6,
                color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          if (done)
            OutlinedButton.icon(
              icon: const Icon(Icons.close, size: 15),
              label: const Text('Remove', style: TextStyle(fontSize: 12)),
              onPressed: onRetract,
            )
          else
            FilledButton.tonal(
              onPressed: onLeave,
              child: const Text('Rate', style: TextStyle(fontSize: 12)),
            ),
        ],
      );

  // ------------------------------------------------------ both sides

  Widget _bothSidesTab() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          const InfoBanner(
            'What each side said about the other. Where the two ratings '
            'disagree sharply, somebody is worth talking to.',
            icon: Icons.compare_arrows,
          ),
          const SizedBox(height: 14),
          for (final r in _bothSides)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${r['subjectCode']}  ·  ${r['tutor']} → '
                            '${r['tutee']}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        _stateChip(r['reviewState']?.toString() ?? ''),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _score('student said', r['tuteeRatedTutor']),
                        const SizedBox(width: 22),
                        _score('tutor said', r['tutorRatedTutee']),
                        const Spacer(),
                        if (r['disputeStatus'] != '-')
                          Text(
                            'dispute ${r['disputeStatus']}',
                            style: const TextStyle(
                                fontSize: 10.5, color: AppColors.negative),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );

  Widget _score(String label, Object? value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9.5, color: AppColors.textMuted)),
          Text(
            value == null ? '—' : '$value',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      );

  Widget _stateChip(String state) {
    final bad = state == 'DISAGREEMENT';
    final none = state == 'no reviews';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bad ? const Color(0x22E0564E) : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: bad ? AppColors.negative : AppColors.border),
      ),
      child: Text(
        state,
        style: TextStyle(
          fontSize: 9.5,
          letterSpacing: 0.4,
          color: bad
              ? AppColors.negative
              : none
                  ? AppColors.textMuted
                  : AppColors.textSecondary,
        ),
      ),
    );
  }

  // ------------------------------------------------------- top rated

  Widget _topTab() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          const InfoBanner(
            'Tutors rated better than the campus average. Only the '
            'students\' ratings count here — what a tutor thought of their '
            'student says nothing about the teaching.',
            icon: Icons.star_outline,
            tint: AppColors.accent,
          ),
          const SizedBox(height: 14),
          for (final t in _topTutors)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['tutorName']?.toString() ?? '',
                              style: const TextStyle(fontSize: 13.5)),
                          Text(
                            '${t['reviews']} review(s)  ·  campus average '
                            '${t['campusAverage']}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${t['theirAverage']}',
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),

          const SectionLabel('By subject'),
          for (final s in _bySubject)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      s['subject']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: '${s['subject']}'.startsWith('**')
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text('${s['avgRating']}',
                      style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(width: 12),
                  Text(
                    '${s['reviews']} review(s)',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
        ],
      );

  // --------------------------------------------------------- actions

  Future<void> _leave(int bookingId, String role) async {
    double rating = 4.5;
    final comments = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(role == 'TUTEE'
              ? 'How was the session?'
              : 'How was the student?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        rating >= i
                            ? Icons.star
                            : rating >= i - 0.5
                                ? Icons.star_half
                                : Icons.star_border,
                        color: AppColors.accent,
                        size: 28,
                      ),
                      onPressed: () =>
                          setLocal(() => rating = i.toDouble()),
                    ),
                ],
              ),
              Center(
                child: Text('$rating',
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: comments,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Anything to add?',
                  hintText: 'Optional',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      await _api.post('/api/feedback', body: {
        'bookingId': bookingId,
        'reviewerRole': role,
        'rating': rating,
        'comments': comments.text.trim(),
      });
      if (!mounted) return;
      setState(() => _flash = 'Review saved.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _flash = _clean('$e'));
    }
  }

  Future<void> _retract(int bookingId, String role) async {
    try {
      final res =
          await _api.delete('/api/feedback/$bookingId/$role') as Map;
      if (!mounted) return;
      setState(() => _flash = res['message']?.toString() ?? 'Removed.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _flash = _clean('$e'));
    }
  }

  static String _clean(String raw) {
    final i = raw.indexOf(': ');
    return i > 0 && i < 40 ? raw.substring(i + 2) : raw;
  }
}
