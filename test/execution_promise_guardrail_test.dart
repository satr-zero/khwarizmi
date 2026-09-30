import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/models/chat_turn.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExecutionPromiseDetector - Pattern Matching', () {
    test('detects Arabic imminent execution promises (documented incidents)', () {
      // الحوادث الموثقة في محادثة المستخدم فعلياً
      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'سأقوم بإنشاء الملف الآن وتسليمه لك مباشرة. هذا مشروع كبير سأكتبه كاملاً في ملف واحد.',
        ),
        isTrue,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'فهمت، سأقوم بإنشاء الملف الكامل وتسليمه الآن مباشرة',
        ),
        isTrue,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'أفهم - سأقوم بإنشاء الملف الكامل وتسليمه الآن مباشرة.',
        ),
        isTrue,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'سأنشئ هذا المشروع الشامل في ملف HTML واحد، دعني أبدأ بإنشاء الملف الكامل مع جميع المتطلبات الآن.',
        ),
        isTrue,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'أعتذر، دعني أبدأ بإنشاء المشروع الآن. سأقوم بإنشاء ملف HTML كامل وشامل يحتوي على جميع المتطلبات.',
        ),
        isTrue,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'سأكتب الملف فوراً وأرسله لك دفعة واحدة.',
        ),
        isTrue,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'سأنفذ التعديل مباشرة في الحال.',
        ),
        isTrue,
      );

      // بدون همزة (tolerance)
      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'ساقوم بانشاء الملف الان وتسليمه مباشرة',
        ),
        isTrue,
      );
    });

    test('detects English imminent execution promises', () {
      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'I will create the file now and deliver it immediately.',
        ),
        isTrue,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'Let me write the full code right away.',
        ),
        isTrue,
      );
    });

    test('does not falsely trigger on normal conversational or explanatory text', () {
      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'ما هي متطلبات المشروع التي تود البدء بها؟',
        ),
        isFalse,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'المشروع يحتاج إلى توضيح بنية البيانات أولاً.',
        ),
        isFalse,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(
          'تقنية WebGL الآن أصبحت مدعومة في كل المتصفحات الحديثة.',
        ),
        isFalse,
      );

      expect(
        ExecutionPromiseDetector.isImminentExecutionPromise(''),
        isFalse,
      );
    });
  });

  group('ExecutionPromiseDetector - Consecutive Promise Counter', () {
    test('returns 0 when there are no promises', () {
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'مرحباً خوارزمي',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'أهلاً بك! كيف يمكنني مساعدتك اليوم؟',
          timestamp: DateTime.now(),
        ),
      ];

      expect(ExecutionPromiseDetector.countConsecutivePromises(messages), 0);
    });

    test('returns 1 for a single promise without tool call', () {
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'اكتب لي ملف HTML كامل',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'سأقوم بإنشاء الملف الآن وتسليمه لك مباشرة.',
          timestamp: DateTime.now(),
        ),
      ];

      expect(ExecutionPromiseDetector.countConsecutivePromises(messages), 1);
    });

    test('returns 2 for two consecutive promises without tool calls in between', () {
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'اكتب لي ملف HTML كامل',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'سأقوم بإنشاء الملف الآن وتسليمه لك مباشرة.',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '3',
          role: MessageRole.user,
          content: 'لكنك لم تنشئ أي ملف؟ شو المشكلة؟',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '4',
          role: MessageRole.assistant,
          content: 'فهمت، سأقوم بإنشاء الملف الكامل وتسليمه الآن مباشرة.',
          timestamp: DateTime.now(),
        ),
      ];

      expect(ExecutionPromiseDetector.countConsecutivePromises(messages), 2);
    });

    test('resets counter when an assistant message includes actual tool calls', () {
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'اكتب لي ملف HTML كامل',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'سأقوم بإنشاء الملف الآن وتسليمه لك مباشرة.',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '3',
          role: MessageRole.user,
          content: 'انشئ ملف تجريبي هيا',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '4',
          role: MessageRole.assistant,
          content: 'سأقوم بإنشاء الملف الآن مباشرة.',
          timestamp: DateTime.now(),
          toolCalls: const [
            ToolCallInfo(
              callId: 'call_1',
              toolName: 'deliver_file',
              arguments: {'filename': 'test.html', 'content': 'hello'},
            ),
          ],
        ),
      ];

      expect(ExecutionPromiseDetector.countConsecutivePromises(messages), 0);
    });

    test('resets counter when a tool result message exists in the trail', () {
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'اكتب لي ملف HTML كامل',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'سأقوم بإنشاء الملف الآن وتسليمه لك مباشرة.',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '3',
          role: MessageRole.tool,
          content: '{"status":"ok"}',
          toolCallId: 'call_1',
          timestamp: DateTime.now(),
        ),
      ];

      expect(ExecutionPromiseDetector.countConsecutivePromises(messages), 0);
    });
  });

  group('ChatTurn & UI Support for MessageRole.system', () {
    test('groupMessages creates SystemTurn for MessageRole.system', () {
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'رسالة مستخدم',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'رد مساعد',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '3',
          role: MessageRole.system,
          content: ExecutionPromiseDetector.systemAlertNotice,
          timestamp: DateTime.now(),
        ),
      ];

      final turns = ChatTurn.groupMessages(messages);
      expect(turns.length, 3);
      expect(turns[0], isA<UserTurn>());
      expect(turns[1], isA<AssistantTurn>());
      expect(turns[2], isA<SystemTurn>());

      final systemTurn = turns[2] as SystemTurn;
      expect(
        systemTurn.message.content,
        contains('لاحظنا أن النموذج وعد بالتنفيذ مرتين متتاليتين'),
      );
    });
  });
}
