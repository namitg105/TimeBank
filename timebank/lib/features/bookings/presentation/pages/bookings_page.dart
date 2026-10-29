import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../domain/entities/booking.dart';
import '../bloc/booking_bloc.dart';
import '../widgets/booking_card.dart';
import '../widgets/session_code_dialog.dart';
import 'book_session_page.dart';

/// The session list, filterable by status.
class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  String? _filter;

  static const _filters = <String?, String>{
    null: 'All',
    'CONFIRMED': 'Upcoming',
    'COMPLETED': 'Finished',
    'CANCELLED': 'Cancelled',
    'DISPUTED': 'Disputed',
  };

  @override
  void initState() {
    super.initState();
    context.read<BookingBloc>().add(const BookingsRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(
            tooltip: 'Book a session',
            icon: const Icon(Icons.add_circle_outline, size: 21),
            onPressed: _openBooking,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            filters: _filters,
            selected: _filter,
            onSelect: (f) {
              setState(() => _filter = f);
              context.read<BookingBloc>().add(BookingsRequested(status: f));
            },
          ),
          Expanded(
            child: BlocConsumer<BookingBloc, BookingState>(
              listenWhen: (_, s) =>
                  s is BookingCreated ||
                  s is BookingActionSuccess ||
                  s is BookingFailure,
              listener: (context, state) {
                switch (state) {
                  // A new booking shows its session code in a dialog. It
                  // is displayed once, and the tutee has to keep it: the
                  // tutor types it in at the start of the session, which
                  // is what proves the tutee actually turned up.
                  case BookingCreated(
                      :final bookingId,
                      :final sessionCode,
                      :final creditsHeld
                    ):
                    showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => SessionCodeDialog(
                        bookingId: bookingId,
                        sessionCode: sessionCode,
                        creditsHeld: creditsHeld,
                      ),
                    );
                  case BookingActionSuccess(:final message):
                    _toast(message, AppColors.positive);
                  case BookingFailure(:final message, :final isRule)
                      when isRule:
                    _toast(message, AppColors.negative);
                  default:
                    break;
                }
              },
              buildWhen: (_, s) =>
                  s is BookingLoading ||
                  s is BookingsLoaded ||
                  (s is BookingFailure && !s.isRule),
              builder: (context, state) => switch (state) {
                BookingLoading() =>
                  const LoadingView(label: 'Reading from Oracle'),
                BookingFailure(:final message) => ErrorView(
                    message: message,
                    onRetry: () => context
                        .read<BookingBloc>()
                        .add(BookingsRequested(status: _filter)),
                  ),
                BookingsLoaded(:final bookings) =>
                  _BookingList(bookings: bookings, filter: _filter),
                _ => const LoadingView(),
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openBooking() {
    final bloc = context.read<BookingBloc>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: const BookSessionPage(),
      ),
    ));
  }

  void _toast(String message, Color tint) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(
              tint == AppColors.positive
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 17,
              color: tint,
            ),
            const SizedBox(width: 11),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 5),
      ));
  }
}

// ---------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  final Map<String?, String> filters;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: filters.entries.map((e) {
            final active = e.key == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(e.key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accentWash
                        : AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active ? AppColors.accentDim : AppColors.border,
                    ),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
}

class _BookingList extends StatelessWidget {
  final List<Booking> bookings;
  final String? filter;

  const _BookingList({required this.bookings, required this.filter});

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return EmptyState(
        icon: Icons.event_busy_outlined,
        title: filter == null ? 'No sessions yet' : 'Nothing here',
        hint: filter == null
            ? 'Book the first one with the + button above.'
            : 'No sessions with that status.',
      );
    }

    final escrow = bookings
        .where((b) => b.isUpcoming)
        .fold<double>(0, (sum, b) => sum + b.creditsHeld);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: bookings.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              escrow > 0
                  ? '${bookings.length} sessions  ·  '
                      '${escrow.toStringAsFixed(1)} credits in escrow'
                  : '${bookings.length} sessions',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return BookingCard(booking: bookings[i - 1]);
      },
    );
  }
}
