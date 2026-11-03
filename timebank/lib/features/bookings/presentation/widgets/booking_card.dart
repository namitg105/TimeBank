import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../../auth/session.dart';
import '../../domain/entities/booking.dart';
import '../bloc/booking_bloc.dart';

/// One session in the list, with whatever action it currently needs.
///
/// The card shows the escrow state, because that is the part people get
/// wrong: credits leave the tutee at BOOKING time, sit in escrow, and
/// reach the tutor only when both sides have confirmed.
class BookingCard extends StatelessWidget {
  final Booking booking;
  const BookingCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: booking.status == 'DISPUTED'
              ? AppColors.negative.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${booking.bookingId}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 9),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHover,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  booking.subjectCode,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              StatusChip(booking.status),
            ],
          ),

          const SizedBox(height: 12),

          // tutee -> tutor, in the direction the credits travel.
          Row(
            children: [
              Expanded(
                child: _Party(
                  label: 'LEARNER',
                  name: booking.tuteeName,
                  tint: AppColors.info,
                  confirmed: booking.tuteeConfirmed,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    const Icon(Icons.arrow_forward,
                        size: 15, color: AppColors.textMuted),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.durationHours}h',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _Party(
                  label: 'TUTOR',
                  name: booking.tutorName,
                  tint: AppColors.accent,
                  confirmed: booking.tutorConfirmed,
                  alignEnd: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),
          const Divider(height: 1),
          const SizedBox(height: 11),

          Row(
            children: [
              const Icon(Icons.schedule,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                '${_date(booking.schedDate)}  '
                '${booking.clockTime}–${booking.endClockTime}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Icon(
                booking.mode == 'ONLINE'
                    ? Icons.videocam_outlined
                    : Icons.place_outlined,
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  booking.venue,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            ],
          ),

          if (booking.creditsHeld > 0) ...[
            const SizedBox(height: 11),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.accentWash,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 13, color: AppColors.accent),
                  const SizedBox(width: 7),
                  Text(
                    '${booking.creditsHeld.toStringAsFixed(1)} credits set '
                    'aside · ${booking.nextAction}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.accent),
                  ),
                ],
              ),
            ),
          ],

          // This value is present only in the learner's response. Keeping
          // it on the card until check-in fixes the real-world case where
          // the tutor created the booking or the original dialog was closed.
          if (booking.sessionCode != null &&
              booking.sessionCode!.isNotEmpty &&
              booking.isUpcoming &&
              !booking.checkedIn) ...[
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.key_outlined, size: 15, color: AppColors.info),
                  const SizedBox(width: 8),
                  const Text('Your session code: ',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  SelectableText(
                    booking.sessionCode!,
                    style: const TextStyle(
                      fontSize: 15,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.info,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (booking.isUpcoming) ...[
            const SizedBox(height: 12),
            _Actions(booking: booking),
          ],

          // A finished session is the only one worth reviewing, and
          // trg_feedback_valid refuses any other — so the button only
          // appears here.
          if (booking.isFinished) ...[
            const SizedBox(height: 12),
            _ReviewRow(booking: booking),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
  }
}

// ---------------------------------------------------------------------

class _Party extends StatelessWidget {
  final String label;
  final String name;
  final Color tint;
  final bool confirmed;
  final bool alignEnd;

  const _Party({
    required this.label,
    required this.name,
    required this.tint,
    required this.confirmed,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (confirmed && !alignEnd) ...[
                const Icon(Icons.check, size: 11, color: AppColors.positive),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: tint.withValues(alpha: 0.8),
                ),
              ),
              if (confirmed && alignEnd) ...[
                const SizedBox(width: 3),
                const Icon(Icons.check, size: 11, color: AppColors.positive),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );
}

/// Only the action the session actually needs next is offered, and only
/// to the side it belongs to.
///
/// Check-in comes before confirmation because the database enforces that
/// order: trg_confirm_after_end refuses a confirmation when check_in_at
/// is still null. Offering both at once would just produce an error.
///
/// A student sees only their own side's buttons. The session code proves
/// the tutee turned up only if the TUTOR types it in, and the two
/// confirmations mean something only if each side gives its own. The
/// administrator acts for either side, which keeps a one-screen demo
/// possible.
class _Actions extends StatelessWidget {
  final Booking booking;
  const _Actions({required this.booking});

  @override
  Widget build(BuildContext context) {
    final me = currentSession.value;
    final isAdmin = me == null || me.isAdmin;
    final asTutor = isAdmin || me.studentId == booking.tutorId;
    final asTutee = isAdmin || me.studentId == booking.tuteeId;

    // Whose cancel this is; null lets the administrator choose.
    final String? myRole = isAdmin ? null : (asTutor ? 'TUTOR' : 'TUTEE');

    if (!booking.checkedIn) {
      return Row(
        children: [
          Expanded(
            child: asTutor
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.key_outlined, size: 16),
                    label: const Text('Enter code',
                        style: TextStyle(fontSize: 13)),
                    onPressed: () => _askForCode(context),
                  )
                : const Text(
                    'When you meet, read your session code to the tutor.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                  ),
          ),
          const SizedBox(width: 9),
          _CancelButton(booking: booking, byRole: myRole),
        ],
      );
    }

    final tutorCanConfirm = asTutor && !booking.tutorConfirmed;
    final tuteeCanConfirm = asTutee && !booking.tuteeConfirmed;

    return Row(
      children: [
        if (tutorCanConfirm)
          Expanded(
            child: _ConfirmButton(
              bookingId: booking.bookingId,
              role: 'TUTOR',
              label: isAdmin ? 'Tutor confirms' : 'I confirm it happened',
            ),
          ),
        if (tutorCanConfirm && tuteeCanConfirm) const SizedBox(width: 9),
        if (tuteeCanConfirm)
          Expanded(
            child: _ConfirmButton(
              bookingId: booking.bookingId,
              role: 'TUTEE',
              label: isAdmin ? 'Learner confirms' : 'I confirm it happened',
            ),
          ),
        if (!tutorCanConfirm && !tuteeCanConfirm)
          const Expanded(
            child: Text(
              'You have confirmed. Waiting for the other side.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        const SizedBox(width: 9),
        _CancelButton(booking: booking, byRole: myRole),
      ],
    );
  }

  void _askForCode(BuildContext context) {
    final bloc = context.read<BookingBloc>();
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
        title: const Text('Session code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ask the learner to read out the 8-character code they were '
              'given when they booked.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              style: const TextStyle(
                fontSize: 19,
                letterSpacing: 5,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'XXXXXXXX',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              bloc.add(SessionCheckedIn(booking.bookingId, controller.text));
              Navigator.pop(dialogContext);
            },
            child: const Text('Check in'),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final int bookingId;
  final String role;
  final String label;
  const _ConfirmButton({
    required this.bookingId,
    required this.role,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: () =>
            context.read<BookingBloc>().add(SessionConfirmed(bookingId, role)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 11),
          foregroundColor: AppColors.positive,
          side: BorderSide(color: AppColors.positive.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      );
}

class _CancelButton extends StatelessWidget {
  final Booking booking;

  /// TUTOR or TUTEE when a student cancels their own side; null for the
  /// administrator, who is asked which side is cancelling.
  final String? byRole;
  const _CancelButton({required this.booking, this.byRole});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Cancel this session',
        icon: const Icon(Icons.close, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: AppColors.negative,
          side: BorderSide(color: AppColors.negative.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
          padding: const EdgeInsets.all(11),
        ),
        onPressed: () => _confirmCancel(context),
      );

  void _confirmCancel(BuildContext context) {
    final bloc = context.read<BookingBloc>();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
        title: const Text('Cancel this session?'),
        content: const Text(
          'Who cancels decides where the credits go.\n\n'
          'If the tutor cancels, or the learner cancels more than 24 hours '
          'ahead, the learner gets everything back.\n\n'
          'If the learner cancels inside 24 hours, the credits are split — '
          'the tutor had already kept that hour free.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep it'),
          ),
          if (byRole == null) ...[
            TextButton(
              onPressed: () => _cancelAs(dialogContext, bloc, 'TUTEE'),
              child: const Text('Learner cancels'),
            ),
            _dangerButton(
              onPressed: () => _cancelAs(dialogContext, bloc, 'TUTOR'),
              label: 'Tutor cancels',
            ),
          ] else
            _dangerButton(
              onPressed: () => _cancelAs(dialogContext, bloc, byRole!),
              label: 'Cancel session',
            ),
        ],
      ),
    );
  }

  void _cancelAs(BuildContext dialogContext, BookingBloc bloc, String role) {
    bloc.add(SessionCancelled(booking.bookingId, role));
    Navigator.pop(dialogContext);
  }

  static Widget _dangerButton({
    required VoidCallback onPressed,
    required String label,
  }) =>
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.negative,
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}

// ---------------------------------------------------------------------

/// Leaving and taking back a review, on a finished session.
///
/// MEMBER 5 — FEEDBACK, a weak entity owned by BOOKING.
///
/// Which side you review AS is not a choice: it follows from which side
/// of the session you were on. The administrator is asked, because they
/// were on neither.
class _ReviewRow extends StatefulWidget {
  final Booking booking;
  const _ReviewRow({required this.booking});

  @override
  State<_ReviewRow> createState() => _ReviewRowState();
}

class _ReviewRowState extends State<_ReviewRow> {
  final ApiClient _api = sl<ApiClient>();

  List<String> _reviewers = [];
  bool _busy = false;
  Flash? _flash;

  Booking get _b => widget.booking;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/api/feedback/${_b.bookingId}') as List;
      if (!mounted) return;
      setState(() => _reviewers = data.map((r) => r.toString()).toList());
    } catch (_) {
      // Not worth a message: the buttons simply stay as they were.
    }
  }

  /// Which side the signed-in person was on, or null for the admin.
  String? get _myRole {
    final me = currentSession.value;
    if (me == null || me.isAdmin) return null;
    if (me.studentId == _b.tutorId) return 'TUTOR';
    if (me.studentId == _b.tuteeId) return 'TUTEE';
    return null;
  }

  Future<void> _run(Future<dynamic> Function() call, String ok) async {
    setState(() {
      _busy = true;
      _flash = null;
    });
    try {
      await call();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _flash = Flash.ok(ok));
    } catch (e) {
      if (!mounted) return;
      setState(() => _flash = Flash.error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = currentSession.value;
    final isAdmin = me == null || me.isAdmin;
    final role = _myRole;
    final mine = role != null && _reviewers.contains(role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _reviewers.isEmpty
                    ? 'No reviews yet'
                    : _reviewers.length == 2
                        ? 'Both sides have reviewed this session'
                        : 'One side has reviewed this session',
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textMuted),
              ),
            ),
            if (!isAdmin && role != null)
              mine
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 15),
                      label: const Text('Remove my review',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.negative),
                      onPressed: _busy ? null : _remove,
                    )
                  : OutlinedButton.icon(
                      icon: const Icon(Icons.star_outline, size: 15),
                      label: const Text('Leave a review',
                          style: TextStyle(fontSize: 12)),
                      onPressed: _busy ? null : () => _leave(role),
                    ),
          ],
        ),
        if (_flash != null) ...[
          const SizedBox(height: 8),
          ResultBanner(_flash!),
        ],
      ],
    );
  }

  Future<void> _remove() => _run(
        () => _api.delete('/api/feedback/${_b.bookingId}/$_myRole'),
        'Review removed.',
      );

  Future<void> _leave(String role) async {
    double rating = 4.5;
    final comment = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(role == 'TUTEE'
              ? 'How was ${_b.tutorName}?'
              : 'How was ${_b.tuteeName}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rating  ${rating.toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 13)),
              Slider(
                value: rating,
                min: 1,
                max: 5,
                divisions: 8,
                label: rating.toStringAsFixed(1),
                onChanged: (v) => setLocal(() => rating = v),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: comment,
                maxLines: 3,
                maxLength: 400,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'What went well, or what did not',
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
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );

    final text = comment.text.trim();
    comment.dispose();
    if (ok != true || !mounted) return;

    await _run(
      () => _api.post('/api/feedback/${_b.bookingId}',
          body: {'role': role, 'rating': rating, 'comments': text}),
      'Review saved.',
    );
  }
}
