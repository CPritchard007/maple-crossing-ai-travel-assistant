import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maple_crossing/services/app_instance_service.dart';

void main() {
  test('initializes once with an anonymous launch ID', () async {
    var calls = 0;
    final service = AppInstanceService(
      baseUrl: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        calls++;
        expect(request.url.toString(), 'https://example.com/api/initialize');
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(
          body['instanceId'],
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
        expect(body['platform'], isNotEmpty);
        return http.Response(jsonEncode(body), 200);
      }),
    );
    await Future.wait([service.initialize(), service.initialize()]);
    expect(calls, 1);
    expect(service.registered, isTrue);
    expect(AppInstanceService().instanceId, isNot(service.instanceId));
  });

  test('retries a temporary failure with the same ID', () async {
    final ids = <String>[];
    final service = AppInstanceService(
      baseUrl: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        ids.add(body['instanceId'] as String);
        return ids.length == 1
            ? http.Response('{}', 503)
            : http.Response(jsonEncode(body), 200);
      }),
    );
    await service.initialize();
    expect(ids, [service.instanceId, service.instanceId]);
    expect(service.registered, isTrue);
  });

  test('permanent rejection does not block startup or retry', () async {
    var calls = 0;
    final service = AppInstanceService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 400);
      }),
    );
    await service.initialize();
    expect(service.registered, isFalse);
    expect(calls, 1);
  });
}
