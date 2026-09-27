import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maple_crossing/services/tts_service.dart';

class FakeAudio implements SpeechAudio {
  final completed = Completer<void>();
  final played = Completer<void>();
  bool disposed = false;
  double? rate;
  @override
  Future<void> get done => completed.future;
  @override
  Future<void> play(Uint8List bytes, double rate, double volume) async {
    this.rate = rate;
    played.complete();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!completed.isCompleted) completed.complete();
  }
}

http.Response mp3() => http.Response.bytes(
  [1, 2, 3],
  200,
  headers: {'content-type': 'audio/mpeg'},
);

void main() {
  test('posts text and language; waits for audio completion', () async {
    final audio = FakeAudio();
    final service = TtsService(
      baseUrl: Uri.parse('https://backend.test'),
      clientFactory: () => MockClient((request) async {
        expect(request.url.toString(), 'https://backend.test/api/speech');
        expect(jsonDecode(request.body), {
          'text': 'Bonjour',
          'language': 'fr-CA',
        });
        return mp3();
      }),
      audioFactory: () => audio,
    );
    var finished = false;
    final speech = service
        .speak(' Bonjour ', language: 'fr-CA', waitForCompletion: true)
        .then((_) => finished = true);
    await audio.played.future;
    expect(finished, false);
    expect(audio.rate, 1);
    audio.completed.complete();
    await speech;
    expect(finished, true);
    expect(audio.disposed, true);
  });

  test(
    'stop promptly cancels an in-flight HTTP request and prevents playback',
    () async {
      final submitted = Completer<void>();
      final response = Completer<http.Response>();
      var players = 0;
      final service = TtsService(
        clientFactory: () => MockClient((_) {
          submitted.complete();
          return response.future;
        }),
        audioFactory: () {
          players++;
          return FakeAudio();
        },
      );
      final speech = service.speakAndWait('Hello');
      await submitted.future;
      await service.stop();
      await speech;
      response.complete(mp3());
      await Future<void>.delayed(Duration.zero);
      expect(players, 0);
    },
  );

  test(
    'new speech replaces playback and releases the previous waiter',
    () async {
      final audios = <FakeAudio>[];
      final service = TtsService(
        clientFactory: () => MockClient((_) async => mp3()),
        audioFactory: () {
          final a = FakeAudio();
          audios.add(a);
          return a;
        },
      );
      final first = service.speakAndWait('First');
      await Future<void>.delayed(Duration.zero);
      await service.speak('Second');
      await first;
      expect(audios.first.disposed, true);
      expect(audios.length, 2);
      await service.stop();
    },
  );

  test(
    'backend failure propagates without poisoning subsequent speech',
    () async {
      var fail = true;
      final service = TtsService(
        clientFactory: () => MockClient(
          (_) async => fail ? http.Response('unavailable', 503) : mp3(),
        ),
        audioFactory: FakeAudio.new,
      );
      await expectLater(service.speakAndWait('Hello'), throwsStateError);
      fail = false;
      await service.speak('Retry');
      await service.stop();
    },
  );

  test('long Unicode text is split and played sequentially', () async {
    final chunks = <String>[];
    final audios = <FakeAudio>[];
    final service = TtsService(
      clientFactory: () => MockClient((request) async {
        chunks.add((jsonDecode(request.body) as Map)['text'] as String);
        return mp3();
      }),
      audioFactory: () {
        final a = FakeAudio();
        audios.add(a);
        return a;
      },
    );
    final text = '😀' * 3001;
    final speech = service.speakAndWait(text);
    await Future<void>.delayed(Duration.zero);
    expect(chunks.length, 1);
    audios.first.completed.complete();
    await Future<void>.delayed(Duration.zero);
    expect(chunks.map((c) => c.runes.length), [2800, 201]);
    expect(chunks.join(), text);
    audios.last.completed.complete();
    await speech;
  });

  test('empty text and invalid parameters never make a request', () async {
    final service = TtsService(
      clientFactory: () => throw StateError('Unexpected request'),
    );
    await service.speak(' ');
    expect(() => service.speak('Hello', rate: double.nan), throwsArgumentError);
    expect(() => service.speak('Hello', pitch: 1.5), throwsArgumentError);
    expect(() => service.speak('Hello', volume: -1), throwsArgumentError);
    expect(
      () => service.speak('Hello', language: 'invalid'),
      throwsArgumentError,
    );
  });
}
