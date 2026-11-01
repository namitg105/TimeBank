import 'package:get_it/get_it.dart';

import '../network/api_client.dart';

import '../../features/students/data/datasources/student_remote_datasource.dart';
import '../../features/students/data/repositories/student_repository_impl.dart';
import '../../features/students/domain/repositories/student_repository.dart';
import '../../features/students/domain/usecases/student_usecases.dart';
import '../../features/students/presentation/bloc/student_bloc.dart';

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

}
