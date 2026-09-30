import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/features/filesystem/services/file_system_service.dart';
import 'package:khwarizmi/features/tools/built_in/filesystem_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempSandboxDir;
  late FileSystemService fileSystemService;
  late WriteFileTool writeTool;
  late ReadFileTool readTool;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempSandboxDir = await Directory.systemTemp.createTemp('khwarizmi_sandbox_test_');
    fileSystemService = FileSystemService.instance;
    await fileSystemService.setAllowedDirectory(tempSandboxDir.path);
    writeTool = WriteFileTool();
    readTool = ReadFileTool();
  });

  tearDown(() async {
    if (await tempSandboxDir.exists()) {
      await tempSandboxDir.delete(recursive: true);
    }
  });

  group('Phase 6 File System Tool Unit Tests', () {
    test('1. Write and read file successfully within allowed sandbox directory', () async {
      const fileName = 'test_note.txt';
      const fileContent = 'مرحباً من خوارزمي! هذه تجربة كتابة نصية حقيقية.';

      // Write file via tool
      final writeResStr = await writeTool.execute({
        'path': fileName,
        'content': fileContent,
      });

      final writeRes = jsonDecode(writeResStr) as Map<String, dynamic>;
      expect(writeRes['status'], equals('success'));
      expect(writeRes['path'], contains(fileName));

      // Physically verify file exists on disk
      final expectedFile = File(p.join(tempSandboxDir.path, fileName));
      expect(await expectedFile.exists(), isTrue);
      expect(await expectedFile.readAsString(), equals(fileContent));

      // Read file via tool
      final readResStr = await readTool.execute({
        'path': fileName,
      });

      final readRes = jsonDecode(readResStr) as Map<String, dynamic>;
      expect(readRes['status'], equals('success'));
      expect(readRes['content'], equals(fileContent));
    });

    test('2. Subdirectories inside allowed folder are created and readable', () async {
      const subPath = 'nested/subfolder/document.md';
      const content = '# تقرير تحليلي\nبيانات داخل مجلد فرعي.';

      final writeResStr = await writeTool.execute({
        'path': subPath,
        'content': content,
      });

      final writeRes = jsonDecode(writeResStr) as Map<String, dynamic>;
      expect(writeRes['status'], equals('success'));

      final readResStr = await readTool.execute({'path': subPath});
      final readRes = jsonDecode(readResStr) as Map<String, dynamic>;
      expect(readRes['content'], equals(content));
    });

    test('3. Strictly rejects path traversal attempts (e.g. ../../escape.txt)', () async {
      const maliciousPath = '../../escape_attempt.txt';
      const content = 'محاولة اختراق خارج الـ Sandbox';

      final writeResStr = await writeTool.execute({
        'path': maliciousPath,
        'content': content,
      });

      final writeRes = jsonDecode(writeResStr) as Map<String, dynamic>;
      expect(writeRes['error'], equals('الوصول مرفوض خارج المجلد المسموح به'));

      // Ensure file was NEVER created on disk outside
      final parentOfSandbox = tempSandboxDir.parent;
      final escapedFile = File(p.join(parentOfSandbox.path, 'escape_attempt.txt'));
      expect(await escapedFile.exists(), isFalse);
    });

    test('4. Strictly rejects absolute path outside allowed directory', () async {
      final externalPath = p.join(Directory.systemTemp.path, 'unauthorized_file.txt');

      final writeResStr = await writeTool.execute({
        'path': externalPath,
        'content': 'data',
      });

      final writeRes = jsonDecode(writeResStr) as Map<String, dynamic>;
      expect(writeRes['error'], equals('الوصول مرفوض خارج المجلد المسموح به'));

      final readResStr = await readTool.execute({
        'path': externalPath,
      });

      final readRes = jsonDecode(readResStr) as Map<String, dynamic>;
      expect(readRes['error'], equals('الوصول مرفوض خارج المجلد المسموح به'));
    });

    test('5. Reading non-existent file within sandbox returns clear JSON error', () async {
      final readResStr = await readTool.execute({
        'path': 'ghost_file.txt',
      });

      final readRes = jsonDecode(readResStr) as Map<String, dynamic>;
      expect(readRes['error'], equals('الملف غير موجود'));
    });

    test('6. Dynamic folder expansion allows new directory and secures old one', () async {
      final secondDir = await Directory.systemTemp.createTemp('khwarizmi_second_');
      try {
        await fileSystemService.setAllowedDirectory(secondDir.path);
        expect(await fileSystemService.getAllowedDirectory(), equals(p.canonicalize(secondDir.path)));

        // Writing to new directory succeeds
        final writeResStr = await writeTool.execute({
          'path': 'new_dir_file.txt',
          'content': 'مجلد جديد مخصص',
        });
        final writeRes = jsonDecode(writeResStr) as Map<String, dynamic>;
        expect(writeRes['status'], equals('success'));

        // Writing to previous directory is now rejected as it is external
        final writeOldStr = await writeTool.execute({
          'path': p.join(tempSandboxDir.path, 'old_dir_file.txt'),
          'content': 'attempt',
        });
        final writeOldRes = jsonDecode(writeOldStr) as Map<String, dynamic>;
        expect(writeOldRes['error'], equals('الوصول مرفوض خارج المجلد المسموح به'));
      } finally {
        if (await secondDir.exists()) {
          await secondDir.delete(recursive: true);
        }
      }
    });
  });
}
