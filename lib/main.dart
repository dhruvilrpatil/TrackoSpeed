import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'core/di/injection.dart';
import 'core/error/error_handler.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/preferences_service.dart';
import 'core/services/adaptive_learning_service.dart';
import 'core/services/speed_calculator_service.dart';
import 'features/speed_tracking/presentation/bloc/speed_tracking_bloc.dart';
import 'features/speed_tracking/presentation/pages/dashboard_page.dart';
import 'features/speed_tracking/presentation/pages/camera_mode_page.dart';
import 'features/speed_tracking/presentation/pages/settings_page.dart';

/// Global service locator instance
final GetIt getIt = GetIt.instance;

/// Global theme provider
late final ThemeProvider themeProvider;

/// Application entry point with comprehensive error handling
void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      await initializeDependencies();

      // Initialize adaptive learning AI (loads learned parameters from disk)
      await getIt<AdaptiveLearningService>().initialize();

      // Wire adaptive learning into speed calculator for AI-tuned parameters
      getIt<SpeedCalculatorService>()
          .attachLearningService(getIt<AdaptiveLearningService>());

      // Initialise theme provider
      themeProvider = ThemeProvider(getIt<PreferencesService>());
      await themeProvider.init();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        GlobalErrorHandler.handleFlutterError(details);
      };

      runApp(const TrackoSpeedApp());
    },
    (error, stackTrace) {
      GlobalErrorHandler.handleUncaughtError(error, stackTrace);
    },
  );
}

/// Initialize all dependencies using GetIt service locator
Future<void> initializeDependencies() async {
  try {
    await setupDependencies(getIt);
  } catch (e, stackTrace) {
    // Log error but continue - app should still work with reduced functionality
    debugPrint('Dependency injection error: $e\n$stackTrace');
  }
}

/// Root application widget
///
/// Provides BLoC instances to the widget tree and configures the app theme.
class TrackoSpeedApp extends StatelessWidget {
  const TrackoSpeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SpeedTrackingBloc>(
          create: (_) => getIt<SpeedTrackingBloc>(),
        ),
      ],
      child: ListenableBuilder(
        listenable: themeProvider,
        builder: (context, _) {
          return MaterialApp(
            title: 'TrackoSpeed',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SafeAppWrapper(child: DashboardPage()),
            routes: {
              '/camera': (context) =>
                  const SafeAppWrapper(child: CameraModePage()),
              '/settings': (context) =>
                  const SafeAppWrapper(child: SettingsPage()),
            },
            builder: (context, child) {
              ErrorWidget.builder = (FlutterErrorDetails details) {
                return _buildErrorWidget(context, details);
              };
              return child ?? const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }

  /// Build a user-friendly error widget instead of red error screen
  Widget _buildErrorWidget(BuildContext context, FlutterErrorDetails details) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The app encountered an error but is still running.',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Safe wrapper that catches errors in child widgets
class SafeAppWrapper extends StatefulWidget {
  final Widget child;

  const SafeAppWrapper({super.key, required this.child});

  @override
  State<SafeAppWrapper> createState() => _SafeAppWrapperState();
}

class _SafeAppWrapperState extends State<SafeAppWrapper> {
  bool _hasError = false;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 80,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Application Error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage,
                  style: TextStyle(color: Colors.grey[400]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Wrap child in error catcher
    return _ErrorCatcher(
      onError: (error) {
        setState(() {
          _hasError = true;
          _errorMessage = error.toString();
        });
      },
      child: widget.child,
    );
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });
  }
}

/// Widget that catches errors in its child tree
class _ErrorCatcher extends StatelessWidget {
  final Widget child;
  final void Function(Object error) onError;

  const _ErrorCatcher({
    required this.child,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

