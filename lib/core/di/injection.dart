import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../../features/speed_tracking/data/datasources/capture_local_datasource.dart';
import '../../features/speed_tracking/data/repositories/capture_repository_impl.dart';
import '../../features/speed_tracking/domain/repositories/capture_repository.dart';
import '../../features/speed_tracking/domain/usecases/capture_vehicle_usecase.dart';
import '../../features/speed_tracking/domain/usecases/get_capture_history_usecase.dart';
import '../../features/speed_tracking/presentation/bloc/speed_tracking_bloc.dart';
import '../platform/permission_service.dart';
import '../platform/gps_service.dart';
import '../platform/camera_service.dart';
import '../platform/vehicle_detection_service.dart';
import '../platform/image_processing_service.dart';
import '../platform/gallery_service.dart';
import '../platform/ocr_service.dart';
import '../services/speed_calculator_service.dart';
import '../services/vehicle_tracker_service.dart';
import '../services/preferences_service.dart';
import '../services/adaptive_learning_service.dart';
import '../services/dashboard_stats_service.dart';

/// Setup all dependencies using GetIt service locator
///
/// Uses lazy singleton pattern for most services to optimize memory usage.
/// Services are initialized only when first accessed.
Future<void> setupDependencies(GetIt getIt) async {
  // ==================== Database ====================
  await _setupDatabase(getIt);

  // ==================== Platform Services ====================
  _setupPlatformServices(getIt);

  // ==================== Core Services ====================
  _setupCoreServices(getIt);

  // ==================== Data Sources ====================
  _setupDataSources(getIt);

  // ==================== Repositories ====================
  _setupRepositories(getIt);

  // ==================== Use Cases ====================
  _setupUseCases(getIt);

  // ==================== BLoCs ====================
  _setupBlocs(getIt);
}

/// Setup SQLite database
Future<void> _setupDatabase(GetIt getIt) async {
  try {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'trackospeed.db');

    final database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Create captures table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS captures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plate_number TEXT,
            estimated_vehicle_speed REAL NOT NULL,
            user_speed REAL NOT NULL,
            relative_speed REAL NOT NULL,
            gps_accuracy REAL,
            confidence_score REAL,
            image_path TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            session_id TEXT NOT NULL,
            vehicle_class TEXT,
            bounding_box TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''');

        // Create index for faster queries
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_timestamp ON captures(timestamp)
        ''');

        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_session ON captures(session_id)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Handle future schema migrations here
      },
    );

    getIt.registerSingleton<Database>(database);
  } catch (e) {
    // If database fails, register a null placeholder
    // App will handle gracefully with in-memory fallback
    throw Exception('Database initialization failed: $e');
  }
}

/// Setup platform-specific services
void _setupPlatformServices(GetIt getIt) {
  // Permission service - handles all permission requests
  getIt.registerLazySingleton<PermissionService>(
    () => PermissionService(),
  );

  // GPS service - provides location and speed data
  getIt.registerLazySingleton<GpsService>(
    () => GpsService(),
  );

  // Camera service - handles camera initialization and frame capture
  getIt.registerLazySingleton<CameraService>(
    () => CameraService(),
  );

  // Vehicle detection service - ML inference for vehicle detection
  getIt.registerLazySingleton<VehicleDetectionService>(
    () => VehicleDetectionService(),
  );

  // Image processing service - draws overlays on images
  getIt.registerLazySingleton<ImageProcessingService>(
    () => ImageProcessingService(),
  );

  // Gallery service - saves images to device gallery
  getIt.registerLazySingleton<GalleryService>(
    () => GalleryService(),
  );

  // OCR service - license plate text recognition
  getIt.registerLazySingleton<OcrService>(
    () => OcrService(),
  );
}

/// Setup core application services
void _setupCoreServices(GetIt getIt) {
  // Preferences service - manages app preferences and first launch
  getIt.registerLazySingleton<PreferencesService>(
    () => PreferencesService(),
  );

  // Speed calculator - computes relative and target vehicle speeds
  getIt.registerLazySingleton<SpeedCalculatorService>(
    () => SpeedCalculatorService(),
  );

  // Vehicle tracker - tracks vehicles across frames
  getIt.registerLazySingleton<VehicleTrackerService>(
    () => VehicleTrackerService(),
  );

  // Adaptive learning - self-improving AI engine
  getIt.registerLazySingleton<AdaptiveLearningService>(
    () => AdaptiveLearningService(),
  );

  // Dashboard stats - persists AVG, MAX, DIST across launches
  getIt.registerLazySingleton<DashboardStatsService>(
    () => DashboardStatsService(),
  );
}

/// Setup data sources
void _setupDataSources(GetIt getIt) {
  getIt.registerLazySingleton<CaptureLocalDataSource>(
    () => CaptureLocalDataSourceImpl(
      database: getIt<Database>(),
    ),
  );
}

/// Setup repositories
void _setupRepositories(GetIt getIt) {
  getIt.registerLazySingleton<CaptureRepository>(
    () => CaptureRepositoryImpl(
      localDataSource: getIt<CaptureLocalDataSource>(),
      galleryService: getIt<GalleryService>(),
      imageProcessingService: getIt<ImageProcessingService>(),
    ),
  );
}

/// Setup use cases
void _setupUseCases(GetIt getIt) {
  getIt.registerLazySingleton<CaptureVehicleUseCase>(
    () => CaptureVehicleUseCase(
      repository: getIt<CaptureRepository>(),
    ),
  );

  getIt.registerLazySingleton<GetCaptureHistoryUseCase>(
    () => GetCaptureHistoryUseCase(
      repository: getIt<CaptureRepository>(),
    ),
  );
}

/// Setup BLoCs
void _setupBlocs(GetIt getIt) {
  // SpeedTrackingBloc - main application state management
  getIt.registerFactory<SpeedTrackingBloc>(
    () => SpeedTrackingBloc(
      permissionService: getIt<PermissionService>(),
      gpsService: getIt<GpsService>(),
      cameraService: getIt<CameraService>(),
      vehicleDetectionService: getIt<VehicleDetectionService>(),
      ocrService: getIt<OcrService>(),
      speedCalculatorService: getIt<SpeedCalculatorService>(),
      vehicleTrackerService: getIt<VehicleTrackerService>(),
      captureVehicleUseCase: getIt<CaptureVehicleUseCase>(),
      preferencesService: getIt<PreferencesService>(),
      adaptiveLearningService: getIt<AdaptiveLearningService>(),
      dashboardStatsService: getIt<DashboardStatsService>(),
    ),
  );
}

