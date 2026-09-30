import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_detector.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_guard.dart';
import 'package:khwarizmi/features/chat/presentation/utils/unified_interceptor.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

void main() {
  group('UnifiedInterceptor - Live Chat Integration', () {
    test('intercepts at postAssistantTurn for consecutive promises without tool calls', () {
      // Setup: conversation with 2 consecutive promises
      final history = [
        ChatMessage(
          id: 'user-1',
          role: MessageRole.user,
          content: 'Create a file for me',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'I will create a file for you now.',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'user-2',
          role: MessageRole.user,
          content: 'Please proceed',
          timestamp: DateTime.now(),
        ),
      ];

      final assistantMsg = ChatMessage(
        id: 'assistant-2',
        role: MessageRole.assistant,
        content: 'I will now create the file as promised.',
        timestamp: DateTime.now(),
      );

      final result = UnifiedInterceptor.intercept(
        conversationHistory: history,
        assistantMessage: assistantMsg,
        toolCalls: [], // No tool calls = promise without execution
        promiseRecoveryAttempt: 0,
        timing: InterceptionTiming.postAssistantTurn,
      );

      expect(result.isIntercepted, isTrue);
      expect(
        result.action,
        equals(ExecutionPromiseGuardAction.interceptAndRecover),
      );
      expect(result.consecutiveCount, equals(2));
      expect(result.shouldInjectSystemTurn, isTrue);
      expect(result.shouldInjectRecoveryUserMessage, isTrue);
    });

    test('does not intercept when tool calls are present', () {
      final history = [
        ChatMessage(
          id: 'user-1',
          role: MessageRole.user,
          content: 'Create a file',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'I will create a file.',
          timestamp: DateTime.now(),
        ),
      ];

      final assistantMsg = ChatMessage(
        id: 'assistant-2',
        role: MessageRole.assistant,
        content: 'Creating the file now.',
        timestamp: DateTime.now(),
      );

      final toolCalls = [
        ToolCallInfo(
          callId: 'call-1',
          toolName: 'deliver_file',
          arguments: {'path': 'test.txt', 'content': 'Hello'},
        ),
      ];

      final result = UnifiedInterceptor.intercept(
        conversationHistory: history,
        assistantMessage: assistantMsg,
        toolCalls: toolCalls,
        promiseRecoveryAttempt: 0,
        timing: InterceptionTiming.postAssistantTurn,
      );

      expect(result.isIntercepted, isFalse);
      expect(result.action, equals(ExecutionPromiseGuardAction.none));
    });

    test('does not intercept for normal conversational text', () {
      final history = [
        ChatMessage(
          id: 'user-1',
          role: MessageRole.user,
          content: 'Hello, how are you?',
          timestamp: DateTime.now(),
        ),
      ];

      final assistantMsg = ChatMessage(
        id: 'assistant-1',
        role: MessageRole.assistant,
        content:
            'I am doing well, thank you for asking! How can I help you today?',
        timestamp: DateTime.now(),
      );

      final result = UnifiedInterceptor.intercept(
        conversationHistory: history,
        assistantMessage: assistantMsg,
        toolCalls: [],
        promiseRecoveryAttempt: 0,
        timing: InterceptionTiming.postAssistantTurn,
      );

      expect(result.isIntercepted, isFalse);
      expect(result.action, equals(ExecutionPromiseGuardAction.none));
    });

    test('applies interception correctly to message list', () {
      final history = [
        ChatMessage(
          id: 'user-1',
          role: MessageRole.user,
          content: 'Create a file',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'I will create a file for you.',
          timestamp: DateTime.now(),
        ),
      ];

      final assistantMsg = ChatMessage(
        id: 'assistant-2',
        role: MessageRole.assistant,
        content: 'I will now create the file as promised.',
        timestamp: DateTime.now(),
      );

      final currentMessages = List<ChatMessage>.from(history)
        ..add(assistantMsg);

      final result = UnifiedInterceptor.intercept(
        conversationHistory: history,
        assistantMessage: assistantMsg,
        toolCalls: [],
        promiseRecoveryAttempt: 0,
        timing: InterceptionTiming.postAssistantTurn,
      );

      final interceptedMessages = UnifiedInterceptor.applyInterception(
        currentMessages: currentMessages,
        result: result,
        assistantMsgId: assistantMsg.id,
        interceptedAssistantStub:
            ExecutionPromiseGuard.interceptedAssistantStub,
      );

      // Should have: user-1, assistant-1, assistant-2 (replaced with stub), system alert, recovery user message = 5
      expect(interceptedMessages.length, equals(5));

      // Assistant message should be replaced with stub
      final modifiedAssistant = interceptedMessages.firstWhere(
        (m) => m.id == 'assistant-2',
      );
      expect(
        modifiedAssistant.content,
        equals(ExecutionPromiseGuard.interceptedAssistantStub),
      );
      expect(modifiedAssistant.isStreaming, isFalse);
      expect(modifiedAssistant.toolCalls, isNull);

      // Should have system message
      final systemMsg = interceptedMessages.firstWhere(
        (m) => m.role == MessageRole.system,
      );
      expect(
        systemMsg.content,
        equals(ExecutionPromiseDetector.systemAlertNotice),
      );

      // Should have recovery user message
      final recoveryMsg = interceptedMessages.lastWhere(
        (m) => m.role == MessageRole.user,
      );
      expect(
        recoveryMsg.content,
        equals(ExecutionPromiseGuard.recoveryUserInjection),
      );
    });

    test('interceptNoticeOnly after max auto recoveries exhausted', () {
      final history = [
        ChatMessage(
          id: 'user-1',
          role: MessageRole.user,
          content: 'Create a file',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'I will create a file.',
          timestamp: DateTime.now(),
        ),
      ];

      final assistantMsg = ChatMessage(
        id: 'assistant-2',
        role: MessageRole.assistant,
        content: 'I will now create the file.',
        timestamp: DateTime.now(),
      );

      final result = UnifiedInterceptor.intercept(
        conversationHistory: history,
        assistantMessage: assistantMsg,
        toolCalls: [],
        promiseRecoveryAttempt: 1, // Already attempted recovery once
        timing: InterceptionTiming.postAssistantTurn,
      );

      expect(result.isIntercepted, isTrue);
      expect(
        result.action,
        equals(ExecutionPromiseGuardAction.interceptNoticeOnly),
      );
      expect(result.shouldInjectSystemTurn, isTrue);
      expect(
        result.shouldInjectRecoveryUserMessage,
        isFalse,
      ); // No recovery user message on notice-only
    });
  });

  group('UnifiedInterceptor - Autonomous Task Path Integration', () {
    test('checkAndInjectPromiseRecovery equivalent logic works', () {
      // Simulates the autonomous task engine calling the unified interceptor
      final history = [
        ChatMessage(
          id: 'user-1',
          role: MessageRole.user,
          content: 'Create a file',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'I will create a file.',
          timestamp: DateTime.now(),
        ),
      ];

      final assistantMsg = ChatMessage(
        id: 'assistant-2',
        role: MessageRole.assistant,
        content: 'I will create the file now.',
        timestamp: DateTime.now(),
      );

      final result = UnifiedInterceptor.intercept(
        conversationHistory: history,
        assistantMessage: assistantMsg,
        toolCalls: [],
        promiseRecoveryAttempt: 0,
        timing: InterceptionTiming.postAssistantTurn,
      );

      // Should trigger recovery for autonomous path too
      expect(result.isIntercepted, isTrue);
      expect(
        result.action,
        equals(ExecutionPromiseGuardAction.interceptAndRecover),
      );
    });
  });

  group('UnifiedInterceptor - Edge Cases', () {
    test('resets counter when tool calls present in assistant message', () {
      final history = [
        ChatMessage(
          id: 'user-1',
          role: MessageRole.user,
          content: 'Create a file',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'I will create a file.',
          timestamp: DateTime.now(),
        ),
      ];

      final assistantMsg = ChatMessage(
        id: 'assistant-2',
        role: MessageRole.assistant,
        content: 'I will create another file.',
        timestamp: DateTime.now(),
        toolCalls: [
          ToolCallInfo(
            callId: 'call-1',
            toolName: 'deliver_file',
            arguments: {'path': 'test.txt', 'content': 'content'},
          ),
        ],
      );

      final result = UnifiedInterceptor.intercept(
        conversationHistory: history,
        assistantMessage: assistantMsg,
        toolCalls: assistantMsg.toolCalls!,
        promiseRecoveryAttempt: 0,
        timing: InterceptionTiming.postAssistantTurn,
      );

      // Tool calls present = no interception
      expect(result.isIntercepted, isFalse);
    });

    test('interceptedAssistantStub is in Arabic as expected', () {
      expect(
        ExecutionPromiseGuard.interceptedAssistantStub,
        contains('اعترض نظام خوارزمي'),
      );
      expect(
        ExecutionPromiseGuard.interceptedAssistantStub,
        contains('وعد متكرر بالتنفيذ دون استدعاء أداة'),
      );
    });

    test('recoveryUserInjection is in Arabic and contains mandatory execution instruction', () {
      expect(
        ExecutionPromiseGuard.recoveryUserInjection,
        contains('[توجيه نظام — تنفيذ فوري إلزامي]'),
      );
      expect(
        ExecutionPromiseGuard.recoveryUserInjection,
        contains('deliver_file'),
      );
    });

    test('systemAlertNotice is in Arabic', () {
      expect(
        ExecutionPromiseDetector.systemAlertNotice,
        contains('لاحظنا أن النموذج وعد بالتنفيذ'),
      );
    });
  });
}
