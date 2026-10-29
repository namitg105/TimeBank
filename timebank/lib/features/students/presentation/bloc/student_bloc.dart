import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../../domain/entities/student.dart';
import '../../domain/usecases/student_usecases.dart';

// ----------------------------------------------------------------- events

sealed class StudentEvent extends Equatable {
  const StudentEvent();
  @override
  List<Object?> get props => [];
}

final class StudentsRequested extends StudentEvent {
  const StudentsRequested();
}

final class StudentsSearched extends StudentEvent {
  final String query;
  const StudentsSearched(this.query);
  @override
  List<Object?> get props => [query];
}

final class StudentRegistered extends StudentEvent {
  final RegisterStudentParams params;
  const StudentRegistered(this.params);
  @override
  List<Object?> get props => [params];
}

final class StudentDeactivated extends StudentEvent {
  final int studentId;
  const StudentDeactivated(this.studentId);
  @override
  List<Object?> get props => [studentId];
}

// ----------------------------------------------------------------- states

sealed class StudentState extends Equatable {
  const StudentState();
  @override
  List<Object?> get props => [];
}

final class StudentInitial extends StudentState {
  const StudentInitial();
}

final class StudentLoading extends StudentState {
  const StudentLoading();
}

final class StudentsLoaded extends StudentState {
  final List<Student> students;
  final String query;
  const StudentsLoaded(this.students, {this.query = ''});
  @override
  List<Object?> get props => [students, query];
}

final class StudentFailure extends StudentState {
  final String message;

  /// True when a database rule refused the request rather than something
  /// breaking. The UI shows these differently: a rule is the user's to
  /// act on, a fault gets a retry button.
  final bool isRule;

  const StudentFailure(this.message, {this.isRule = false});
  @override
  List<Object?> get props => [message, isRule];
}

/// Emitted once after a write succeeds, so the page can show a snackbar.
final class StudentActionSuccess extends StudentState {
  final String message;
  const StudentActionSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

// ------------------------------------------------------------------ bloc

/// Holds the student screen's state.
///
/// The widgets below never call a use case directly: they add an event
/// and rebuild on whatever state comes back. That is what makes the UI
/// replaceable — the same Bloc would drive a web layout or a tablet
/// layout without changing a line.
class StudentBloc extends Bloc<StudentEvent, StudentState> {
  final GetStudents getStudents;
  final SearchStudents searchStudents;
  final RegisterStudent registerStudent;
  final DeactivateStudent deactivateStudent;

  StudentBloc({
    required this.getStudents,
    required this.searchStudents,
    required this.registerStudent,
    required this.deactivateStudent,
  }) : super(const StudentInitial()) {
    on<StudentsRequested>(_onRequested);
    on<StudentsSearched>(_onSearched);
    on<StudentRegistered>(_onRegistered);
    on<StudentDeactivated>(_onDeactivated);
  }

  Future<void> _onRequested(
      StudentsRequested event, Emitter<StudentState> emit) async {
    emit(const StudentLoading());
    final result = await getStudents(const NoParams());
    // fold forces both branches to be handled. There is no way to read
    // the success value without having written the failure case.
    emit(result.fold(
      (f) => StudentFailure(f.message, isRule: _isRule(f)),
      (students) => StudentsLoaded(students),
    ));
  }

  Future<void> _onSearched(
      StudentsSearched event, Emitter<StudentState> emit) async {
    emit(const StudentLoading());
    final result = await searchStudents(event.query);
    emit(result.fold(
      (f) => StudentFailure(f.message, isRule: _isRule(f)),
      (students) => StudentsLoaded(students, query: event.query),
    ));
  }

  Future<void> _onRegistered(
      StudentRegistered event, Emitter<StudentState> emit) async {
    emit(const StudentLoading());
    final result = await registerStudent(event.params);

    await result.fold(
      (f) async => emit(StudentFailure(f.message, isRule: _isRule(f))),
      (student) async {
        emit(StudentActionSuccess(
            '${student.fullName} registered with '
            '${student.creditBalance.toStringAsFixed(1)} starter credits.'));
        // Reload so the new row appears without the page asking.
        add(const StudentsRequested());
      },
    );
  }

  Future<void> _onDeactivated(
      StudentDeactivated event, Emitter<StudentState> emit) async {
    final result = await deactivateStudent(event.studentId);
    await result.fold(
      (f) async => emit(StudentFailure(f.message, isRule: _isRule(f))),
      (message) async {
        emit(StudentActionSuccess(message));
        add(const StudentsRequested());
      },
    );
  }

  /// Failure is a sealed class, so this switch is exhaustive -- adding a
  /// new kind of Failure makes the compiler point here.
  static bool _isRule(Failure f) => switch (f) {
        RuleFailure() || ValidationFailure() => true,
        NetworkFailure() || ServerFailure() => false,
      };
}
