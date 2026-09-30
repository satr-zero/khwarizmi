import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/data/chat_history_database.dart';
import 'package:khwarizmi/features/chat/domain/entities/conversation.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_controller.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('chat_stop_edit_test_');
    testDbPath = '${tempDir.path}/test_chat.db';
    await MemoryDatabase.initialize(customPath: testDbPath);
    await ChatHistoryDatabase.initialize();
  });

  tearDownAll(() async {
    MemoryDatabase.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await ChatHistoryDatabase.clearAll();
  });

  group('Chat Stop Generation & Message Editing Tests', () {
    test('1. ChatHistoryDatabase.deleteMessagesFrom deletes target message and subsequent messages', () async {
      final now = DateTime.now();
      final conv = Conversation(
        id: 'conv_1',
        title: 'محادثة تجريبية',
        createdAt: now,
        updatedAt: now,
      );
      await ChatHistoryDatabase.createConversation(conv);

      final msg1 = ChatMessage(
        id: 'm1',
        role: MessageRole.user,
        content: 'الرسالة الأولى',
        timestamp: now.add(const Duration(seconds: 1)),
      );
      final msg2 = ChatMessage(
        id: 'm2',
        role: MessageRole.assistant,
        content: 'رد 1',
        timestamp: now.add(const Duration(seconds: 2)),
      );
      final msg3 = ChatMessage(
        id: 'm3',
        role: MessageRole.user,
        content: 'الرسالة الثانية (المراد تعديلها)',
        timestamp: now.add(const Duration(seconds: 3)),
      );
      final msg4 = ChatMessage(
        id: 'm4',
        role: MessageRole.assistant,
        content: 'رد 2',
        timestamp: now.add(const Duration(seconds: 4)),
      );

      await ChatHistoryDatabase.saveMessage('conv_1', msg1);
      await ChatHistoryDatabase.saveMessage('conv_1', msg2);
      await ChatHistoryDatabase.saveMessage('conv_1', msg3);
      await ChatHistoryDatabase.saveMessage('conv_1', msg4);

      var messages = await ChatHistoryDatabase.getMessagesForConversation('conv_1');
      expect(messages.length, equals(4));

      // Delete from m3 onwards
      await ChatHistoryDatabase.deleteMessagesFrom('conv_1', 'm3');

      messages = await ChatHistoryDatabase.getMessagesForConversation('conv_1');
      expect(messages.length, equals(2));
      expect(messages[0].id, equals('m1'));
      expect(messages[1].id, equals('m2'));
    });

    test('2. ChatController.getLastUserMessage returns the most recent user message', () {
      final controller = ChatController();
      final msg1 = ChatMessage(
        id: '1',
        role: MessageRole.user,
        content: 'سؤال أول',
        timestamp: DateTime.now(),
      );
      final msg2 = ChatMessage(
        id: '2',
        role: MessageRole.assistant,
        content: 'جواب أول',
        timestamp: DateTime.now(),
      );
      final msg3 = ChatMessage(
        id: '3',
        role: MessageRole.user,
        content: 'سؤال أخير',
        timestamp: DateTime.now(),
      );

      // Initially empty
      expect(controller.getLastUserMessage(), isNull);

      // Update state with messages
      controller.state = controller.state.copyWith(
        messages: [msg1, msg2, msg3],
      );

      final last = controller.getLastUserMessage();
      expect(last, isNotNull);
      expect(last!.id, equals('3'));
      expect(last.content, equals('سؤال أخير'));
    });

    test('3. ChatController.stopGeneration stops streaming and removes empty assistant placeholder', () {
      final controller = ChatController();
      final userMsg = ChatMessage(
        id: 'u1',
        role: MessageRole.user,
        content: 'ما هو الطقس؟',
        timestamp: DateTime.now(),
      );
      final emptyAssistantMsg = ChatMessage(
        id: 'a1',
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
        isStreaming: true,
      );

      controller.state = controller.state.copyWith(
        messages: [userMsg, emptyAssistantMsg],
        isStreaming: true,
        activeStatus: 'يفكّر...',
      );

      controller.stopGeneration();

      expect(controller.state.isStreaming, isFalse);
      expect(controller.state.activeStatus, isNull);
      // Empty assistant placeholder was cleanly removed
      expect(controller.state.messages.length, equals(1));
      expect(controller.state.messages.first.id, equals('u1'));
    });

    test('4. ChatController.stopGeneration marks partial assistant response with stop note', () {
      final controller = ChatController();
      final userMsg = ChatMessage(
        id: 'u1',
        role: MessageRole.user,
        content: 'اكتب لي مقالة',
        timestamp: DateTime.now(),
      );
      final partialAssistantMsg = ChatMessage(
        id: 'a1',
        role: MessageRole.assistant,
        content: 'هذه بداية المقالة...',
        timestamp: DateTime.now(),
        isStreaming: true,
      );

      controller.state = controller.state.copyWith(
        messages: [userMsg, partialAssistantMsg],
        isStreaming: true,
        activeStatus: 'يكتب...',
      );

      controller.stopGeneration();

      expect(controller.state.isStreaming, isFalse);
      expect(controller.state.messages.length, equals(2));
      final lastMsg = controller.state.messages.last;
      expect(lastMsg.isStreaming, isFalse);
      expect(lastMsg.content, contains('هذه بداية المقالة...'));
      expect(lastMsg.content, contains('تم إيقاف التوليد بواسطة المستخدم'));
    });
  });
}
