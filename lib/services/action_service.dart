import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tts_service.dart';

final actionService = ActionService();

enum GeoHighlight { none, point, path, destination }

enum GeoStatus { recommendation, hazard, summary }

enum GeoIntent { waypoint, reroute, terminate }

class GeoCoordinate {
  const GeoCoordinate(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class GeoAction {
  GeoAction({
    required this.highlight,
    required this.status,
    required this.intent,
    required List<GeoCoordinate> coordinates,
    this.name,
  }) : coordinates = List.unmodifiable(coordinates);

  final GeoHighlight highlight;

  /// The incoming `type` describes the highlight's status.
  final GeoStatus status;
  final GeoIntent intent;
  final String? name;
  final List<GeoCoordinate> coordinates;
}

class ActionStep {
  const ActionStep({required this.speech, this.geo});
  final String speech;
  final GeoAction? geo;
}

typedef MapActionHandler = Future<void> Function(GeoAction action);

/// Consumes backend text; this service does not call an AI provider itself.
class ActionService {
  ActionService({
    Future<void> Function(String)? speak,
    Future<void> Function()? stopSpeaking,
    MapActionHandler? onMapAction,
  }) : _speak = speak ?? ttsService.speakAndWait,
       _stopSpeaking = stopSpeaking ?? ttsService.stop,
       _mapHandler = onMapAction;

  final Future<void> Function(String) _speak;
  final Future<void> Function() _stopSpeaking;
  MapActionHandler? _mapHandler;
  Future<void> Function()? _onFinished;
  bool get isRunning => _running;
  bool _running = false;
  int _generation = 0;
  StreamIterator<ActionStep>? _iterator;
  final _overlayText = ValueNotifier<String?>(null);
  Timer? _overlayClearTimer;

  /// Text for the current step, cleared ten seconds after speech finishes.
  ValueListenable<String?> get overlayText => _overlayText;

  /// The map owns this binding and must call the returned function on disposal.
  void Function() attachMap(
    MapActionHandler handler, {
    Future<void> Function()? onFinished,
  }) {
    _mapHandler = handler;
    _onFinished = onFinished;
    return () {
      if (identical(_mapHandler, handler)) {
        _mapHandler = null;
        _onFinished = null;
      }
    };
  }

  List<ActionStep> parse(String feed) {
    final decoder = ActionFeedDecoder();
    return List.unmodifiable([...decoder.add(feed), ...decoder.finish()]);
  }

  /// Validates a complete response before performing any actions.
  Future<void> execute(String feed) {
    final steps = parse(feed);
    return _run(Stream.fromIterable(steps));
  }

  /// Chunks are appended verbatim, including chunks split inside a quoted tag.
  /// Complete steps run in order with backpressure while the rest is buffered.
  Future<void> consume(Stream<String> feed) => _run(_decode(feed));

  Stream<ActionStep> _decode(Stream<String> feed) {
    final decoder = ActionFeedDecoder();
    return feed.transform(
      StreamTransformer<String, ActionStep>.fromHandlers(
        handleData: (chunk, sink) {
          try {
            for (final step in decoder.add(chunk)) {
              sink.add(step);
            }
          } catch (error, stack) {
            sink.addError(error, stack);
          }
        },
        handleDone: (sink) {
          try {
            for (final step in decoder.finish()) {
              sink.add(step);
            }
          } catch (error, stack) {
            sink.addError(error, stack);
          }
          sink.close();
        },
      ),
    );
  }

  Future<void> _run(Stream<ActionStep> steps) async {
    if (_running) throw StateError('An action feed is already running.');
    _running = true;
    final generation = ++_generation;
    final iterator = _iterator = StreamIterator(steps);
    try {
      while (await iterator.moveNext()) {
        final step = iterator.current;
        if (generation != _generation) break;
        if (step.speech.isNotEmpty) {
          _overlayClearTimer?.cancel();
          _overlayText.value = step.speech;
          try {
            await _speak(step.speech);
          } finally {
            if (generation == _generation) {
              _overlayClearTimer = Timer(const Duration(seconds: 10), () {
                _overlayText.value = '';
              });
            }
          }
        }
        if (generation != _generation) break;
        final geo = step.geo;
        if (geo != null) {
          final handler = _mapHandler;
          if (handler == null) {
            throw StateError('No map is attached to ActionService.');
          }
          await handler(geo);
        }
        if (generation != _generation) break;
        if (geo?.intent == GeoIntent.terminate) break;
      }
      if (generation == _generation) await _onFinished?.call();
    } finally {
      await iterator.cancel();
      _iterator = null;
      _running = false;
    }
  }

  Future<void> cancel() async {
    ++_generation;
    _overlayClearTimer?.cancel();
    _overlayText.value = '';
    await Future.wait([
      _stopSpeaking(),
      if (_iterator != null) _iterator!.cancel(),
    ]);
  }
}

/// Incremental, bounded parser for bracketed geo and highlight commands.
class ActionFeedDecoder {
  static const maxFeedLength = 1024 * 1024;
  static const maxTagLength = 32768;
  String _buffer = '';
  int _length = 0;
  bool _terminated = false;

  List<ActionStep> add(String chunk) {
    _length += chunk.length;
    if (_length > maxFeedLength) {
      throw const FormatException('Action feed is too large.');
    }
    _buffer += chunk;
    final steps = <ActionStep>[];
    while (true) {
      final start = _buffer.indexOf('((');
      if (start < 0) break;
      if (_terminated) throw const FormatException('Content after terminate.');
      final end = _tagEnd(start + 2);
      if (end < 0) {
        if (_buffer.length - start > maxTagLength) {
          throw const FormatException('Geo tag is too large.');
        }
        break;
      }
      if (end - start > maxTagLength) {
        throw const FormatException('Geo tag is too large.');
      }
      final speech = _speech(_buffer.substring(0, start));
      final geo = _parseTag(_buffer.substring(start + 2, end));
      steps.add(ActionStep(speech: speech, geo: geo));
      _terminated = geo.intent == GeoIntent.terminate;
      _buffer = _buffer.substring(end + 2);
    }
    return steps;
  }

  List<ActionStep> finish() {
    if (_buffer.contains('((')) {
      throw const FormatException('Unclosed geo tag.');
    }
    final tail = _speech(_buffer);
    _buffer = '';
    if (_terminated && tail.isNotEmpty) {
      throw const FormatException('Content after terminate.');
    }
    return tail.isEmpty ? [] : [ActionStep(speech: tail)];
  }

  int _tagEnd(int start) {
    String? quote;
    for (var i = start; i < _buffer.length - 1; i++) {
      final char = _buffer[i];
      if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (_buffer.startsWith('))', i)) {
        return i;
      } else if (_buffer.startsWith('((', i)) {
        throw const FormatException('Nested geo tag.');
      }
    }
    return -1;
  }

  static String _speech(String text) {
    if (text.contains('))')) {
      throw const FormatException('Unexpected closing tag.');
    }
    return text.trim();
  }

  static GeoAction _parseTag(String source) {
    final header = RegExp(r'^(geo|highlight)\s+').firstMatch(source.trimLeft());
    if (header == null) {
      throw const FormatException('Expected a geo or highlight tag.');
    }
    var rest = source.trimLeft().substring(header.end);
    final attrs = <String, String>{};
    final attribute = RegExp(r'''^([a-z]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
    while (rest.trim().isNotEmpty) {
      rest = rest.trimLeft();
      final match = attribute.firstMatch(rest);
      if (match == null) {
        throw const FormatException('Expected quoted geo attributes.');
      }
      final key = match[1]!;
      if (!{
            'lat',
            'lng',
            'name',
            'type',
            'action',
            'highlight',
            'path',
          }.contains(key) ||
          attrs.containsKey(key)) {
        throw FormatException('Unknown or duplicate geo attribute: $key');
      }
      attrs[key] = match[2] ?? match[3]!;
      rest = rest.substring(match.end);
      if (rest.isNotEmpty && !RegExp(r'^\s').hasMatch(rest)) {
        throw const FormatException(
          'Geo attributes must be separated by whitespace.',
        );
      }
    }
    T enumValue<T extends Enum>(String key, List<T> values, T fallback) {
      if (!attrs.containsKey(key)) return fallback;
      for (final value in values) {
        if (value.name == attrs[key]) return value;
      }
      throw FormatException('Unsupported or missing $key: ${attrs[key]}');
    }

    final highlight = enumValue(
      'highlight',
      GeoHighlight.values,
      header[1] == 'highlight'
          ? (attrs.containsKey('path') ? GeoHighlight.path : GeoHighlight.point)
          : GeoHighlight.none,
    );
    final status = enumValue(
      'type',
      GeoStatus.values,
      GeoStatus.recommendation,
    );
    final intent = enumValue('action', GeoIntent.values, GeoIntent.waypoint);
    final coordinates = <GeoCoordinate>[];
    if (highlight == GeoHighlight.path) {
      if (attrs.containsKey('lat') || attrs.containsKey('lng')) {
        throw const FormatException(
          'A path must use path coordinates, not lat/lng.',
        );
      }
      final pairs = (attrs['path'] ?? '').split(';');
      if (pairs.length < 2 || pairs.length > 1000) {
        throw const FormatException('A path requires 2–1000 coordinates.');
      }
      for (final pair in pairs) {
        final parts = pair.split(',');
        if (parts.length != 2) {
          throw const FormatException('Expected latitude,longitude pairs.');
        }
        coordinates.add(_coordinate(parts[0], parts[1]));
      }
    } else {
      if (attrs.containsKey('path')) {
        throw const FormatException('Only path highlights accept a path.');
      }
      coordinates.add(_coordinate(attrs['lat'], attrs['lng']));
    }
    return GeoAction(
      highlight: highlight,
      status: status,
      intent: intent,
      coordinates: coordinates,
      name: attrs['name'],
    );
  }

  static GeoCoordinate _coordinate(String? lat, String? lng) {
    final latitude = double.tryParse(lat?.trim() ?? '');
    final longitude = double.tryParse(lng?.trim() ?? '');
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const FormatException('Invalid latitude/longitude.');
    }
    return GeoCoordinate(latitude, longitude);
  }
}
