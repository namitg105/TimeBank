import 'package:get_it/get_it.dart';

import '../network/api_client.dart';

import '../../features/students/data/datasources/student_remote_datasource.dart';
import '../../features/students/data/repositories/student_repository_impl.dart';
import '../../features/students/domain/repositories/student_repository.dart';
import '../../features/students/domain/usecases/student_usecases.dart';
import '../../features/students/presentation/bloc/student_bloc.dart';

import '../../features/bookings/data/datasources/booking_remote_datasource.dart';
import '../../features/bookings/data/repositories/booking_repository_impl.dart';
import '../../features/bookings/domain/repositories/booking_repository.dart';
import '../../features/bookings/domain/usecases/booking_usecases.dart';
import '../../features/bookings/presentation/bloc/booking_bloc.dart';

import '../../features/ledger/data/datasources/ledger_remote_datasource.dart';
import '../../features/ledger/data/repositories/ledger_repository_impl.dart';
import '../../features/ledger/domain/repositories/ledger_repository.dart';
import '../../features/ledger/domain/usecases/ledger_usecases.dart';
import '../../features/ledger/presentation/bloc/ledger_bloc.dart';

/// The service locator.
final sl = GetIt.instance;

/// Wires everything together, outside in.
///
/// Registration order matters because each layer depends on the one
/// below it:
///
///     ApiClient  ->  DataSource  ->  Repository  ->  UseCase  ->  Bloc
///
/// Note that the repository is registered against its INTERFACE, not its
/// implementation. Nothing above the data layer ever names
/// StudentRepositoryImpl, so swapping in a fake for testing, or a
/// different backend later, is a one-line change here.
///
/// lazySingleton for everything stateless: created once, on first use.
/// factory for Blocs, because each page needs its own instance with its
/// own state.
Future<void> initDependencies({String? baseUrl}) async {
  // ---- core --------------------------------------------------------
  sl.registerLazySingleton<ApiClient>(() => ApiClient(baseUrl: baseUrl));

  // ---- students ----------------------------------------------------
  sl
    ..registerLazySingleton<StudentRemoteDataSource>(
        () => StudentRemoteDataSourceImpl(sl()))
    ..registerLazySingleton<StudentRepository>(
        () => StudentRepositoryImpl(sl()))
    ..registerLazySingleton(() => GetStudents(sl()))
    ..registerLazySingleton(() => SearchStudents(sl()))
    ..registerLazySingleton(() => RegisterStudent(sl()))
    ..registerLazySingleton(() => DeactivateStudent(sl()))
    ..registerFactory(() => StudentBloc(
          getStudents: sl(),
          searchStudents: sl(),
          registerStudent: sl(),
          deactivateStudent: sl(),
        ));

  // ---- bookings ----------------------------------------------------
  sl
    ..registerLazySingleton<BookingRemoteDataSource>(
        () => BookingRemoteDataSourceImpl(sl()))
    ..registerLazySingleton<BookingRepository>(
        () => BookingRepositoryImpl(sl()))
    ..registerLazySingleton(() => GetBookings(sl()))
    ..registerLazySingleton(() => BookSession(sl()))
    ..registerLazySingleton(() => CheckInSession(sl()))
    ..registerLazySingleton(() => ConfirmSession(sl()))
    ..registerLazySingleton(() => CancelSession(sl()))
    ..registerFactory(() => BookingBloc(
          getBookings: sl(),
          bookSession: sl(),
          checkInSession: sl(),
          confirmSession: sl(),
          cancelSession: sl(),
        ));

  // ---- ledger ------------------------------------------------------
  sl
    ..registerLazySingleton<LedgerRemoteDataSource>(
        () => LedgerRemoteDataSourceImpl(sl()))
    ..registerLazySingleton<LedgerRepository>(
        () => LedgerRepositoryImpl(sl()))
    ..registerLazySingleton(() => GetPassbook(sl()))
    ..registerLazySingleton(() => RunAudit(sl()))
    ..registerLazySingleton(() => PostAdjustment(sl()))
    ..registerLazySingleton(() => GetLeaderboard(sl()))
    ..registerLazySingleton(() => GetCollusionReport(sl()))
    ..registerFactory(() => LedgerBloc(
          getPassbook: sl(),
          runAudit: sl(),
          postAdjustment: sl(),
          getLeaderboard: sl(),
          getCollusionReport: sl(),
        ));
}
