import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

/// يمثل أداة Skill خارجية قابلة للاستدعاء من قبل النموذج عبر HTTP محلي.
class SkillTool implements AgentTool {
  final SkillManifest manifest;
  final http.Client? client;

  SkillTool(this.manifest, {this.client});

  @override
  ToolDefinition get definition => ToolDefinition(
        name: manifest.name,
        description: manifest.description,
        parameters: manifest.inputSchema,
        isControlTool: false, // متاحة للشات العادي والمهام المستقلة
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final httpClient = client ?? http.Client();
    final url = Uri.parse(manifest.endpoint);

    final payload = jsonEncode({
      'tool': manifest.name,
      'arguments': arguments,
    });

    try {
      debugPrint('[SkillTool:${manifest.name}] Invoking endpoint ${manifest.endpoint} with args: $arguments');

      final response = await httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: payload,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[SkillTool:${manifest.name}] Success (${response.statusCode})');
        return response.body;
      } else {
        debugPrint('[SkillTool:${manifest.name}] HTTP ${response.statusCode}: ${response.body}');
        return jsonEncode({
          'error': "Skill '${manifest.name}' returned HTTP error ${response.statusCode}: ${response.body}",
        });
      }
    } on TimeoutException {
      debugPrint('[SkillTool:${manifest.name}] Timeout exceeded (15 seconds)');
      return jsonEncode({
        'error': "Skill '${manifest.name}' تجاوز مهلة الانتظار القصوى (15 ثانية). الـ Sidecar قد يكون بطيئاً أو غير مستجيب.",
      });
    } on SocketException catch (e) {
      debugPrint('[SkillTool:${manifest.name}] Connection failed: $e');
      return jsonEncode({
        'error': "Skill '${manifest.name}' غير متاح حاليًا: تعذر الاتصال بـ ${manifest.endpoint} (تأكد من عمل الـ Sidecar).",
      });
    } catch (e) {
      debugPrint('[SkillTool:${manifest.name}] Execution error: $e');
      return jsonEncode({
        'error': "Skill '${manifest.name}' غير متاح حاليًا: $e",
      });
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
