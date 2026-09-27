import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final ttsService = TtsService();

/// Audio output is injectable so synthesis and cancellation can be tested.
abstract class SpeechAudio {
  Future<void> play(Uint8List bytes, double rate, double volume);
  Future<void> get done;
  Future<void> dispose();
}

class _PollyAudio implements SpeechAudio {
  final _player = AudioPlayer();
  final _done = Completer<void>();
  StreamSubscription<void>? _completion;
  Future<void>? _starting;
  Future<void>? _disposal;
  bool _disposed = false;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> play(Uint8List bytes, double rate, double volume) =>
      _starting = _start(bytes, rate, volume);

  Future<void> _start(Uint8List bytes, double rate, double volume) async {
    _completion = _player.onPlayerComplete.listen(
      (_) {
        if (!_done.isCompleted) _done.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (!_done.isCompleted) _done.completeError(error, stack);
      },
    );
    await _player.setPlaybackRate(rate);
    if (_disposed) return;
    await _player.play(
      BytesSource(bytes, mimeType: 'audio/mpeg'),
      volume: volume,
    );
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    try {
      await _starting;
    } catch (_) {}
    await _completion?.cancel();
    await _player.dispose();
    if (!_done.isCompleted) _done.complete();
  }
}

/// Synthesizes through the backend; AWS credentials never enter the app.
class TtsService {
  TtsService({
    this.baseUrl,
    http.Client Function()? clientFactory,
    SpeechAudio Function()? audioFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _audioFactory = audioFactory ?? _PollyAudio.new;

  final Uri? baseUrl;
  final http.Client Function() _clientFactory;
  final SpeechAudio Function() _audioFactory;
  _SpeechRequest? _active;

  bool get isSupported =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.fuchsia;

  Uri get _endpoint {
    const configured = String.fromEnvironment('BACKEND_URL');
    return (baseUrl ??
            (configured.isNotEmpty
                ? Uri.parse(configured)
                : kReleaseMode && kIsWeb
                ? Uri.base
                : Uri.parse('http://localhost:3000')))
        .resolve('/api/speech');
  }

  Future<void> speakAndWait(String text) =>
      speak(text, waitForCompletion: true);

  /// Replaces previous speech. Rate 0.5 means normal playback speed.
  /// Polly Neural does not support pitch adjustment; pitch must remain 1.
  Future<void> speak(
    String text, {
    String language = 'en-CA',
    double rate = 0.5,
    double volume = 1,
    double pitch = 1,
    bool waitForCompletion = false,
  }) {
    if (text.trim().isEmpty) return Future<void>.value();
    if (!const ['en-CA', 'en-US', 'fr-CA'].contains(language)) {
      throw ArgumentError.value(language, 'language');
    }
    _checkRange(rate, 'rate', 0, 1);
    _checkRange(volume, 'volume', 0, 1);
    if (pitch != 1) {
      throw ArgumentError.value(
        pitch,
        'pitch',
        'Polly Neural requires pitch 1',
      );
    }
    if (!isSupported) {
      return Future.error(UnsupportedError('Audio unavailable'));
    }
    final previous = _active;
    final request = _SpeechRequest(_clientFactory());
    _active = request;
    final operation = _run(
      request,
      previous,
      text.trim(),
      language,
      rate,
      volume,
    );
    // Always observe background failures, even when the caller only waits for submission.
    unawaited(
      operation.then(
        (_) {
          if (!request.started.isCompleted) request.started.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!request.started.isCompleted) {
            request.started.completeError(error, stack);
          } else if (!waitForCompletion) {
            debugPrint('Speech playback failed: $error');
          }
        },
      ),
    );
    return waitForCompletion
        ? Future.wait<void>([request.started.future, operation]).then((_) {})
        : request.started.future;
  }

  Future<void> _run(
    _SpeechRequest request,
    _SpeechRequest? previous,
    String text,
    String language,
    double rate,
    double volume,
  ) async {
    try {
      await previous?.cancel();
      // Bound each request to Polly's synchronous input limit without splitting Unicode.
      final characters = text.runes.toList();
      for (var offset = 0; offset < characters.length; offset += 2800) {
        if (request.cancelled) return;
        final end = (offset + 2800).clamp(0, characters.length);
        final chunk = String.fromCharCodes(
          characters.sublist(offset, end),
        ).trim();
        if (chunk.isEmpty) continue;
        final response = await Future.any<http.Response?>([
          request.client
              .post(
                _endpoint,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'text': chunk, 'language': language}),
              )
              .timeout(const Duration(seconds: 20)),
          request.stopped.future.then((_) => null),
        ]);
        if (request.cancelled || response == null) return;
        if (response.statusCode != 200 ||
            response.bodyBytes.isEmpty ||
            !(response.headers['content-type'] ?? '').startsWith(
              'audio/mpeg',
            )) {
          throw StateError(
            'Speech synthesis failed (HTTP ${response.statusCode})',
          );
        }
        final audio = request.audio = _audioFactory();
        // Install the error listener before playback starts.
        final finished = audio.done;
        unawaited(finished.catchError((Object _) {}));
        await audio.play(response.bodyBytes, (rate * 2).clamp(0.1, 2), volume);
        if (!request.started.isCompleted) request.started.complete();
        if (request.cancelled) return;
        await finished;
        await audio.dispose();
        request.audio = null;
      }
    } catch (_) {
      if (!request.cancelled) rethrow;
    } finally {
      await request.cancel();
      if (identical(_active, request)) _active = null;
    }
  }

  Future<void> stop() async {
    final request = _active;
    _active = null;
    await request?.cancel();
  }

  static void _checkRange(double value, String name, double min, double max) {
    if (!value.isFinite || value < min || value > max) {
      throw ArgumentError.value(value, name, 'Must be between $min and $max');
    }
  }
}

class _SpeechRequest {
  _SpeechRequest(this.client);
  final http.Client client;
  final started = Completer<void>();
  final stopped = Completer<void>();
  SpeechAudio? audio;
  bool cancelled = false;
  Future<void>? _cancellation;

  Future<void> cancel() => _cancellation ??= _cancel();
  Future<void> _cancel() async {
    cancelled = true;
    stopped.complete();
    client.close();
    await audio?.dispose();
  }
}
