import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';
import 'package:khwarizmi/features/skills/domain/skill_tool.dart';

void main() {
  group('Phase 8: SkillTool Execution & Resiliency Unit Tests', () {
    late SkillManifest manifest;

    setUp(() {
      manifest = const SkillManifest(
        name: 'mock_weather',
        displayName: 'طقس تجريبي',
        description: 'أداة طقس للمحاكاة',
        endpoint: 'http://localhost:5055/execute',
        inputSchema: {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'}
          }
        },
        folderPath: '/mock/path',
      );
    });

    test('1. Successful execution returns HTTP 200 response body directly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), equals('http://localhost:5055/execute'));
        expect(request.method, equals('POST'));

        final body = jsonDecode(request.body);
        expect(body['tool'], equals('mock_weather'));
        expect(body['arguments']['city'], equals('Riyadh'));

        return http.Response(
          jsonEncode({'city': 'Riyadh', 'temp': 32, 'condition': 'Sunny'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final tool = SkillTool(manifest, client: mockClient);
      final result = await tool.execute({'city': 'Riyadh'});

      final decoded = jsonDecode(result);
      expect(decoded['city'], equals('Riyadh'));
      expect(decoded['temp'], equals(32));
      expect(decoded['condition'], equals('Sunny'));
    });

    test('2. Timeout exception (>15s) returns clear Arabic error without throwing or halting loop', () async {
      final mockClient = MockClient((request) async {
        // يحاكي تأخير يتجاوز مهلة الـ 15 ثانية برمي TimeoutException
        throw TimeoutException('Request timed out after 15 seconds');
      });

      final tool = SkillTool(manifest, client: mockClient);
      final result = await tool.execute({'city': 'Cairo'});

      final decoded = jsonDecode(result);
      expect(decoded['error'], isNotNull);
      expect(decoded['error'], contains('تجاوز مهلة الانتظار القصوى'));
      expect(decoded['error'], contains('mock_weather'));
    });

    test('3. SocketException / connection failure returns clear error without crashing', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection refused');
      });

      final tool = SkillTool(manifest, client: mockClient);
      final result = await tool.execute({'city': 'Dubai'});

      final decoded = jsonDecode(result);
      expect(decoded['error'], isNotNull);
      expect(decoded['error'], contains('غير متاح حاليًا'));
      expect(decoded['error'], contains('mock_weather'));
    });

    test('4. HTTP 500 error returns clear error payload to the model', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error in sidecar', 500);
      });

      final tool = SkillTool(manifest, client: mockClient);
      final result = await tool.execute({'city': 'Jeddah'});

      final decoded = jsonDecode(result);
      expect(decoded['error'], contains('HTTP error 500'));
    });
  });
}
