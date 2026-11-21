/// Auto-starts and manages the ML backend FastAPI server.
///
/// On app start: checks if backend is reachable; if not, launches
/// `uvicorn ml_backend.server:app --host 127.0.0.1 --port 8000`
/// from the `ml_backend` directory with the project's virtual environment.
///
/// On app exit: gracefully terminates the backend process.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Prints a log message with [BackendService] prefix.
void _log(String message) {
  // ignore: avoid_print
  print('[BackendService] $message');
}

/// Manages the ML backend lifecycle.
class BackendService {
  BackendService._();

  static final BackendService _instance = BackendService._();

  static BackendService get instance => _instance;

  Process? _backendProcess;
  Timer? _healthCheckTimer;
  bool _isStarting = false;
  final _stateController = StreamController<BackendState>.broadcast();

  /// Current backend state stream.
  Stream<BackendState> get stateStream => _stateController.stream;

  /// Current backend state.
  BackendState _currentState = BackendState.stopped;

  BackendState get currentState => _currentState;

  /// Base URL for the backend API.
  String get baseUrl => 'http://127.0.0.1:8000';

  /// Health check endpoint.
  String get healthUrl => '$baseUrl/health';

  /// Starts the backend if not already running.
  ///
  /// Returns true if backend is ready (either was already running or started successfully).
  Future<bool> ensureRunning() async {
    // Already running?
    if (await _isHealthy()) {
      _log('Backend already running at $baseUrl');
      _updateState(BackendState.running);
      return true;
    }

    // Already starting?
    if (_isStarting) {
      _log('Backend already starting at $baseUrl, waiting...');
      // Wait for startup to complete
      await _waitForState(BackendState.running,
          timeout: const Duration(seconds: 180));
      return _currentState == BackendState.running;
    }

    _log('Starting backend at $baseUrl...');
    _isStarting = true;
    _updateState(BackendState.starting);

    try {
      await _startBackend();
      final ready = await _waitForState(BackendState.running,
          timeout: const Duration(seconds: 180));
      _log('Backend startup ${ready ? 'succeeded' : 'failed'}');
      return ready;
    } catch (e) {
      _log('Backend startup error: $e');
      _updateState(BackendState.failed);
      return false;
    } finally {
      _isStarting = false;
    }
  }

  /// Starts the uvicorn server as a subprocess.
  Future<void> _startBackend() async {
    _log('Starting ML backend...');
    final mlBackendDir = _getMlBackendDirectory();
    final pythonExecutable = _getPythonExecutable(mlBackendDir);

    _log('Using Python: $pythonExecutable');
    _log('Working directory: ${mlBackendDir.path}');

    if (!await File(pythonExecutable).exists()) {
      _log('ERROR: Python executable not found at $pythonExecutable');
      throw StateError('Python executable not found at $pythonExecutable. '
          'Run "pip install -e .[dev]" in ml_backend directory first.');
    }

    _log('Starting uvicorn server...');
    _backendProcess = await Process.start(
      pythonExecutable,
      [
        '-m',
        'uvicorn',
        'ml_backend.server:app',
        '--host',
        '127.0.0.1',
        '--port',
        '8000'
      ],
      workingDirectory: mlBackendDir.path,
      mode: ProcessStartMode.inheritStdio,
    );

    _log('Backend process started (PID: ${_backendProcess!.pid})');

    unawaited(_backendProcess!.exitCode.then((code) {
      _log('Backend process exited with code: $code');
      if (_currentState == BackendState.running) {
        _updateState(BackendState.stopped);
      }
    }));

    // Start periodic health checks
    _startHealthChecks();
  }

  /// Waits for backend to reach a specific state.
  Future<bool> _waitForState(BackendState target,
      {required Duration timeout}) async {
    final completer = Completer<bool>();
    late StreamSubscription<BackendState> subscription;

    subscription = stateStream.listen((state) {
      if (state == target) {
        subscription.cancel();
        completer.complete(true);
      } else if (state == BackendState.failed) {
        subscription.cancel();
        completer.complete(false);
      }
    });

    // Timeout fallback
    Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(false);
      }
    });

    return completer.future;
  }

  /// Starts periodic health checks after a brief delay to allow the server to fully start.
  void _startHealthChecks() {
    _healthCheckTimer?.cancel();
    // Delay the first health check to allow the server to fully start accepting connections.
    // Uvicorn reports "Application startup complete" before the server is fully ready to accept connections.
    _healthCheckTimer = Timer(const Duration(seconds: 3), () {
      _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (!await _isHealthy()) {
          _updateState(BackendState.failed);
        }
      });
    });
  }

  /// Checks if backend is healthy.
  Future<bool> _isHealthy() async {
    try {
      _log('Checking health at $healthUrl...');
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 3));
      final healthy = response.statusCode == 200;
      _log(
          'Health check: ${healthy ? 'HEALTHY' : 'UNHEALTHY (status: ${response.statusCode})'}');
      return healthy;
    } catch (e) {
      _log('Health check failed at $baseUrl: $e');
      return false;
    }
  }

  /// Updates state and notifies listeners.
  void _updateState(BackendState state) {
    if (_currentState != state) {
      _currentState = state;
      _stateController.add(state);
    }
  }

  /// Gets the ml_backend directory path.
  Directory _getMlBackendDirectory() {
    // When running from build directory, ml_backend is at project root
    final currentDir = Directory.current;
    final projectRoot = currentDir.path.contains('build')
        ? Directory(currentDir.path.split('build').first).parent
        : currentDir;
    return Directory('${projectRoot.path}/ml_backend');
  }

  /// Gets the python executable from the virtual environment.
  String _getPythonExecutable(Directory mlBackendDir) {
    // Prefer virtual environment
    final venvPython = File('${mlBackendDir.path}/.venv/bin/python');
    if (venvPython.existsSync()) {
      return venvPython.path;
    }
    // Fallback to system python - resolve full path using `which`
    final result = Process.runSync('which', ['python3']);
    if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
      return result.stdout.toString().trim();
    }
    // Last resort: assume python3 is in PATH
    return 'python3';
  }

  /// Shuts down the backend process.
  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    if (_backendProcess != null) {
      _backendProcess!.kill(ProcessSignal.sigterm);
      try {
        await _backendProcess!.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        _backendProcess!.kill(ProcessSignal.sigkill);
      }
      _backendProcess = null;
    }
    _updateState(BackendState.stopped);
    await _stateController.close();
  }
}

/// Backend lifecycle states.
enum BackendState {
  stopped,
  starting,
  running,
  failed,
}
