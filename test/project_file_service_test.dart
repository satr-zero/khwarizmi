import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/projects/data/project_database.dart';
import 'package:khwarizmi/features/projects/domain/entities/pending_file_change.dart';
import 'package:khwarizmi/features/projects/domain/entities/project.dart';
import 'package:khwarizmi/features/projects/services/diff_service.dart';
import 'package:khwarizmi/features/projects/services/project_file_service.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Project testProject;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_project_test_');
    final dbPath = p.join(tempDir.path, 'proj_test.db');
    await MemoryDatabase.initialize(customPath: dbPath);
    await ProjectDatabase.initialize();

    testProject = Project(
      id: 'test-proj-1',
      name: 'Test Project',
      rootPath: tempDir.path,
      lastOpenedAt: DateTime.now(),
    );
  });

  tearDown(() async {
    MemoryDatabase.close();
    ProjectManager.instance.closeProject();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ProjectFileService Path Validation Tests', () {
    test('Valid relative path inside root resolves to ValidPath', () {
      final res = ProjectFileService.resolveAndValidatePath(
        testProject,
        'lib/main.dart',
      );
      expect(res, isA<ValidPath>());
      final valid = res as ValidPath;
      expect(valid.absolutePath.toLowerCase(), contains('lib'));
      expect(valid.absolutePath.toLowerCase(), contains('main.dart'));
    });

    test('Valid absolute path inside root resolves to ValidPath', () {
      final absoluteInside = p.join(testProject.rootPath, 'pubspec.yaml');
      final res = ProjectFileService.resolveAndValidatePath(
        testProject,
        absoluteInside,
      );
      expect(res, isA<ValidPath>());
      expect((res as ValidPath).absolutePath, equals(p.normalize(absoluteInside)));
    });

    test('Absolute path outside root resolves to InvalidPath', () {
      final res = ProjectFileService.resolveAndValidatePath(
        testProject,
        r'C:\Windows\System32\cmd.exe',
      );
      expect(res, isA<InvalidPath>());
      final invalid = res as InvalidPath;
      expect(invalid.reason, contains('خارج مجلد المشروع'));
    });

    test('Path traversal escaping root resolves to InvalidPath', () {
      final res = ProjectFileService.resolveAndValidatePath(
        testProject,
        '../../outside_file.txt',
      );
      expect(res, isA<InvalidPath>());
    });

    test('Empty or whitespace path resolves to InvalidPath', () {
      final res = ProjectFileService.resolveAndValidatePath(
        testProject,
        '   ',
      );
      expect(res, isA<InvalidPath>());
      expect((res as InvalidPath).reason, contains('فارغ'));
    });
  });

  group('ProjectFileService Read and Write File Tests', () {
    test('Write and read file within project root succeeds', () async {
      final writePath = p.join(testProject.rootPath, 'lib', 'utils', 'helper.dart');
      const content = "String greet() => 'Hello Khwarizmi';";

      final writeResultJson = await ProjectFileService.writeProjectFile(
        testProject,
        writePath,
        content,
      );
      final writeData = jsonDecode(writeResultJson) as Map<String, dynamic>;
      expect(writeData['success'], isTrue);
      expect(writeData['path'], equals(writePath));

      // Read back
      final readResultJson = await ProjectFileService.readProjectFile(
        testProject,
        'lib/utils/helper.dart',
      );
      final readData = jsonDecode(readResultJson) as Map<String, dynamic>;
      expect(readData['content'], equals(content));
    });

    test('Writing outside project root is rejected with error', () async {
      final writeResultJson = await ProjectFileService.writeProjectFile(
        testProject,
        r'C:\Windows\System32\danger.txt',
        'danger',
      );
      final writeData = jsonDecode(writeResultJson) as Map<String, dynamic>;
      expect(writeData['error'], contains('SECURITY'));
    });

    test('Reading non-existent file returns file not found error', () async {
      final readResultJson = await ProjectFileService.readProjectFile(
        testProject,
        'non_existent_file.txt',
      );
      final readData = jsonDecode(readResultJson) as Map<String, dynamic>;
      expect(readData['error'], contains('الملف غير موجود'));
    });

    test('Reading file larger than 500KB is rejected with size limit error', () async {
      final largeFilePath = p.join(testProject.rootPath, 'large_file.txt');
      // Create a 600KB file
      final largeFile = File(largeFilePath);
      final largeContent = 'A' * (600 * 1024);
      await largeFile.writeAsString(largeContent);

      final readResultJson = await ProjectFileService.readProjectFile(
        testProject,
        'large_file.txt',
      );
      final readData = jsonDecode(readResultJson) as Map<String, dynamic>;
      expect(readData.containsKey('error'), isTrue);
      expect(readData['error'], contains('500 KB'));
      expect(readData['maxSize'], equals(500 * 1024));

      // readRawContent should also return null
      final raw = await ProjectFileService.readRawContent(testProject, 'large_file.txt');
      expect(raw, isNull);
    });
  });

  group('DiffService Computation Tests', () {
    test('New file diff: all lines are marked as added', () {
      const newContent = 'line 1\nline 2\nline 3';
      final diff = DiffService.computeDiff(newText: newContent, oldText: null);

      expect(diff.length, equals(3));
      for (final line in diff) {
        expect(line.type, equals(DiffLineType.added));
      }
      expect(diff[0].content, equals('line 1'));
      expect(diff[0].newLineNumber, equals(1));
      expect(diff[2].content, equals('line 3'));
      expect(diff[2].newLineNumber, equals(3));
    });

    test('Modified file diff: identifies added, removed, and unchanged lines', () {
      const oldContent = 'void main() {\n  print("old");\n}';
      const newContent = 'void main() {\n  print("new");\n}';

      final diff = DiffService.computeDiff(
        oldText: oldContent,
        newText: newContent,
      );

      final addedLines = diff.where((l) => l.type == DiffLineType.added).toList();
      final removedLines = diff.where((l) => l.type == DiffLineType.removed).toList();

      expect(addedLines.length, equals(1));
      expect(addedLines.first.content, contains('print("new")'));
      expect(removedLines.length, equals(1));
      expect(removedLines.first.content, contains('print("old")'));
    });
  });

  group('ProjectManager Decision & Timeout Tests', () {
    test('waitForChangeDecision times out and auto-rejects after specified duration', () async {
      await ProjectManager.instance.openProject(testProject.rootPath);

      final proposeJson = await ProjectManager.instance.proposePendingChange(
        path: 'lib/test_change.dart',
        newContent: '// new content',
      );
      final changeId = (jsonDecode(proposeJson) as Map<String, dynamic>)['change_id'] as String;

      expect(ProjectManager.instance.pendingChanges.any((c) => c.id == changeId), isTrue);

      // Wait with short timeout (50ms) to simulate timeout
      final decision = await ProjectManager.instance.waitForChangeDecision(
        changeId,
        timeout: const Duration(milliseconds: 50),
      );

      expect(decision, isFalse);
      // Auto-rejected: pending change should be removed
      expect(ProjectManager.instance.pendingChanges.any((c) => c.id == changeId), isFalse);
    });

    test('waitForChangeDecision resolves immediately when approved', () async {
      await ProjectManager.instance.openProject(testProject.rootPath);

      final proposeJson = await ProjectManager.instance.proposePendingChange(
        path: 'lib/approved_change.dart',
        newContent: '// approved content',
      );
      final changeId = (jsonDecode(proposeJson) as Map<String, dynamic>)['change_id'] as String;

      // Asynchronously approve
      Future.delayed(const Duration(milliseconds: 20), () {
        ProjectManager.instance.applyChange(changeId);
      });

      final decision = await ProjectManager.instance.waitForChangeDecision(
        changeId,
        timeout: const Duration(seconds: 2),
      );

      expect(decision, isTrue);
    });
  });
}
