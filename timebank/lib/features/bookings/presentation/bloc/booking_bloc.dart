import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/booking.dart';
import '../../domain/usecases/booking_usecases.dart';

// ----------------------------------------------------------------- events

sealed class BookingEvent extends Equatable {
  const BookingEvent();
  @override
  List<Object?> get props => [];
}

final class BookingsRequested extends BookingEvent {
  final String? status;
  const BookingsRequested({this.status});
  @override
  List<Object?> get props => [status];
}

final class SessionBooked extends BookingEvent {
  final BookSessionParams params;
  const SessionBooked(this.params);
  @override
  List<Object?> get props => [params];
}

final class SessionCheckedIn extends BookingEvent {
  final int bookingId;
  final String code;
  const SessionCheckedIn(this.bookingId, this.code);
  @override
  List<Object?> get props => [bookingId, code];
}

final class SessionConfirmed extends BookingEvent {
  final int bookingId;
  final String role;
  const SessionConfirmed(this.bookingId, this.role);
  @override
  List<Object?> get props => [bookingId, role];
}

final class SessionCancelled extends BookingEvent {
  final int bookingId;
  final String byRole;
  const SessionCancelled(this.bookingId, this.byRole);
  @override
  List<Object?> get props => [bookingId, byRole];
}

// ----------------------------------------------------------------- states

sealed class BookingState extends Equatable {
  const BookingState();
  @override
  List<Object?> get props => [];
}

final class BookingInitial extends BookingState {
  const BookingInitial();
}

final class BookingLoading extends BookingState {
  const BookingLoading();
}

final class BookingsLoaded extends BookingState {
  final List<Booking> bookings;
  final String? filter;
  const BookingsLoaded(this.bookings, {this.filter});
  @override
  List<Object?> get props => [bookings, filter];
}

/// Carries the session code back after a successful booking.
///
/// It is its own state because the code is shown once, in a dialog, and
/// the tutee has to write it down -- it is not part of the list.
final class BookingCreated extends BookingState {
  final int bookingId;
  final String sessionCode;
  final double creditsHeld;
  const BookingCreated(this.bookingId, this.sessionCode, this.creditsHeld);
  @override
  List<Object?> get props => [bookingId, sessionCode];
}

final class BookingActionSuccess extends BookingState {
  final String message;
  const BookingActionSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

final class BookingFailure extends BookingState {
  final String message;
  final bool isRule;
  const BookingFailure(this.message, {this.isRule = false});
  @override
  List<Object?> get props => [message, isRule];
}

// ------------------------------------------------------------------ bloc

class BookingBloc extends Bloc<BookingEvent, BookingState> {
  final GetBookings getBookings;
  final BookSession bookSession;
  final CheckInSession checkInSession;
  final ConfirmSession confirmSession;
  final CancelSession cancelSession;

  String? _lastFilter;

  BookingBloc({
    required this.getBookings,
    required this.bookSession,
    required this.checkInSession,
    required this.confirmSession,
    required this.cancelSession,
  }) : super(const BookingInitial()) {
    on<BookingsRequested>(_onRequested);
    on<SessionBooked>(_onBooked);
    on<SessionCheckedIn>(_onCheckedIn);
    on<SessionConfirmed>(_onConfirmed);
    on<SessionCancelled>(_onCancelled);
  }

  Future<void> _onRequested(
      BookingsRequested event, Emitter<BookingState> emit) async {
    _lastFilter = event.status;
    emit(const BookingLoading());
    final result = await getBookings(event.status);
    emit(result.fold(
      (f) => BookingFailure(f.message, isRule: _isRule(f)),
      (list) => BookingsLoaded(list, filter: event.status),
    ));
  }

  Future<void> _onBooked(
      SessionBooked event, Emitter<BookingState> emit) async {
    emit(const BookingLoading());
    final result = await bookSession(event.params);

    await result.fold(
      (f) async => emit(BookingFailure(f.message, isRule: _isRule(f))),
      (pair) async {
        final (id, code) = pair;
        emit(BookingCreated(id, code, event.params.durationHours));
        add(BookingsRequested(status: _lastFilter));
      },
    );
  }

  Future<void> _onCheckedIn(
      SessionCheckedIn event, Emitter<BookingState> emit) async {
    final result = await checkInSession((event.bookingId, event.code));
    await _finish(result, emit);
  }

  Future<void> _onConfirmed(
      SessionConfirmed event, Emitter<BookingState> emit) async {
    final result = await confirmSession((event.bookingId, event.role));
    await _finish(result, emit);
  }

  Future<void> _onCancelled(
      SessionCancelled event, Emitter<BookingState> emit) async {
    final result = await cancelSession((event.bookingId, event.byRole));
    await _finish(result, emit);
  }

  /// Shared tail for the three write actions: report, then reload.
  Future<void> _finish(
      Either<Failure, String> result, Emitter<BookingState> emit) async {
    await result.fold(
      (f) async => emit(BookingFailure(f.message, isRule: _isRule(f))),
      (message) async {
        emit(BookingActionSuccess(message));
        add(BookingsRequested(status: _lastFilter));
      },
    );
  }

  static bool _isRule(Failure f) => switch (f) {
        RuleFailure() || ValidationFailure() => true,
        NetworkFailure() || ServerFailure() => false,
      };
}
