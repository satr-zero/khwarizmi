import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/core/theme/theme_controller.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/models/chat_turn.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/tool_call_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Monochrome Theme & WCAG Contrast Tests', () {
    test('WCAG AA Contrast calculation for Light and Dark modes', () {
      double calculateLuminance(Color color) {
        double channel(int c) {
          final s = c / 255.0;
          return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
        }
        return 0.2126 * channel((color.r * 255).round()) +
               0.7152 * channel((color.g * 255).round()) +
               0.0722 * channel((color.b * 255).round());
      }

      double contrastRatio(Color fg, Color bg) {
        final l1 = calculateLuminance(fg);
        final l2 = calculateLuminance(bg);
        final brighter = l1 > l2 ? l1 : l2;
        final darker = l1 > l2 ? l2 : l1;
        return (brighter + 0.05) / (darker + 0.05);
      }

      // 1. Light Mode Primary Text on Base Background
      final lightPrimaryRatio = contrastRatio(DesignTokens.textPrimaryLight, DesignTokens.bgLight);
      expect(lightPrimaryRatio, greaterThanOrEqualTo(7.0), reason: 'Light mode primary text exceeds AAA (7:1)');

      // 2. Light Mode Secondary Text on Base Background
      final lightSecondaryRatio = contrastRatio(DesignTokens.textSecondaryLight, DesignTokens.bgLight);
      expect(lightSecondaryRatio, greaterThanOrEqualTo(4.5), reason: 'Light mode secondary text meets AA (4.5:1)');

      // 3. Dark Mode Primary Text on Dark Background
      final darkPrimaryRatio = contrastRatio(DesignTokens.textPrimaryDark, DesignTokens.bgDark);
      expect(darkPrimaryRatio, greaterThanOrEqualTo(7.0), reason: 'Dark mode primary text exceeds AAA (7:1)');

      // 4. Dark Mode Secondary Text on Dark Background
      final darkSecondaryRatio = contrastRatio(DesignTokens.textSecondaryDark, DesignTokens.bgDark);
      expect(darkSecondaryRatio, greaterThanOrEqualTo(4.5), reason: 'Dark mode secondary text meets AA (4.5:1)');
    });

    test('ThemeModeNotifier toggle order (system -> light -> dark -> system)', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = ThemeModeNotifier();

      expect(notifier.state, ThemeMode.system);

      await notifier.toggleNext();
      expect(notifier.state, ThemeMode.light);

      await notifier.toggleNext();
      expect(notifier.state, ThemeMode.dark);

      await notifier.toggleNext();
      expect(notifier.state, ThemeMode.system);
    });
  });

  group('ChatTurn Presentation & Unification Tests', () {
    test('Consolidates assistant message, tool calls, and final response into ONE AssistantTurn', () {
      final now = DateTime.now();
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'ما هو الطقس في باريس؟',
          timestamp: now,
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'سأقوم بالبحث عن حالة الطقس في باريس الآن.',
          timestamp: now.add(const Duration(seconds: 1)),
          toolCalls: const [
            ToolCallInfo(
              callId: 'call_search_1',
              toolName: 'web_search',
              arguments: {'query': 'weather in Paris today'},
              status: ToolCallStatus.running,
            ),
          ],
        ),
        ChatMessage(
          id: '3',
          role: MessageRole.tool,
          toolCallId: 'call_search_1',
          content: '{"results": [{"title": "Paris 20C Sunny", "snippet": "Clear sky"}]}',
          timestamp: now.add(const Duration(seconds: 2)),
        ),
        ChatMessage(
          id: '4',
          role: MessageRole.assistant,
          content: 'الطقس الحالي في باريس مشمس ودرجة الحرارة 20 مئوية.',
          timestamp: now.add(const Duration(seconds: 3)),
        ),
      ];

      final turns = ChatTurn.groupMessages(messages);

      // Must result in exactly 2 turns: 1 UserTurn and 1 unified AssistantTurn
      expect(turns.length, equals(2));
      expect(turns[0], isA<UserTurn>());
      expect(turns[1], isA<AssistantTurn>());

      final assistantTurn = turns[1] as AssistantTurn;
      // Both the pre-tool thought and post-tool final text must be in textSegments
      expect(assistantTurn.textSegments.length, equals(2));
      expect(assistantTurn.textSegments[0], contains('سأقوم بالبحث'));
      expect(assistantTurn.textSegments[1], contains('مشمس ودرجة الحرارة 20'));

      // Tool call was enriched with tool output
      expect(assistantTurn.toolCalls.length, equals(1));
      expect(assistantTurn.toolCalls.first.status, equals(ToolCallStatus.success));
      expect(assistantTurn.toolCalls.first.result, contains('Paris 20C Sunny'));
    });
  });

  group('ToolCallCard Widget Visual States Tests', () {
    testWidgets('Renders Running State with spinner', (tester) async {
      const call = ToolCallInfo(
        callId: 'c1',
        toolName: 'web_search',
        arguments: {'query': 'test search'},
        status: ToolCallStatus.running,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ToolCallCard(toolCall: call),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('يبحث في الويب'), findsOneWidget);
    });

    testWidgets('Renders Success State with checkmark and collapsed by default', (tester) async {
      const call = ToolCallInfo(
        callId: 'c2',
        toolName: 'web_search',
        arguments: {'query': 'test query'},
        status: ToolCallStatus.success,
        summary: 'وجد 5 نتائج بحث مطابقة',
        result: '{"results": [{"title": "test"}]}',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ToolCallCard(toolCall: call),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('وجد 5 نتائج بحث مطابقة'), findsOneWidget);

      // Raw parameters/result are hidden when collapsed
      expect(find.text('المدخلات (Arguments):'), findsNothing);

      // Tap to expand
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      // Now expanded raw parameters are visible
      expect(find.text('المدخلات (Arguments):'), findsOneWidget);
    });

    testWidgets('Renders Error State with warning icon and failure reason', (tester) async {
      const call = ToolCallInfo(
        callId: 'c3',
        toolName: 'web_search',
        arguments: {'query': 'bad query'},
        status: ToolCallStatus.error,
        summary: 'تعذر الإكمال: خطأ في الاتصال بالشبكة',
        errorMessage: 'Network timeout',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ToolCallCard(toolCall: call),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('تعذر الإكمال: خطأ في الاتصال بالشبكة'), findsOneWidget);
    });

    testWidgets('Renders Awaiting Confirmation State with prominent action buttons', (tester) async {
      bool confirmed = false;
      bool rejected = false;

      const call = ToolCallInfo(
        callId: 'c4',
        toolName: 'agent_browser',
        arguments: {'action': 'checkout', 'amount': '150 USD'},
        status: ToolCallStatus.awaitingConfirmation,
        summary: 'بانتظار تأكيدك لمتابعة عملية الدفع...',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolCallCard(
              toolCall: call,
              onConfirm: () => confirmed = true,
              onReject: () => rejected = true,
            ),
          ),
        ),
      );

      // Awaiting confirmation starts expanded
      expect(find.text('تأكيد والمتابعة'), findsOneWidget);
      expect(find.text('إلغاء الإجراء'), findsOneWidget);

      await tester.tap(find.text('تأكيد والمتابعة'));
      await tester.pump();
      expect(confirmed, isTrue);

      await tester.tap(find.text('إلغاء الإجراء'));
      await tester.pump();
      expect(rejected, isTrue);
    });
  });
}
