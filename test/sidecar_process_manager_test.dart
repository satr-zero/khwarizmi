import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';
import 'package:khwarizmi/features/skills/services/sidecar_process_manager.dart';

void main() {
  group('Phase 8: SidecarProcessManager Unit Tests', () {
    test('1. Manifest without start_command succeeds without launching any process', () async {
      const manifest = SkillManifest(
        name: 'external_only',
        displayName: 'أداة خارجية',
        description: 'تعتمد على خادم خارجي',
        endpoint: 'http://localhost:8080/api',
        inputSchema: {'type': 'object'},
        folderPath: '/fake',
        startCommand: null,
      );

      final manager = SidecarProcessManager.instance;
      final started = await manager.startProcess(manifest);

      expect(started, isTrue);
      expect(manager.isRunning('external_only'), isFalse);
    });

    test('2. Handles stopProcess cleanly for non-running skill', () async {
      final manager = SidecarProcessManager.instance;
      expect(() => manager.stopProcess('non_existent'), returnsNormally);
    });
  });
}
