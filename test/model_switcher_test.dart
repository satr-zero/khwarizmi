import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/model_switcher.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/providers/domain/provider_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ProviderRegistry.initialize();
  });

  group('ModelSwitcher Responsive Design & Functionality Tests', () {
    testWidgets('ModelSwitcherBadge renders correctly and does not overflow on small screens',
        (WidgetTester tester) async {
      // Test on a very small mobile screen: 320x480
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: ModelSwitcherBadge(compact: true),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ModelSwitcherBadge), findsOneWidget);
      expect(find.byIcon(Icons.memory_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ModelSwitcher Dialog opens without overflowing on compact window (400x550)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 550);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ModelSwitcherBadge(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap to open the dialog
      await tester.tap(find.byType(ModelSwitcherBadge));
      await tester.pumpAndSettle();

      // Verify dialog is opened
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.text('تطبيق'), findsOneWidget);

      // Verify no RenderFlex overflow happened
      expect(tester.takeException(), isNull);

      // Close dialog
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('ModelSwitcher Dialog opens smoothly on standard desktop (1280x800)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ModelSwitcherBadge(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byType(ModelSwitcherBadge));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Test search functionality inside dialog
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'flash');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });

    test('Custom provider can be added and listed in ProviderRegistry', () async {
      const customConfig = ProviderConfig(
        id: 'test_custom_local',
        displayName: 'Local vLLM Server',
        type: 'openai_compatible',
        baseUrl: 'http://localhost:8000/v1',
        defaultModel: 'mistral-7b-instruct',
        availableModels: ['mistral-7b-instruct', 'qwen-2.5-7b'],
        isCustom: true,
        extraBodyParams: {'temperature': 0.6},
      );

      await ProviderRegistry.addCustomProvider(customConfig);

      final retrieved = ProviderRegistry.getConfig('test_custom_local');
      expect(retrieved, isNotNull);
      expect(retrieved!.displayName, equals('Local vLLM Server'));
      expect(retrieved.isCustom, isTrue);
      expect(retrieved.extraBodyParams['temperature'], equals(0.6));

      // Cleanup
      await ProviderRegistry.deleteCustomProvider('test_custom_local');
      expect(ProviderRegistry.getConfig('test_custom_local'), isNull);
    });
  });
}
