import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
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
                  label: 'TUTEE',
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
                    '${booking.creditsHeld.toStringAsFixed(1)} credits in '
                    'escrow · ${booking.nextAction}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.accent),
                  ),
                ],
              ),
            ),
          ],

          if (booking.isUpcoming) ...[
            const SizedBox(height: 12),
            _Actions(booking: booking),
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

/// Only the action the session actually needs next is offered.
///
/// Check-in comes before confirmation because the database enforces that
/// order: trg_confirm_after_end refuses a confirmation when check_in_at
/// is still null. Offering both at once would just produce an error.
class _Actions extends StatelessWidget {
  final Booking booking;
  const _Actions({required this.booking});

  @override
  Widget build(BuildContext context) {
    if (!booking.checkedIn) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.key_outlined, size: 16),
              label: const Text('Enter code', style: TextStyle(fontSize: 13)),
              onPressed: () => _askForCode(context),
            ),
          ),
          const SizedBox(width: 9),
          _CancelButton(booking: booking),
        ],
      );
    }

    return Row(
      children: [
        if (!booking.tutorConfirmed)
          Expanded(
            child: _ConfirmButton(bookingId: booking.bookingId, role: 'TUTOR'),
          ),
        if (!booking.tutorConfirmed && !booking.tuteeConfirmed)
          const SizedBox(width: 9),
        if (!booking.tuteeConfirmed)
          Expanded(
            child: _ConfirmButton(bookingId: booking.bookingId, role: 'TUTEE'),
          ),
        const SizedBox(width: 9),
        _CancelButton(booking: booking),
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
              'Ask the tutee to read out the 8-character code they were '
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
  const _ConfirmButton({required this.bookingId, required this.role});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: () =>
            context.read<BookingBloc>().add(SessionConfirmed(bookingId, role)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 11),
          foregroundColor: AppColors.positive,
          side: BorderSide(color: AppColors.positive.withValues(alpha: 0.5)),
        ),
        child: Text(
          role == 'TUTOR' ? 'Tutor confirms' : 'Tutee confirms',
          style: const TextStyle(fontSize: 12.5),
        ),
      );
}

class _CancelButton extends StatelessWidget {
  final Booking booking;
  const _CancelButton({required this.booking});

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
          'Who is cancelling decides where the escrow goes.\n\n'
          'Tutor cancels, or tutee cancels more than 24 hours ahead: '
          'all credits go back to the tutee.\n\n'
          'Tutee cancels inside 24 hours: the credits are split, because '
          'the tutor had already blocked out that hour.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () {
              bloc.add(SessionCancelled(booking.bookingId, 'TUTEE'));
              Navigator.pop(dialogContext);
            },
            child: const Text('Tutee cancels'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negative,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              bloc.add(SessionCancelled(booking.bookingId, 'TUTOR'));
              Navigator.pop(dialogContext);
            },
            child: const Text('Tutor cancels'),
          ),
        ],
      ),
    );
  }
}
