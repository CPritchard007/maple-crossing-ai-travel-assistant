import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:maple_crossing/services/action_service.dart';

const sample =
    'We recommend traveling through windsor tunnel as it has the lowest travel cost, and no current delays. '
    '((geo lat="42.3149" lng="-83.0364" highlight="point" type="recommendation" action="waypoint")) '
    'Be advised that XYZ road is currently under construction. '
    '((geo name="XYZ Road" type="hazard" action="reroute" highlight="path" path="42.3012,-82.9981;42.3080,-82.9900;42.3150,-82.9800")) '
    'This will be todays travel notice, have a terrific day! '
    '((geo lat="42.2854" lng="-82.9512" highlight="destination" type="summary" action="terminate"))';

void main() {
  test('clears text ten seconds after playback finishes', () {
    fakeAsync((clock) {
      final playback = Completer<void>();
      final service = ActionService(speak: (_) => playback.future);
      unawaited(service.execute('Final narration'));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 20));
      expect(service.overlayText.value, 'Final narration');
      playback.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      expect(service.overlayText.value, 'Final narration');
      clock.elapse(const Duration(seconds: 1));
      expect(service.overlayText.value, '');
    });
  });

  test('previous timeout cannot clear new narration', () {
    fakeAsync((clock) {
      final playback = Completer<void>();
      final service = ActionService(
        speak: (text) async {
          if (text == 'New narration') await playback.future;
        },
      );
      final feed = StreamController<String>();
      service.attachMap((_) async {});
      unawaited(service.consume(feed.stream));
      feed.add('First ((geo lat="42" lng="-83"))');
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 5));
      feed.add('New narration ((geo lat="42" lng="-83"))');
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 10));
      expect(service.overlayText.value, 'New narration');
      playback.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 10));
      expect(service.overlayText.value, '');
      unawaited(feed.close());
      clock.flushMicrotasks();
    });
  });

  test('returns home only after the final narration completes', () async {
    final events = <String>[];
    final finalSpeech = Completer<void>();
    final release = Completer<void>();
    final service = ActionService(
      speak: (text) async {
        events.add(text);
        if (text == 'Last') {
          finalSpeech.complete();
          await release.future;
        }
      },
    );
    service.attachMap(
      (_) async => events.add('map'),
      onFinished: () async => events.add('home'),
    );
    final run = service.execute('First ((geo lat="42" lng="-83")) Last');
    await finalSpeech.future;
    expect(events, ['First', 'map', 'Last']);
    release.complete();
    await run;
    expect(events, ['First', 'map', 'Last', 'home']);
  });

  test(
    'next text waits for action completion and trailing text is spoken',
    () async {
      final actionStarted = Completer<void>();
      final actionDone = Completer<void>();
      final spoken = <String>[];
      late ActionService service;
      service = ActionService(
        speak: (text) async {
          expect(service.overlayText.value, text);
          spoken.add(text);
        },
        onMapAction: (_) async {
          expect(spoken, ['First']);
          actionStarted.complete();
          await actionDone.future;
        },
      );
      final run = service.execute(
        'First ((geo lat="42.3" lng="-83")) Final text',
      );
      await actionStarted.future;
      expect(service.overlayText.value, 'First');
      expect(spoken, ['First']);
      actionDone.complete();
      await run;
      expect(spoken, ['First', 'Final text']);
      expect(service.overlayText.value, 'Final text');
    },
  );

  test(
    'overlay follows narration including trailing text and streamed feeds',
    () async {
      late ActionService service;
      final displayed = <String?>[];
      service = ActionService(
        onMapAction: (_) async {},
        speak: (text) async {
          expect(service.overlayText.value, text);
          displayed.add(service.overlayText.value);
        },
      );
      expect(service.overlayText.value, isNull);
      const feed = 'Look here ((geo lat="42.3" lng="-83")) Safe travels.';
      await service.consume(Stream.fromIterable(feed.split('')));
      expect(displayed, ['Look here', 'Safe travels.']);
      expect(service.overlayText.value, 'Safe travels.');
      await service.execute('((geo lat="42.3" lng="-83"))');
      expect(service.overlayText.value, 'Safe travels.');
      expect(displayed, hasLength(2));
    },
  );

  test('highlight-first point and path tags work across stream boundaries', () {
    const feed =
        'Point ((highlight lat="42.3" lng="-83.0")) '
        'Road ((highlight path="42.3,-83.0;42.4,-82.9" type="hazard"))';
    for (var split = 0; split <= feed.length; split++) {
      final decoder = ActionFeedDecoder();
      final steps = [
        ...decoder.add(feed.substring(0, split)),
        ...decoder.add(feed.substring(split)),
        ...decoder.finish(),
      ];
      expect(steps, hasLength(2));
      expect(steps.first.speech, 'Point');
      expect(steps.first.geo!.highlight, GeoHighlight.point);
      expect(steps.last.speech, 'Road');
      expect(steps.last.geo!.highlight, GeoHighlight.path);
      expect(steps.last.geo!.status, GeoStatus.hazard);
      expect(steps.last.geo!.coordinates, hasLength(2));
    }
  });

  test('bare geo coordinates focus without requiring styling or intent', () {
    final step = ActionService()
        .parse('Look here ((geo lat="42.3" lng="-83.0"))')
        .single;
    expect(step.speech, 'Look here');
    expect(step.geo!.coordinates.single.latitude, 42.3);
    expect(step.geo!.coordinates.single.longitude, -83);
    expect(step.geo!.highlight, GeoHighlight.none);
    expect(step.geo!.intent, GeoIntent.waypoint);
    expect(step.geo!.status, GeoStatus.recommendation);
  });

  test('example produces speech and correctly ordered coordinates/status', () {
    final steps = ActionService().parse(sample);
    expect(steps, hasLength(3));
    expect(steps[0].speech, startsWith('We recommend'));
    expect(steps.every((s) => !s.speech.contains('((geo')), isTrue);
    expect(steps[0].geo!.coordinates.single.latitude, 42.3149);
    expect(steps[0].geo!.coordinates.single.longitude, -83.0364);
    expect(steps[1].geo!.name, 'XYZ Road');
    expect(steps[1].geo!.coordinates, hasLength(3));
    expect(steps[1].geo!.status, GeoStatus.hazard);
    expect(steps[2].geo!.intent, GeoIntent.terminate);
  });

  test('every possible chunk boundary preserves the example', () {
    for (var split = 0; split <= sample.length; split++) {
      final decoder = ActionFeedDecoder();
      final steps = [
        ...decoder.add(sample.substring(0, split)),
        ...decoder.add(sample.substring(split)),
        ...decoder.finish(),
      ];
      expect(
        steps.map((s) => s.speech),
        ActionService().parse(sample).map((s) => s.speech),
      );
      expect(steps[1].geo!.coordinates.last.longitude, -82.9800);
    }
  });

  test('plain speech, trailing speech, single quotes and quoted brackets', () {
    final service = ActionService();
    expect(service.parse('Hello world').single.speech, 'Hello world');
    final steps = service.parse(
      "Hello ((geo name='Road )) North' lat='0' lng='0' highlight='point' type='hazard' action='waypoint')) Tail",
    );
    expect(steps.first.geo!.name, 'Road )) North');
    expect(steps.last.speech, 'Tail');
    expect(steps.last.geo, isNull);
  });

  test('invalid tags reject the entire batch before side effects', () async {
    final events = <String>[];
    final service = ActionService(
      speak: (text) async => events.add(text),
      onMapAction: (_) async => events.add('map'),
    );
    final valid = sample.substring(0, sample.indexOf(' Be advised'));
    for (final invalid in [
      '((geo lat="0"',
      'stray ))',
      '((geo ((geo ))',
      valid.replaceFirst('42.3149', 'NaN'),
      valid.replaceFirst('42.3149', '91'),
      valid.replaceFirst('-83.0364', '-181'),
      valid.replaceFirst('type="recommendation"', 'type="unknown"'),
      valid.replaceFirst('lat="42.3149"', 'lat=42.3149'),
      valid.replaceFirst('lat="42.3149"', 'lat="1" lat="2"'),
      valid.replaceFirst('highlight="point"', 'highlight="path"'),
      valid.replaceFirst('action="waypoint"', 'action="delete"'),
      valid.replaceFirst('lat="42.3149" ', ''),
      '$sample Unexpected tail',
    ]) {
      expect(() => service.execute('$valid $invalid'), throwsFormatException);
    }
    expect(events, isEmpty);
  });

  test(
    'execution waits for speech before dispatching each map action',
    () async {
      final events = <String>[];
      final release = Completer<void>();
      final firstSpeech = Completer<void>();
      final service = ActionService(
        onMapAction: (geo) async => events.add(geo.status.name),
        speak: (text) async {
          events.add(text);
          if (!firstSpeech.isCompleted) {
            firstSpeech.complete();
            await release.future;
          }
        },
      );
      final run = service.execute(sample);
      await firstSpeech.future;
      expect(events, hasLength(1));
      release.complete();
      await run;
      expect(events, hasLength(6));
      expect(events[3], 'hazard');
      expect(events[5], 'summary');
    },
  );

  test('streams character-sized chunks without speaking tags', () async {
    final spoken = <String>[];
    final service = ActionService(
      onMapAction: (_) async {},
      speak: (text) async => spoken.add(text),
    );
    await service.consume(Stream.fromIterable(sample.split('')));
    expect(spoken, service.parse(sample).map((s) => s.speech));
  });

  test('cancel interrupts narration and prevents later map actions', () async {
    final speaking = Completer<void>();
    final released = Completer<void>();
    var mapActions = 0;
    final service = ActionService(
      onMapAction: (_) async {
        mapActions++;
      },
      speak: (_) {
        speaking.complete();
        return released.future;
      },
      stopSpeaking: () async => released.complete(),
    );
    final run = service.execute(sample);
    await speaking.future;
    await service.cancel();
    await run;
    expect(mapActions, 0);
  });
  test('cancel releases a feed waiting for more network data', () async {
    final feed = StreamController<String>();
    final service = ActionService(
      speak: (_) async {},
      stopSpeaking: () async {},
    );
    final run = service.consume(feed.stream);
    await Future<void>.delayed(Duration.zero);
    await service.cancel().timeout(const Duration(seconds: 2));
    await run.timeout(const Duration(seconds: 2));
    await feed.close();
  });
}
