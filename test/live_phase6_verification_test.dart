// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/core/security/browser_security_interceptor.dart';
import 'package:khwarizmi/features/browser/services/agent_browser_service.dart';
import 'package:khwarizmi/features/filesystem/services/file_system_service.dart';
import 'package:khwarizmi/features/tools/built_in/browser_tools.dart';
import 'package:khwarizmi/features/tools/built_in/filesystem_tools.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Live Phase 6 Verification Suite (Browser, Filesystem, and Payment Barrier)', () {
    test('Proof 1: Dedicated Browser User Data Profile Isolation Path', () {
      final profileDir = AgentBrowserService.profileDirectory;
      final dlDir = AgentBrowserService.downloadDirectory;

      print('=== PROOF 1: Dedicated Browser Isolation Directories ===');
      print('Agent Browser Profile Directory: $profileDir');
      print('Agent Dedicated Downloads Directory: $dlDir');

      expect(profileDir.toLowerCase(), contains('khwarizmi'));
      expect(profileDir.toLowerCase(), contains('browserprofile'));
      expect(dlDir.toLowerCase(), contains('downloads'));
      expect(dlDir.toLowerCase(), contains('khwarizmi'));

      // Ensure directory is inside APPDATA, completely separate from default Edge / Chrome user profiles
      final appData = Platform.environment['APPDATA'] ?? '';
      if (appData.isNotEmpty) {
        expect(p.canonicalize(profileDir).startsWith(p.canonicalize(appData)), isTrue);
      }
    });

    test('Proof 2: Real write_file and read_file on physical disk', () async {
      print('=== PROOF 2: Real Sandboxed File System Execution ===');
      final writeTool = WriteFileTool();
      final readTool = ReadFileTool();

      final defaultDir = FileSystemService.defaultAllowedDirectory;
      print('Default Sandbox Directory: $defaultDir');

      const testFileName = 'khwarizmi_phase6_live_test.txt';
      final testContent = 'اختبار التحقق الفعلي للمرحلة 6 — خوارزمي: ${DateTime.now().toIso8601String()}';

      // 1. Write file
      final writeResStr = await writeTool.execute({
        'path': testFileName,
        'content': testContent,
      });
      print('Write Result: $writeResStr');
      final writeRes = jsonDecode(writeResStr) as Map<String, dynamic>;
      expect(writeRes['status'], equals('success'));
      final savedPath = writeRes['path'] as String;

      // 2. Physical disk verification
      final diskFile = File(savedPath);
      expect(await diskFile.exists(), isTrue);
      expect(await diskFile.length(), greaterThan(0));
      print('File physically verified on disk: ${diskFile.path} (${await diskFile.length()} bytes)');

      // 3. Read file via tool
      final readResStr = await readTool.execute({'path': testFileName});
      final readRes = jsonDecode(readResStr) as Map<String, dynamic>;
      expect(readRes['status'], equals('success'));
      expect(readRes['content'], equals(testContent));
      print('Read verification verified content accurately.');

      // 4. Cleanup test file
      await diskFile.delete();
    });

    test('Proof 3: Real file download and physical storage verification', () async {
      print('=== PROOF 3: Real File Download to Designated Downloads Folder ===');
      final dlTool = DownloadFileTool();

      // Download a small real file from pub.dev / github
      const fileUrl = 'https://raw.githubusercontent.com/flutter/flutter/master/README.md';

      final dlResStr = await dlTool.execute({'url': fileUrl});
      print('Download Response: $dlResStr');
      final dlRes = jsonDecode(dlResStr) as Map<String, dynamic>;

      expect(dlRes['status'], equals('success'));
      expect(dlRes.containsKey('saved_path'), isTrue);

      final savedFilePath = dlRes['saved_path'] as String;
      final fileOnDisk = File(savedFilePath);

      // Verify physical presence & size
      expect(await fileOnDisk.exists(), isTrue);
      expect(await fileOnDisk.length(), greaterThan(0));
      print('Downloaded file physically verified on disk at: $savedFilePath (${await fileOnDisk.length()} bytes)');

      // Cleanup downloaded test file
      if (await fileOnDisk.exists()) {
        await fileOnDisk.delete();
      }
    });

    test('Proof 4: Critical Payment Security Barrier Live Interception & Confirmation Lifecycle', () async {
      print('=== PROOF 4: Critical Payment Security Barrier Lifecycle ===');

      // Scenario: Khwarizmi navigates an e-commerce site to checkout and encounters payment button
      const checkoutUrl = 'https://demo-store.stripe.dev/checkout';
      const checkoutSelector = 'button#complete-payment';
      const buttonText = 'Pay \$49.99 Now';

      print('Step 1: Attempting unconfirmed click on payment button...');
      final clickRes1 = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: checkoutUrl,
        selector: checkoutSelector,
        elementText: buttonText,
      );

      print('Interception Result: blocked=${clickRes1.isBlocked}, reason="${clickRes1.riskReason}"');
      print('Token Issued: ${clickRes1.confirmationToken}');

      expect(clickRes1.isBlocked, isTrue);
      expect(clickRes1.confirmationToken, isNotNull);
      expect(clickRes1.riskReason, contains('إجراء مالي'));

      final _ = clickRes1.confirmationToken!; // captured for assertion above; value not used further

      print('Step 2: Simulating user explicit rejection ("لا، إلغاء")...');
      final rejectionHandled = BrowserSecurityInterceptor.handleUserChatConfirmationOrRejection('لا، ألغِ العملية');
      expect(rejectionHandled, isTrue);

      // Verify action remains blocked after rejection
      final clickAfterReject = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: checkoutUrl,
        selector: checkoutSelector,
        elementText: buttonText,
      );
      expect(clickAfterReject.isBlocked, isTrue);
      print('After rejection: execution remains strictly blocked.');

      print('Step 3: Simulating user explicit approval ("نعم، أكّد إتمام الشراء")...');
      final newToken = clickAfterReject.confirmationToken!;
      expect(newToken, isNotEmpty);

      final approvalHandled = BrowserSecurityInterceptor.handleUserChatConfirmationOrRejection('نعم، أكّد إتمام الشراء');
      expect(approvalHandled, isTrue);

      // Verify action is now safely permitted
      final clickAfterApproval = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: checkoutUrl,
        selector: checkoutSelector,
        elementText: buttonText,
      );
      expect(clickAfterApproval.isBlocked, isFalse);
      expect(clickAfterApproval.usedConfirmationToken, isTrue);
      print('After explicit user confirmation: action allowed and token consumed.');

      // Verify token is single-use and cannot be replayed
      final replayClick = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: checkoutUrl,
        selector: checkoutSelector,
        elementText: buttonText,
      );
      expect(replayClick.isBlocked, isTrue);
      print('Replay prevention: single-use token consumed, subsequent clicks require new confirmation.');
    });
  });
}
