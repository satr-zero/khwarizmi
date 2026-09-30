import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/coding_modes.dart';
import 'package:khwarizmi/features/chat/presentation/utils/tool_presentation_formatter.dart';
import 'package:khwarizmi/features/projects/domain/entities/project.dart';
import 'package:khwarizmi/features/projects/services/project_file_service.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  setUpAll(() {
    ToolRegistry.initialize();
  });

  group('search_project_code Tool & Service', () {
    late Directory tempDir;
    late Project testProject;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('khwarizmi_search_test_');

      // Create dummy project files
      final libDir = Directory(p.join(tempDir.path, 'lib'))..createSync(recursive: true);
      Directory(p.join(tempDir.path, 'test')).createSync(recursive: true);
      final gitDir = Directory(p.join(tempDir.path, '.git'))..createSync(recursive: true);
      final buildDir = Directory(p.join(tempDir.path, 'build'))..createSync(recursive: true);

      // Normal code file
      File(p.join(libDir.path, 'main.dart')).writeAsStringSync('''
void main() {
  final isCritical = true;
  print("Hello World");
  final ToolCallCard card = ToolCallCard();
}
''');

      // Another code file
      File(p.join(libDir.path, 'card.dart')).writeAsStringSync('''
class ToolCallCard {
  final bool isCritical;
  ToolCallCard({this.isCritical = false});
}
''');

      // Ignored folders should not be searched
      File(p.join(gitDir.path, 'config')).writeAsStringSync('isCritical in git');
      File(p.join(buildDir.path, 'out.dart')).writeAsStringSync('isCritical in build');

      // Binary file should be skipped
      File(p.join(libDir.path, 'image.png')).writeAsStringSync('isCritical in png');

      testProject = Project(
        id: 'test-proj',
        name: 'Test Project',
        rootPath: tempDir.path,
        createdAt: DateTime.now(),
        lastOpenedAt: DateTime.now(),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('is registered in ToolRegistry as a built-in tool', () {
      expect(ToolRegistry.isBuiltInTool('search_project_code'), isTrue);
      expect(ToolRegistry.isToolRegistered('search_project_code'), isTrue);

      final defs = ToolRegistry.getAvailableDefinitions();
      final searchDef = defs.firstWhere((d) => d.name == 'search_project_code');
      expect(searchDef.parameters['properties'], contains('query'));
      expect(searchDef.parameters['properties'], contains('search_type'));
    });

    test('searches literal string and finds matching files with context lines', () async {
      final raw = await ProjectFileService.searchProjectCode(
        testProject,
        query: 'isCritical',
        searchType: 'literal',
      );

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['query'], 'isCritical');
      expect(decoded['count'], 3); // 1 in main.dart, 2 in card.dart (.git and build/ are excluded)
      expect(decoded['truncated'], isFalse);

      final matches = decoded['matches'] as List;
      expect(matches.length, 3);

      final files = matches.map((m) => m['file'] as String).toList();
      expect(files, contains('lib/main.dart'));
      expect(files, contains('lib/card.dart'));

      // Check context and line numbering
      final firstMatch = matches.firstWhere((m) => m['file'] == 'lib/main.dart');
      expect(firstMatch['line'], 2);
      expect(firstMatch['line_content'], 'final isCritical = true;');
      expect(firstMatch['context'], contains('> '));
    });

    test('searches symbol with word boundaries', () async {
      final raw = await ProjectFileService.searchProjectCode(
        testProject,
        query: 'ToolCallCard',
        searchType: 'symbol',
      );

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['count'], 3);
    });

    test('searches regex correctly', () async {
      final raw = await ProjectFileService.searchProjectCode(
        testProject,
        query: r'print\(.*\)',
        searchType: 'regex',
      );

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['count'], 1);
      final match = (decoded['matches'] as List).first;
      expect(match['file'], 'lib/main.dart');
      expect(match['line_content'], 'print("Hello World");');
    });

    test('narrows search when relative path is provided', () async {
      final raw = await ProjectFileService.searchProjectCode(
        testProject,
        query: 'isCritical',
        relativePath: 'lib/card.dart',
      );

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['count'], 2); // only card.dart
      final matches = decoded['matches'] as List;
      expect(matches.every((m) => m['file'] == 'lib/card.dart'), isTrue);
    });

    test('returns error for empty query or invalid regex', () async {
      final emptyResult = await ProjectFileService.searchProjectCode(
        testProject,
        query: '   ',
      );
      expect(jsonDecode(emptyResult), contains('error'));

      final invalidRegexResult = await ProjectFileService.searchProjectCode(
        testProject,
        query: '[invalid-regex',
        searchType: 'regex',
      );
      expect(jsonDecode(invalidRegexResult), contains('error'));
    });
  });

  group('ToolPresentationFormatter for search_project_code', () {
    test('collapsed summary matches exact Arabic format: بحث عن "<query>" — <count> نتيجة', () {
      final rawResult = jsonEncode({
        'query': 'isCritical',
        'count': 8,
        'matches': List.generate(8, (i) => {'file': 'lib/a.dart', 'line': i + 1}),
      });

      final summary = ToolPresentationFormatter.getFriendlySummary(
        'search_project_code',
        rawResult,
        arguments: {'query': 'isCritical'},
      );

      expect(summary, 'بحث عن "isCritical" — 8 نتيجة');
    });

    test('friendly tool name returns Arabic running state', () {
      final name = ToolPresentationFormatter.getFriendlyToolName(
        'search_project_code',
        {'query': 'ToolCallCard'},
      );

      expect(name, 'يبحث بالكود عن "ToolCallCard"');
    });
  });

  group('Five Modes Permissions for search_project_code', () {
    test('search_project_code is allowed in ALL 5 modes (manager, planner, code, debug, inquiry)', () {
      const toolDef = ToolDefinition(
        name: 'search_project_code',
        description: 'Search code',
        parameters: {},
      );

      for (final mode in CodingMode.values) {
        expect(
          ToolFilter.isToolAllowed(toolDef, mode),
          isTrue,
          reason: 'search_project_code must be allowed in mode $mode',
        );
      }
    });
  });
}
