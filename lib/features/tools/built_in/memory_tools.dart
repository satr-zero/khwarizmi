import 'dart:convert';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/memory/data/memory_repository.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

class StoreMemoryTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'store_memory',
    description: 'Saves a permanent fact, user preference, instruction, or key context into Khwarizmi long-term persistent memory database.',
    parameters: {
      'type': 'OBJECT',
      'properties': {
        'content': {
          'type': 'STRING',
          'description': 'The fact, preference, or detail to store permanently.'
        },
        'category': {
          'type': 'STRING',
          'description': 'Optional category for organizing memories (e.g., preference, identity, project, rule, contact).'
        },
        'importance': {
          'type': 'INTEGER',
          'description': 'Importance level from 1 (low) to 5 (critical user preference or fact).'
        }
      },
      'required': ['content']
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final content = arguments['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      return '{"status": "error", "message": "Missing content parameter"}';
    }

    final category = (arguments['category'] as String?) ?? 'general';
    final importance = (arguments['importance'] as num?)?.toInt() ?? 1;

    try {
      final apiKey = await SecureStorageService.getApiKey('gemini');
      final entry = await MemoryRepository.storeMemory(
        content: content.trim(),
        category: category,
        importance: importance,
        apiKey: apiKey,
      );

      return jsonEncode({
        'status': 'success',
        'message': 'Memory saved successfully into local persistent database.',
        'memory_id': entry.id,
        'has_vector_embedding': entry.embedding != null,
      });
    } catch (e) {
      return jsonEncode({
        'status': 'error',
        'message': 'Failed to save memory: $e',
      });
    }
  }
}

class SearchMemoryTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'search_memory',
    description: 'Searches Khwarizmi long-term memory for past facts, user preferences, instructions, or history using semantic vector search and keyword matching.',
    parameters: {
      'type': 'OBJECT',
      'properties': {
        'query': {
          'type': 'STRING',
          'description': 'The semantic topic, keyword, or question to search the memories for.'
        },
        'limit': {
          'type': 'INTEGER',
          'description': 'Maximum number of relevant memories to retrieve (default 5).'
        }
      },
      'required': ['query']
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final query = arguments['query'] as String?;
    if (query == null || query.trim().isEmpty) {
      return '{"status": "error", "message": "Missing query parameter"}';
    }

    final limit = (arguments['limit'] as num?)?.toInt() ?? 5;

    try {
      final apiKey = await SecureStorageService.getApiKey('gemini');
      final results = await MemoryRepository.searchMemory(
        query: query.trim(),
        limit: limit,
        apiKey: apiKey,
      );

      if (results.isEmpty) {
        return jsonEncode({
          'status': 'success',
          'results_count': 0,
          'message': 'No matching memories found for this query.',
          'memories': [],
        });
      }

      final mapped = results.map((sm) {
        return {
          'content': sm.entry.content,
          'category': sm.entry.category,
          'relevance_score': double.parse(sm.score.toStringAsFixed(2)),
          'recorded_at': sm.entry.createdAt.toIso8601String(),
        };
      }).toList();

      return jsonEncode({
        'status': 'success',
        'results_count': mapped.length,
        'memories': mapped,
      });
    } catch (e) {
      return jsonEncode({
        'status': 'error',
        'message': 'Failed to search memory: $e',
      });
    }
  }
}
