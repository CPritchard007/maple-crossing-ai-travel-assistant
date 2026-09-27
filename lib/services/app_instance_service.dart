import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../platform/instance_lifecycle.dart';
import 'package:http/http.dart' as http;

/// One anonymous ID per running app. It is a correlation ID, not a credential.
final appInstance = AppInstanceService();

enum AppInstanceStatus { initializing, ready, failed }

class AppInstanceService extends ChangeNotifier {
  AppInstanceService({this.client, this.baseUrl});

  final http.Client? client;
  final Uri? baseUrl;
  final String instanceId = _newId();
  AppInstanceStatus status = AppInstanceStatus.initializing;
  bool get registered => status == AppInstanceStatus.ready;
  Future<void>? _initialization;
  Timer? _heartbeatTimer;
  AppLifecycleListener? _lifecycle;
  bool _busy = false;
  bool _closed = false;
  bool _disposed = false;

  Uri get _origin {
    const configured = String.fromEnvironment('BACKEND_URL');
    return baseUrl ??
        (configured.isNotEmpty
            ? Uri.parse(configured)
            : kReleaseMode && kIsWeb
            ? Uri.base
            : Uri.parse('http://localhost:3000'));
  }

  /// Called once by the app entry point; tests can initialize without timers.
  void startTracking() {
    if (_heartbeatTimer != null || _closed) return;
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(heartbeat()),
      onDetach: () => unawaited(close()),
    );
    unawaited(heartbeat());
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(heartbeat()),
    );
  }

  Future<void> heartbeat() async {
    if (_busy || _closed || _disposed) return;
    _busy = true;
    try {
      if (!registered) {
        // Repeat registration after outages using the same launch ID.
        await initialize();
        if (!registered) _initialization = null;
      }
      if (!registered || _closed || _disposed) return;
      installInstanceClose(
        _origin.resolve('/api/instances/$instanceId?action=close').toString(),
      );
      final response = await _sendLifecycle('heartbeat');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['status'] != 'active') {
        status = AppInstanceStatus.failed;
      }
    } catch (_) {
      status = AppInstanceStatus.failed;
    } finally {
      _busy = false;
      if (!registered) _initialization = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<http.Response> _sendLifecycle(String action) async {
    final requestClient = client ?? http.Client();
    try {
      return await requestClient
          .post(_origin.resolve('/api/instances/$instanceId?action=$action'))
          .timeout(const Duration(seconds: 10));
    } finally {
      if (client == null) requestClient.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeatTimer?.cancel();
    removeInstanceClose();
    // If registration is in flight, close its record once it completes.
    await _initialization;
    try {
      await _sendLifecycle('close');
    } catch (_) {
      // The backend lease expires if shutdown prevents delivery.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeatTimer?.cancel();
    _lifecycle?.dispose();
    removeInstanceClose();
    super.dispose();
  }

  Future<void> initialize() => _initialization ??= _register();

  Future<void> _register() async {
    final requestClient = client ?? http.Client();
    try {
      final endpoint = _origin.resolve('/api/initialize');
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final response = await requestClient
              .post(
                endpoint,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'instanceId': instanceId,
                  'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
                }),
              )
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body) as Map<String, dynamic>;
            if (body['instanceId'] != instanceId) {
              throw const FormatException('Instance ID mismatch');
            }
            status = AppInstanceStatus.ready;
            return;
          }
          if (response.statusCode < 500 && response.statusCode != 429) {
            return;
          }
        } catch (_) {
          // Registration must never prevent the map from starting.
        }
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
      debugPrint('Anonymous app registration unavailable.');
    } catch (_) {
      debugPrint('Anonymous app registration configuration invalid.');
    } finally {
      if (!registered) status = AppInstanceStatus.failed;
      if (client == null) requestClient.close();
      if (!_disposed) notifyListeners();
    }
  }

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
