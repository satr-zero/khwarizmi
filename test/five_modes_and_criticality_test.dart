import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/core/security/question_criticality_classifier.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/coding_modes.dart';

void main() {
  group('Five Modes System (منظومة الأوضاع الخمسة)', () {
    test('Manager, Planner, Code, and Inquiry are user-selectable initially', () {
      final initialModes = userSelectableInitialModes;
      expect(initialModes, contains(CodingMode.manager));
      expect(initialModes, contains(CodingMode.planner));
      expect(initialModes, contains(CodingMode.code));
      expect(initialModes, contains(CodingMode.inquiry));
      expect(initialModes.contains(CodingMode.debug), isFalse);
      expect(initialModes.length, 4);
    });

    test('ToolFilter enforces strict permissions per mode', () {
      const readFileTool = ToolDefinition(
        name: 'read_project_file',
        description: 'Read file',
        parameters: {},
      );
      const writeTool = ToolDefinition(
        name: 'propose_file_change',
        description: 'Write file',
        parameters: {},
      );
      const terminalTool = ToolDefinition(
        name: 'run_terminal_command',
        description: 'Run command',
        parameters: {},
      );
      const searchTool = ToolDefinition(
        name: 'search_memory',
        description: 'Search memory',
        parameters: {},
      );

      final allTools = [readFileTool, writeTool, terminalTool, searchTool];

      // Inquiry: Safe, read-only, no modification or terminal execution
      final inquiryTools = ToolFilter.filterForMode(allTools, CodingMode.inquiry);
      expect(inquiryTools.contains(readFileTool), isTrue);
      expect(inquiryTools.contains(searchTool), isTrue);
      expect(inquiryTools.contains(writeTool), isFalse);
      expect(inquiryTools.contains(terminalTool), isFalse);

      // Planner: Read & research only, no modification or terminal execution
      final plannerTools = ToolFilter.filterForMode(allTools, CodingMode.planner);
      expect(plannerTools.contains(readFileTool), isTrue);
      expect(plannerTools.contains(searchTool), isTrue);
      expect(plannerTools.contains(writeTool), isFalse);
      expect(plannerTools.contains(terminalTool), isFalse);

      // Code: Full execution capabilities
      final codeTools = ToolFilter.filterForMode(allTools, CodingMode.code);
      expect(codeTools.contains(readFileTool), isTrue);
      expect(codeTools.contains(writeTool), isTrue);
      expect(codeTools.contains(terminalTool), isTrue);

      // Debug: Read, diagnose and patch
      final debugTools = ToolFilter.filterForMode(allTools, CodingMode.debug);
      expect(debugTools.contains(readFileTool), isTrue);
      expect(debugTools.contains(writeTool), isTrue);
      expect(debugTools.contains(terminalTool), isTrue);
    });
  });

  group('Question Criticality Classifier (تصنيف الأسئلة: حرج vs غير حرج)', () {
    test('Non-critical choice questions return false', () {
      expect(
        QuestionCriticalityClassifier.isCritical(
          question: 'أي مكتبة تفضل استخدامها لإدارة الحالة؟ (Riverpod أو Bloc)',
        ),
        isFalse,
      );

      expect(
        QuestionCriticalityClassifier.isCritical(
          question: 'ما هو نمط التصميم المفضل لواجهة المستخدم؟',
        ),
        isFalse,
      );
    });

    test('Critical questions and actions return true', () {
      expect(
        QuestionCriticalityClassifier.isCritical(
          question: 'هل توافق على حذف المجلد بالكامل؟',
        ),
        isTrue,
      );

      expect(
        QuestionCriticalityClassifier.isCritical(
          question: '🔒 تأكيد مطلوب: أمر طرفية حساس',
        ),
        isTrue,
      );

      expect(
        QuestionCriticalityClassifier.isCritical(
          question: 'أي اختيار تفضل؟',
          explicitTag: true,
        ),
        isTrue,
      );

      expect(
        QuestionCriticalityClassifier.isCritical(
          question: 'تنفيذ أمر إجبار الدفع',
          arguments: {'command': 'git push --force origin main'},
        ),
        isTrue,
      );
    });
  });
}
