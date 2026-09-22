import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/domain/entities/conversation.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';

/// إدارة سجل المحادثات (Chat History) الخام في SQLite.
/// منفصل تماماً عن جداول الذاكرة الدلالية (memories) والمهام (tasks).
class ChatHistoryDatabase {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS conversations (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');

      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS conversation_messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          tool_calls TEXT,
          tool_call_id TEXT,
          status_badge TEXT,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
        );
      ''');

      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);',
      );
      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_messages_conv ON conversation_messages(conversation_id, timestamp ASC);',
      );

      _initialized = true;
      debugPrint('[ChatHistoryDatabase] Initialized successfully.');
    } catch (e) {
      debugPrint('[ChatHistoryDatabase] Initialization error: $e');
    }
  }

  // ── Conversation Operations ──────────────────────────────────────────────

  static Future<void> createConversation(Conversation conversation) async {
    await MemoryDatabase.executeRaw('''
      INSERT OR REPLACE INTO conversations (id, title, created_at, updated_at)
      VALUES (?, ?, ?, ?)
    ''', [
      conversation.id,
      conversation.title,
      conversation.createdAt.millisecondsSinceEpoch,
      conversation.updatedAt.millisecondsSinceEpoch,
    ]);
  }

  static Future<List<Conversation>> getAllConversations({int limit = 100}) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM conversations ORDER BY updated_at DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) => Conversation.fromMap(r)).toList();
  }

  static Future<Conversation?> getConversationById(String id) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM conversations WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  static Future<void> updateConversationTitle(String id, String newTitle) async {
    await MemoryDatabase.executeRaw(
      'UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?',
      [newTitle.trim(), DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  static Future<void> touchConversation(String id) async {
    await MemoryDatabase.executeRaw(
      'UPDATE conversations SET updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  static Future<void> deleteConversation(String id) async {
    await MemoryDatabase.executeRaw(
      'DELETE FROM conversation_messages WHERE conversation_id = ?',
      [id],
    );
    await MemoryDatabase.executeRaw(
      'DELETE FROM conversations WHERE id = ?',
      [id],
    );
  }

  // ── Messages Operations ──────────────────────────────────────────────────

  static Future<void> saveMessage(String conversationId, ChatMessage message) async {
    final toolCallsJson = message.toolCalls != null
        ? jsonEncode(message.toolCalls!.map((c) => c.toJson()).toList())
        : null;

    await MemoryDatabase.executeRaw('''
      INSERT OR REPLACE INTO conversation_messages (
        id, conversation_id, role, content, timestamp, tool_calls, tool_call_id, status_badge
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      message.id,
      conversationId,
      message.role.name,
      message.content,
      message.timestamp.millisecondsSinceEpoch,
      toolCallsJson,
      message.toolCallId,
      message.statusBadge,
    ]);

    await touchConversation(conversationId);
  }

  static Future<void> saveMessages(String conversationId, List<ChatMessage> messages) async {
    for (final msg in messages) {
      await saveMessage(conversationId, msg);
    }
  }

  static Future<List<ChatMessage>> getMessagesForConversation(String conversationId) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM conversation_messages WHERE conversation_id = ? ORDER BY timestamp ASC',
      [conversationId],
    );

    return rows.map((r) {
      List<ToolCallInfo>? toolCalls;
      final rawCalls = r['tool_calls'] as String?;
      if (rawCalls != null && rawCalls.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawCalls) as List;
          toolCalls = decoded
              .map((e) => ToolCallInfo.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        } catch (_) {}
      }

      return ChatMessage(
        id: r['id'] as String,
        role: MessageRole.values.firstWhere(
          (role) => role.name == (r['role'] as String?),
          orElse: () => MessageRole.assistant,
        ),
        content: r['content'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (r['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
        toolCalls: toolCalls,
        toolCallId: r['tool_call_id'] as String?,
        isStreaming: false,
        statusBadge: r['status_badge'] as String?,
      );
    }).toList();
  }

  /// حذف رسالة واحدة محددة
  static Future<void> deleteMessage(String messageId) async {
    await MemoryDatabase.executeRaw(
      'DELETE FROM conversation_messages WHERE id = ?',
      [messageId],
    );
  }

  /// حذف رسالة معينة وكل الرسائل التي تلتها في نفس المحادثة (تُستخدم عند تعديل الرسالة وإعادة إرسالها)
  static Future<void> deleteMessagesFrom(String conversationId, String messageId) async {
    final messages = await getMessagesForConversation(conversationId);
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    for (int i = index; i < messages.length; i++) {
      await MemoryDatabase.executeRaw(
        'DELETE FROM conversation_messages WHERE id = ?',
        [messages[i].id],
      );
    }
    await touchConversation(conversationId);
  }

  static Future<void> clearAll() async {
    await MemoryDatabase.executeRaw('DELETE FROM conversation_messages');
    await MemoryDatabase.executeRaw('DELETE FROM conversations');
  }
}
