import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';

void main() {
  group('Phase 8: SkillManifest Domain Entity Unit Tests', () {
    test('1. Parses valid manifest.json with all fields and start_command', () {
      final json = {
        'name': 'weather_skill',
        'display_name': 'أداة الطقس المحلية',
        'description': 'جلب حالة الطقس لمدينة معينة',
        'endpoint': 'http://localhost:5055/execute',
        'input_schema': {
          'type': 'object',
          'properties': {
            'city': {'type': 'string', 'description': 'اسم المدينة'}
          },
          'required': ['city']
        },
        'permissions': ['network', 'filesystem'],
        'version': '1.2.0',
        'start_command': 'python weather_skill.py'
      };

      final manifest = SkillManifest.fromJson(json, folderPath: r'C:\Skills\weather');

      expect(manifest.name, equals('weather_skill'));
      expect(manifest.displayName, equals('أداة الطقس المحلية'));
      expect(manifest.description, equals('جلب حالة الطقس لمدينة معينة'));
      expect(manifest.endpoint, equals('http://localhost:5055/execute'));
      expect(manifest.permissions, contains('network'));
      expect(manifest.permissions, contains('filesystem'));
      expect(manifest.version, equals('1.2.0'));
      expect(manifest.startCommand, equals('python weather_skill.py'));
      expect(manifest.folderPath, equals(r'C:\Skills\weather'));
    });

    test('2. Parses valid manifest without optional fields (default version and null start_command)', () {
      final json = {
        'name': 'simple_calc',
        'display_name': 'حاسبة سريعة',
        'description': 'عمليات حسابية',
        'endpoint': 'http://127.0.0.1:9000/api',
        'input_schema': {'type': 'object'}
      };

      final manifest = SkillManifest.fromJson(json, folderPath: '/tmp/calc');

      expect(manifest.name, equals('simple_calc'));
      expect(manifest.version, equals('1.0.0'));
      expect(manifest.permissions, isEmpty);
      expect(manifest.startCommand, isNull);
    });

    test('3. Throws FormatException when required fields are missing or empty', () {
      // Missing name
      expect(
        () => SkillManifest.fromJson({
          'display_name': 'Test',
          'description': 'Desc',
          'endpoint': 'http://localhost:8080',
          'input_schema': {}
        }, folderPath: '/tmp'),
        throwsFormatException,
      );

      // Missing endpoint
      expect(
        () => SkillManifest.fromJson({
          'name': 'test_tool',
          'display_name': 'Test',
          'description': 'Desc',
          'input_schema': {}
        }, folderPath: '/tmp'),
        throwsFormatException,
      );

      // Missing input_schema
      expect(
        () => SkillManifest.fromJson({
          'name': 'test_tool',
          'display_name': 'Test',
          'description': 'Desc',
          'endpoint': 'http://localhost:8080',
        }, folderPath: '/tmp'),
        throwsFormatException,
      );

      // Invalid endpoint URL
      expect(
        () => SkillManifest.fromJson({
          'name': 'test_tool',
          'display_name': 'Test',
          'description': 'Desc',
          'endpoint': 'not_a_valid_url',
          'input_schema': {}
        }, folderPath: '/tmp'),
        throwsFormatException,
      );
    });

    test('4. Safely rejects malformed raw JSON string', () {
      expect(
        () => SkillManifest.fromRawJson('{ this is broken json }', folderPath: '/tmp'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
