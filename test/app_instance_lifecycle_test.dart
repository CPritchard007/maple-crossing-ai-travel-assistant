import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maple_crossing/services/app_instance_service.dart';

void main() {
  test('registers, heartbeats, and closes the same instance', () async {
    final actions = <String>[];
    String? id;
    final service = AppInstanceService(
      client: MockClient((request) async {
        if (request.url.path == '/api/initialize') {
          id =
              (jsonDecode(request.body) as Map<String, dynamic>)['instanceId']
                  as String;
          return http.Response(jsonEncode({'instanceId': id}), 200);
        }
        expect(request.url.path, '/api/instances/$id');
        actions.add(request.url.queryParameters['action']!);
        return http.Response('{"status":"active"}', 200);
      }),
    );
    await service.heartbeat();
    await service.heartbeat();
    await service.close();
    await service.heartbeat();
    await service.close();
    expect(actions, ['heartbeat', 'heartbeat', 'close']);
    service.dispose();
  });

  test(
    'heartbeat failure updates status and recovers with the same ID',
    () async {
      var fail = true;
      final ids = <String>[];
      final service = AppInstanceService(
        client: MockClient((request) async {
          if (request.url.path == '/api/initialize') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            ids.add(body['instanceId'] as String);
            return http.Response(jsonEncode(body), 200);
          }
          return http.Response(
            fail ? '{}' : '{"status":"active"}',
            fail ? 503 : 200,
          );
        }),
      );
      await service.heartbeat();
      expect(service.status, AppInstanceStatus.failed);
      fail = false;
      await service.heartbeat();
      expect(service.status, AppInstanceStatus.ready);
      expect(ids, [service.instanceId, service.instanceId]);
      service.dispose();
    },
  );
}
