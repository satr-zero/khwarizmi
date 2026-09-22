import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:khwarizmi/core/security/browser_security_interceptor.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/core/services/agent_identity_service.dart';
import 'package:khwarizmi/features/agent/data/task_database.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/agent/services/task_execution_engine.dart';
import 'package:khwarizmi/features/chat/data/chat_history_database.dart';
import 'package:khwarizmi/features/chat/domain/entities/conversation.dart';
import 'package:khwarizmi/features/chat/presentation/utils/tool_presentation_formatter.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/memory/data/memory_repository.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/providers/domain/ai_provider.dart';
import 'package:khwarizmi/features/scheduler/data/reminder_database.dart';
import 'package:khwarizmi/features/scheduler/services/scheduler_service.dart';
import 'package:khwarizmi/features/agent/presentation/controllers/task_provider.dart';
import 'package:khwarizmi/features/projects/data/project_database.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_state.dart';

final chatProvider = StateNotifierProvider<ChatController, ChatState>((ref) {
  return ChatController(ref);
});

class ChatController extends StateNotifier<ChatState> {
  static const _uuid = Uuid();
  final Ref? _ref;

  StreamSubscription<AgentEvent>? _activeSubscription;
  bool _isAborted = false;
  String? _activeAutonomousTaskId;

  ChatController([this._ref]) : super(const ChatState()) {
    _initialize();
  }

  /// تبديل وضع (وكيل برمجي)
  void setCodingAgentMode(bool enabled) {
    state = state.copyWith(isCodingAgentMode: enabled);
  }

  /// تبديل ميزة التفكير الموسَّع يدويًا
  void toggleThinking() {
    state = state.copyWith(thinkingEnabled: !state.thinkingEnabled);
  }

  /// تسجيل أنه تم إظهار تنبيه عدم دعم التفكير في وضع الكود
  void markCodingBannerShown() {
    state = state.copyWith(codingModeThinkingBannerShown: true);
  }

  // Models that are deprecated/removed by Google — replaced automatically on startup
  static const _deprecatedModels = {
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-1.0-pro',
    'gemini-2.5-flash-lite', // no longer available to new users
  };

  Future<void> _initialize() async {
    try {
      await MemoryDatabase.initialize();
      await ChatHistoryDatabase.initialize();
      ReminderDatabase.initialize();
      SchedulerService.instance.start();
    } catch (e) {
      // Ignore if in headless test or already initialized
    }
    ToolRegistry.initialize();

    final systemPrompt = await AgentIdentityService.loadSystemPrompt();
    await ProviderRegistry.initialize();
    final activeProvider = await SecureStorageService.getActiveProvider();
    final provider = ProviderRegistry.getProvider(activeProvider);
    String savedModel =
        await SecureStorageService.getProviderModel(activeProvider) ??
            provider.defaultModel;
    final apiKey = await SecureStorageService.getApiKey(activeProvider);

    // Migrate deprecated models to latest default if on gemini
    if (activeProvider == 'gemini' &&
        _deprecatedModels.contains(savedModel)) {
      savedModel = 'gemini-3.8-flash';
      await SecureStorageService.setProviderModel('gemini', savedModel);
    }

    state = state.copyWith(
      systemPrompt: systemPrompt,
      selectedProviderId: activeProvider,
      selectedModel: savedModel,
      apiKey: apiKey,
    );

    // Sync any memories stored without embeddings in the background using Gemini key
    final geminiKey = (activeProvider == 'gemini')
        ? apiKey
        : await SecureStorageService.getApiKey('gemini');
    if (geminiKey != null && geminiKey.isNotEmpty) {
      MemoryRepository.syncPendingEmbeddings(geminiKey).catchError((_) => 0);
    }

    // Load conversation history list
    await loadConversations();
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<void> updateApiKey(String providerId, String key) async {
    await SecureStorageService.saveApiKey(providerId, key);
    if (state.selectedProviderId == providerId) {
      state = state.copyWith(apiKey: key.trim(), clearError: true);
    }
    if (providerId == 'gemini' && key.trim().isNotEmpty) {
      MemoryRepository.syncPendingEmbeddings(key.trim()).catchError((_) => 0);
    }
  }

  Future<void> updateModel(String model) async {
    await SecureStorageService.setProviderModel(state.selectedProviderId, model);
    state = state.copyWith(selectedModel: model);
  }

  Future<void> updateProvider(String providerId) async {
    await SecureStorageService.setActiveProvider(providerId);
    final key = await SecureStorageService.getApiKey(providerId);
    final provider = ProviderRegistry.getProvider(providerId);
    final savedModel =
        await SecureStorageService.getProviderModel(providerId) ??
            provider.defaultModel;
    state = state.copyWith(
      selectedProviderId: providerId,
      selectedModel: savedModel,
      apiKey: key,
      clearError: true,
    );
  }

  // ── Conversation Management ────────────────────────────────────────────────

  /// تحميل قائمة المحادثات من قاعدة البيانات
  Future<void> loadConversations() async {
    state = state.copyWith(isLoadingHistory: true);
    try {
      final convs = await ChatHistoryDatabase.getAllConversations();
      state = state.copyWith(conversations: convs, isLoadingHistory: false);
    } catch (e) {
      state = state.copyWith(isLoadingHistory: false);
      debugPrint('[ChatController] Failed to load conversations: $e');
    }
  }

  /// بدء محادثة جديدة فارغة (يُصفّر الشاشة)
  void clearConversation() {
    state = state.copyWith(
      messages: [],
      clearError: true,
      clearStatus: true,
      clearActiveConversation: true,
    );
  }

  /// فتح محادثة موجودة من قائمة التاريخ
  Future<void> openConversation(String conversationId) async {
    state = state.copyWith(isLoadingHistory: true);
    try {
      final conv =
          await ChatHistoryDatabase.getConversationById(conversationId);
      if (conv == null) {
        state = state.copyWith(isLoadingHistory: false);
        return;
      }
      final messages =
          await ChatHistoryDatabase.getMessagesForConversation(conversationId);

      // استعادة المشروع المرتبط بالمحادثة إن وجد
      final associatedProject =
          await ProjectDatabase.getProjectForConversation(conversationId);
      if (associatedProject != null) {
        await ProjectManager.instance.openProject(associatedProject.rootPath);
      }

      state = state.copyWith(
        activeConversation: conv,
        messages: messages,
        isLoadingHistory: false,
        clearError: true,
        clearStatus: true,
        isCodingAgentMode: associatedProject != null ? true : state.isCodingAgentMode,
      );
    } catch (e) {
      state = state.copyWith(isLoadingHistory: false);
      debugPrint('[ChatController] Failed to open conversation: $e');
    }
  }

  /// إعادة تسمية محادثة
  Future<void> renameConversation(String conversationId, String newTitle) async {
    await ChatHistoryDatabase.updateConversationTitle(conversationId, newTitle);
    // تحديث الحالة المحلية
    final updated = state.conversations.map((c) {
      if (c.id == conversationId) return c.copyWith(title: newTitle);
      return c;
    }).toList();
    state = state.copyWith(
      conversations: updated,
      activeConversation: state.activeConversation?.id == conversationId
          ? state.activeConversation!.copyWith(title: newTitle)
          : state.activeConversation,
    );
  }

  /// حذف محادثة
  Future<void> deleteConversation(String conversationId) async {
    await ChatHistoryDatabase.deleteConversation(conversationId);
    final updated =
        state.conversations.where((c) => c.id != conversationId).toList();
    // إن كانت المحادثة المحذوفة هي النشطة، ابدأ جديدة
    if (state.activeConversation?.id == conversationId) {
      state = state.copyWith(
        conversations: updated,
        messages: [],
        clearActiveConversation: true,
        clearError: true,
        clearStatus: true,
      );
    } else {
      state = state.copyWith(conversations: updated);
    }
  }

  // ── Internal: Conversation Persistence ────────────────────────────────────

  /// يضمن وجود محادثة نشطة (ينشئ واحدة إذا لم تكن موجودة)
  Future<Conversation> _ensureActiveConversation(String firstUserMessage) async {
    if (state.activeConversation != null) return state.activeConversation!;

    // استخدم أول 60 حرف من رسالة المستخدم كعنوان مبدئي
    final title = firstUserMessage.length > 60
        ? '${firstUserMessage.substring(0, 60)}...'
        : firstUserMessage;

    final now = DateTime.now();
    final conv = Conversation(
      id: _uuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    await ChatHistoryDatabase.createConversation(conv);

    // ربط المشروع النشط بالمحادثة إذا كان محدداً
    final activeProj = ProjectManager.instance.activeProject;
    if (activeProj != null) {
      await ProjectDatabase.linkConversationToProject(conv.id, activeProj.id);
    }

    state = state.copyWith(
      activeConversation: conv,
      conversations: [conv, ...state.conversations],
    );
    return conv;
  }

  /// يحفظ رسالة في قاعدة البيانات إذا كانت هناك محادثة نشطة
  Future<void> _persistMessage(ChatMessage message) async {
    final conv = state.activeConversation;
    if (conv == null) return;
    try {
      await ChatHistoryDatabase.saveMessage(conv.id, message);
    } catch (e) {
      debugPrint('[ChatController] Failed to persist message: $e');
    }
  }

  // ── Generation Control & Message Editing ───────────────────────────────────

  /// استرجاع آخر رسالة أرسلها المستخدم في المحادثة الحالية
  ChatMessage? getLastUserMessage() {
    for (int i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].role == MessageRole.user) {
        return state.messages[i];
      }
    }
    return null;
  }

  /// إيقاف التوليد أو التفكير وقطع الاتصال فوراً
  void stopGeneration() {
    if (!state.isStreaming && _activeSubscription == null && _activeAutonomousTaskId == null) {
      return;
    }
    _isAborted = true;
    _activeSubscription?.cancel();
    _activeSubscription = null;

    if (_activeAutonomousTaskId != null) {
      try {
        TaskExecutionEngine.instance.cancelTask(_activeAutonomousTaskId!);
      } catch (_) {}
      _activeAutonomousTaskId = null;
    }

    final messages = List<ChatMessage>.from(state.messages);
    if (messages.isNotEmpty) {
      final lastMsg = messages.last;
      if (lastMsg.role == MessageRole.assistant) {
        final hasTools = lastMsg.toolCalls != null && lastMsg.toolCalls!.isNotEmpty;
        final hasText = lastMsg.content.trim().isNotEmpty;

        if (!hasText && !hasTools) {
          // كانت فارغة قيد التفكير الأولي فقط → نحذف الفقاعة الفارغة تماماً
          messages.removeLast();
          if (state.activeConversation != null) {
            ChatHistoryDatabase.deleteMessage(lastMsg.id);
          }
        } else {
          // تحتوي على نص جزئي أو أدوات نُفذت → نختم الرسالة مع ملاحظة إيقاف
          final stoppedContent = hasText
              ? '${lastMsg.content}\n\n*(تم إيقاف التوليد بواسطة المستخدم)*'
              : '*(تم إيقاف التفكير بواسطة المستخدم)*';
          final stoppedMsg = lastMsg.copyWith(
            content: stoppedContent,
            isStreaming: false,
            statusBadge: null,
          );
          messages[messages.length - 1] = stoppedMsg;
          _persistMessage(stoppedMsg);
        }
      }
    }

    state = state.copyWith(
      messages: messages,
      isStreaming: false,
      clearStatus: true,
    );
  }

  /// تعديل رسالة مستخدم معينة وإعادة إرسالها (يحذف كل ما تلاها من ردود ويعيد توليد الرد)
  Future<void> editAndResendMessage(String messageId, String newContent) async {
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) return;

    if (state.isStreaming) {
      stopGeneration();
    }

    final targetIdx = state.messages.indexWhere((m) => m.id == messageId);
    if (targetIdx != -1) {
      if (state.activeConversation != null) {
        await ChatHistoryDatabase.deleteMessagesFrom(
          state.activeConversation!.id,
          messageId,
        );
      }
      final remaining = state.messages.sublist(0, targetIdx);
      state = state.copyWith(messages: remaining);
    }

    await sendMessage(trimmed);
  }

  // ── Send Message ───────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isStreaming) return;

    // Check if user confirmed or rejected any pending financial/checkout interception
    BrowserSecurityInterceptor.handleUserChatConfirmationOrRejection(trimmed);

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );

    final currentMessages =
        List<ChatMessage>.from(state.messages)..add(userMessage);

    state = state.copyWith(
      messages: currentMessages,
      isStreaming: true,
      clearError: true,
      activeStatus: 'يفكّر...',
    );

    final apiKey = state.apiKey;
    final activeProvider =
        ProviderRegistry.getProvider(state.selectedProviderId);
    if (apiKey == null || apiKey.trim().isEmpty) {
      final errorMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content:
            'مرحبًا بك! لاستخدام خوارزمي عبر (${activeProvider.displayName})، يرجى إدخال مفتاح API الخاص بك أولاً من الإعدادات (⚙️ أعلى اليمين).',
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: List<ChatMessage>.from(state.messages)..add(errorMsg),
        isStreaming: false,
        clearStatus: true,
      );
      return;
    }

    // ── إنشاء/تأكيد المحادثة وحفظ رسالة المستخدم ─────────────────────────
    await _ensureActiveConversation(trimmed);
    await _persistMessage(userMessage);

    await _runAgentLoop(currentMessages);
  }

  // ── Agent Loop ─────────────────────────────────────────────────────────────

  Future<void> _runAgentLoop(
      List<ChatMessage> conversationHistory, {
      int recoveryAttempt = 0,
  }) async {
    final provider = ProviderRegistry.getProvider(state.selectedProviderId);
    final availableTools = ToolRegistry.getChatDefinitions();
    final systemPrompt =
        state.systemPrompt ?? await AgentIdentityService.loadSystemPrompt();

    // Auto-retrieve relevant memories to inject into system prompt
    String effectiveSystemPrompt = systemPrompt;
    try {
      final userMessages =
          conversationHistory.where((m) => m.role == MessageRole.user);
      if (userMessages.isNotEmpty) {
        final lastUserText = userMessages.last.content;
        final geminiKey = (state.selectedProviderId == 'gemini')
            ? state.apiKey
            : await SecureStorageService.getApiKey('gemini');

        final relevant = await MemoryRepository.searchMemory(
          query: lastUserText,
          limit: 3,
          minScore: 0.35,
          apiKey: geminiKey,
        );

        if (relevant.isNotEmpty) {
          final memStrings = relevant
              .map((sm) =>
                  '- [${sm.entry.category}] ${sm.entry.content}')
              .join('\n');
          effectiveSystemPrompt += '''

\n[معلومات وذكريات مسترجعة ذات صلة من ذاكرة خوارزمي الدائمة]:
$memStrings
(ملاحظة: استخدم هذه المعلومات المسترجعة للإجابة بذكاء وسلاسة وبدون التصريح بأنك استرجعتها من قاعدة البيانات إلا إذا سُئلت).
''';
        }
      }
    } catch (_) {}

    // ── حقن سياق المهام المعلقة (waitingForUser) ──────────────────────────
    // يُعلم النموذج بالمهام المعلقة ليقرر بنفسه إن كانت رسالة المستخدم رداً عليها
    try {
      final pendingTasks =
          await TaskDatabase.getTasksByStatus(TaskStatus.waitingForUser);
      if (pendingTasks.isNotEmpty) {
        final pendingInfo = pendingTasks
            .map((t) =>
                '- مهمة ID=${t.id}: "${t.goal}" — سؤالها المعلق: "${t.pendingQuestion ?? ''}"')
            .join('\n');
        effectiveSystemPrompt += '''

\n[مهام معلقة تنتظر رد المستخدم — قرّر بنفسك هل رسالة المستخدم الحالية إجابة على إحداها]:
$pendingInfo
إذا كانت رسالة المستخدم رداً فعلياً على سؤال مهمة معلقة، استدعِ أداة resume_task(taskId, answer).
إذا كانت رسالة المستخدم شيئاً مختلفاً تماماً، أجب عنها طبيعياً ولا تستدعِ resume_task.
''';
      }
    } catch (_) {}

    // ── حقن الفهرس الخفيف للمهارات النصية (Text Skills Index) ────────────
    try {
      final textSkillsIndex = await TextSkillService.instance.getLightweightIndexPrompt();
      if (textSkillsIndex.isNotEmpty) {
        effectiveSystemPrompt += '\n\n$textSkillsIndex\n';
      }
    } catch (_) {}

    // ── حقن سياق المشروع البرمجي النشط (Phase 9: Coding Agent) ───────────
    final activeProj = ProjectManager.instance.activeProject;
    if (activeProj != null || state.isCodingAgentMode) {
      if (activeProj != null) {
        final projectMap = await ProjectManager.instance.getProjectMap();
        final mapInjected = projectMap != null && projectMap.isNotEmpty;
        final mapLen = mapInjected ? projectMap.length : 0;
        debugPrint('[ChatController] 📌 Project map injection: ${mapInjected ? "✅ YES ($mapLen chars)" : "❌ NO — map is null/empty"}');
        effectiveSystemPrompt += '''

[سياق المشروع البرمجي النشط — وكيل برمجي]:
أنت تعمل الآن كـ "وكيل برمجي" (Software Coding Agent) على المشروع التالي:
- اسم المشروع: ${activeProj.name}
- مسار جذر المشروع: ${activeProj.rootPath}
${mapInjected ? '\n[خريطة بنية المشروع — اقرأها كاملاً قبل أي خطوة]:\n$projectMap\n' : ''}
القواعد الإلزامية للتعامل مع هذا المشروع:
1. **خريطة المشروع أعلاه هي مصدرك الأساسي والوحيد لفهم بنية المشروع.** اقرأها كاملاً أولاً.
2. **ممنوع** استدعاء list_project_files لأي مجلد ظاهر بالخريطة — الخريطة تُغني عنه تماماً.
3. استدعِ list_project_files فقط لمجلد غير موجود في الخريطة إطلاقاً (مثلاً: مجلد أُنشئ حديثاً بعد توليد الخريطة).
4. لقراءة محتوى ملف بعينه: استخدم read_project_file (مسموح دائماً).
5. لأي تعديل أو إنشاء ملف جديد: استخدم propose_file_change (عرض Diff + موافقة المستخدم).
6. لتشغيل الأوامر: استخدم run_terminal_command. الأوامر الخطرة تتطلب تأكيداً.
7. إذا تغيّر هيكل المشروع بعد تعديلات: استدعِ refresh_project_map لتحديث الخريطة.
''';
      } else {
        effectiveSystemPrompt += '''

[سياق وضع الوكيل البرمجي]:
أنت في وضع "وكيل برمجي"، لكن المستخدم لم يحدد مسار المشروع بعد. اطلب منه اختيار مجلد المشروع من الزر المخصص أعلى شريط الإدخال.
''';
      }
    }

    // ── إعداد التفكير الموسَّع (ThinkingConfig) ──────────────────────────
    final providerConfig = ProviderRegistry.getConfig(state.selectedProviderId);
    final modelSupportsThinking =
        providerConfig?.doesModelSupportThinking(state.selectedModel) ?? false;

    ThinkingConfig? thinkingConfig;
    if (state.isCodingAgentMode) {
      // في وضع الكود، التفكير إلزامي وبميزانية قصوى 16000 توكن
      thinkingConfig = ThinkingConfig.coding;
    } else if (state.thinkingEnabled && modelSupportsThinking) {
      // في المحادثة العادية إن فعّله المستخدم يدوياً: 8000 توكن
      thinkingConfig = ThinkingConfig.regular;
    }

    _isAborted = false;
    final assistantMsgId = _uuid.v4();
    var currentAssistantContent = '';
    var currentThinkingContent = '';
    final List<ToolCallInfo> toolCalls = [];

    // Add initial assistant streaming placeholder
    var updatedMessages = List<ChatMessage>.from(conversationHistory)
      ..add(ChatMessage(
        id: assistantMsgId,
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
        isStreaming: true,
      ));

    state = state.copyWith(messages: updatedMessages);

    try {
      final stream = provider.sendMessage(
        history: conversationHistory,
        availableTools: availableTools,
        systemPrompt: effectiveSystemPrompt,
        apiKey: state.apiKey ?? '',
        modelName: state.selectedModel,
        thinking: thinkingConfig,
      );

      final completer = Completer<void>();
      _activeSubscription = stream.listen(
        (event) {
          if (_isAborted) return;
          if (event is AgentTextChunk) {
            currentAssistantContent += event.text;
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              thinkingContent:
                  currentThinkingContent.isNotEmpty ? currentThinkingContent : null,
              isStreaming: true,
              statusBadge: null,
            );
          } else if (event is AgentThinkingChunkEvent) {
            currentThinkingContent += event.text;
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              thinkingContent: currentThinkingContent,
              isStreaming: true,
              statusBadge: '🧠 يفكّر بعمق...',
            );
          } else if (event is AgentToolCallEvent) {
            toolCalls.add(event.toolCall);
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              thinkingContent:
                  currentThinkingContent.isNotEmpty ? currentThinkingContent : null,
              toolCalls: List.from(toolCalls),
              isStreaming: true,
              statusBadge: '🛠️ ينفّذ: ${event.toolCall.toolName}',
            );
          } else if (event is AgentStatusEvent) {
            state = state.copyWith(activeStatus: event.status);
          } else if (event is AgentErrorEvent) {
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent.isEmpty
                  ? '⚠️ ${event.message}'
                  : '$currentAssistantContent\n\n*(تنبيه: ${event.message})*',
              thinkingContent:
                  currentThinkingContent.isNotEmpty ? currentThinkingContent : null,
              isStreaming: false,
              statusBadge: null,
            );
            state = state.copyWith(
              isStreaming: false,
              clearStatus: true,
              errorMessage: event.message,
            );
            if (!completer.isCompleted) completer.complete();
          } else if (event is AgentDoneEvent) {
            if (!completer.isCompleted) completer.complete();
          }
        },
        onError: (e) {
          if (_isAborted) return;
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
      _activeSubscription = null;

      if (_isAborted) return;

      // Finalize the current assistant message
      _updateAssistantMessage(
        assistantMsgId,
        content: currentAssistantContent,
        toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
        thinkingContent:
            currentThinkingContent.isNotEmpty ? currentThinkingContent : null,
        isStreaming: false,
        statusBadge: null,
      );

      // حفظ رسالة المساعد
      final assistantMsg = state.messages.firstWhere(
        (m) => m.id == assistantMsgId,
        orElse: () => ChatMessage(
          id: assistantMsgId,
          role: MessageRole.assistant,
          content: currentAssistantContent,
          timestamp: DateTime.now(),
          thinkingContent:
              currentThinkingContent.isNotEmpty ? currentThinkingContent : null,
        ),
      );
      await _persistMessage(assistantMsg);

      // If the model called any tools, execute them and continue the agent loop
      if (toolCalls.isNotEmpty) {
        state = state.copyWith(
            activeStatus: 'جارٍ استكمال تنفيذ الأداة...');

        final newMessages = List<ChatMessage>.from(state.messages);
        final List<ToolCallInfo> updatedToolCalls = [];

        for (final toolCall in toolCalls) {
          if (_isAborted) return;
          // ── اعتراض start_autonomous_task ─────────────────────────────
          if (toolCall.toolName == 'start_autonomous_task') {
            final goal =
                toolCall.arguments['goal'] as String? ?? currentAssistantContent;
            await _handleStartAutonomousTask(
              toolCall: toolCall,
              goal: goal,
              assistantMsgId: assistantMsgId,
              currentAssistantContent: currentAssistantContent,
              updatedToolCalls: updatedToolCalls,
              newMessages: newMessages,
            );
            // المهمة تعمل في الخلفية — الحلقة العادية تنتهي هنا
            state = state.copyWith(
              messages: newMessages,
              isStreaming: false,
              clearStatus: true,
            );
            return;
          }

          // ── اعتراض resume_task ─────────────────────────────────────
          if (toolCall.toolName == 'resume_task') {
            final taskId =
                toolCall.arguments['taskId'] as String? ?? '';
            final answer =
                toolCall.arguments['answer'] as String? ?? '';
            await _handleResumeTask(
              toolCall: toolCall,
              taskId: taskId,
              answer: answer,
              assistantMsgId: assistantMsgId,
              currentAssistantContent: currentAssistantContent,
              updatedToolCalls: updatedToolCalls,
              newMessages: newMessages,
            );
            state = state.copyWith(
              messages: newMessages,
              isStreaming: false,
              clearStatus: true,
            );
            return;
          }

          // ── حاجز أمان الدفع ───────────────────────────────────────
          final isSensitive =
              BrowserSecurityInterceptor.isAwaitingConfirmation;
          if (isSensitive) {
            final pendingCall = toolCall.copyWith(
              status: ToolCallStatus.awaitingConfirmation,
              summary:
                  'بانتظار تأكيدك لمتابعة هذا الإجراء الحساس...',
            );
            updatedToolCalls.add(pendingCall);
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              toolCalls: List.from(updatedToolCalls),
              isStreaming: true,
            );
          }

          // فتح لوحة المتصفح الحية تلقائياً عند استدعاء أي أداة متصفح
          if (toolCall.toolName == 'browse_url' ||
              toolCall.toolName == 'scroll_page' ||
              toolCall.toolName == 'inspect_visual_page' ||
              toolCall.toolName == 'click_element' ||
              toolCall.toolName == 'fill_input' ||
              toolCall.toolName == 'download_file') {
            final paramPreview = toolCall.arguments.values.isNotEmpty
                ? toolCall.arguments.values.first.toString()
                : '';
            _ref?.read(tasksProvider.notifier).setBrowserPanelVisible(
                  true,
                  lastAction: '${toolCall.toolName}: $paramPreview',
                );
          }

          String resultJson;
          ToolCallStatus execStatus = ToolCallStatus.success;
          String? errorMsg;

          try {
            resultJson = await ToolRegistry.executeTool(
              toolCall.toolName,
              toolCall.arguments,
            );
            if (resultJson.contains('"error"') ||
                resultJson.contains('"isBlocked":true')) {
              if (resultJson.contains('"isBlocked":true')) {
                execStatus = ToolCallStatus.awaitingConfirmation;
              } else {
                execStatus = ToolCallStatus.error;
              }
            }
          } catch (err) {
            resultJson = jsonEncode({'error': err.toString()});
            execStatus = ToolCallStatus.error;
            errorMsg = err.toString();
          }

          final finishedCall = toolCall.copyWith(
            status: execStatus,
            result: resultJson,
            summary: ToolPresentationFormatter.getFriendlySummary(
              toolCall.toolName,
              resultJson,
              errorMessage: errorMsg,
            ),
            errorMessage: errorMsg,
          );

          // Replace or add the finished tool call
          final existingIdx = updatedToolCalls
              .indexWhere((c) => c.callId == toolCall.callId);
          if (existingIdx != -1) {
            updatedToolCalls[existingIdx] = finishedCall;
          } else {
            updatedToolCalls.add(finishedCall);
          }

          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
          );

          final toolResultMsg = ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.tool,
            content: resultJson,
            timestamp: DateTime.now(),
            toolCallId: toolCall.callId,
          );
          newMessages.add(toolResultMsg);
          await _persistMessage(toolResultMsg);
        }

        if (_isAborted) return;
        state = state.copyWith(messages: newMessages);

        // Feed tool results back to the model to generate the final response
        await _runAgentLoop(newMessages);
      } else {
        // Final Answer Enforcement: فحص هل انتهى النموذج بصمت بعد استدعاء أدوات
        if (currentAssistantContent.trim().isEmpty) {
          final hadPreviousTools = conversationHistory.any((m) => m.role == MessageRole.tool);
          if (hadPreviousTools) {
            if (recoveryAttempt == 0) {
              debugPrint(
                  '[SilentEnd] provider=${state.selectedProviderId} model=${state.selectedModel} attempt=1');
              final toolNames = conversationHistory
                  .where((m) => m.toolCalls != null)
                  .expand((m) => m.toolCalls!)
                  .map((tc) => tc.toolName)
                  .toSet()
                  .join(', ');

              final reminderMsg = ChatMessage(
                id: _uuid.v4(),
                role: MessageRole.user,
                content:
                    'نفّذتَ الأدوات التالية بنجاح: [$toolNames]. قدّم الآن إجابتك وشرحك النهائي الواضح للمستخدم — لا تستدعِ أي أدوات إضافية.',
                timestamp: DateTime.now(),
              );

              final retryHistory = List<ChatMessage>.from(conversationHistory)..add(reminderMsg);
              await _runAgentLoop(retryHistory, recoveryAttempt: 1);
              return;
            } else {
              debugPrint(
                  '[SilentEnd] provider=${state.selectedProviderId} model=${state.selectedModel} attempt=2');
              final executedTools = conversationHistory
                  .where((m) => m.toolCalls != null)
                  .expand((m) => m.toolCalls!)
                  .toList();

              final toolSummaries =
                  executedTools.map((t) => '- ${t.summary ?? t.toolName}').join('\n');
              final fallbackAnswer =
                  'خوارزمي نفّذ العمليات التالية بنجاح:\n$toolSummaries\n\n(تم إنجاز المطلوب. أخبرني إن كنت بحاجة لأي استفسار إضافي).';

              currentAssistantContent = fallbackAnswer;
              _updateAssistantMessage(
                assistantMsgId,
                content: currentAssistantContent,
                thinkingContent:
                    currentThinkingContent.isNotEmpty ? currentThinkingContent : null,
                isStreaming: false,
                statusBadge: null,
              );
              final fallbackMsg = ChatMessage(
                id: assistantMsgId,
                role: MessageRole.assistant,
                content: currentAssistantContent,
                timestamp: DateTime.now(),
                thinkingContent:
                    currentThinkingContent.isNotEmpty ? currentThinkingContent : null,
              );
              await _persistMessage(fallbackMsg);
              state = state.copyWith(isStreaming: false, clearStatus: true);
              return;
            }
          }
        }

        state = state.copyWith(isStreaming: false, clearStatus: true);
      }
    } catch (e) {
      if (_isAborted) return;
      _updateAssistantMessage(
        assistantMsgId,
        content:
            '$currentAssistantContent\n\n*(حدث خطأ غير متوقع: $e)*',
        isStreaming: false,
        statusBadge: null,
      );
      state = state.copyWith(
        isStreaming: false,
        clearStatus: true,
        errorMessage: e.toString(),
      );
    }
  }

  // ── Autonomous Task Integration ────────────────────────────────────────────

  /// يبدأ TaskExecutionEngine ويعرض خطواته كـ ToolCallCards داخل فقاعة الرد
  Future<void> _handleStartAutonomousTask({
    required ToolCallInfo toolCall,
    required String goal,
    required String assistantMsgId,
    required String currentAssistantContent,
    required List<ToolCallInfo> updatedToolCalls,
    required List<ChatMessage> newMessages,
  }) async {
    // أضف بطاقة البدء
    final startCall = toolCall.copyWith(
      status: ToolCallStatus.success,
      result: jsonEncode({'status': 'task_initiated', 'goal': goal}),
      summary: '🚀 جارٍ تنفيذ المهمة المستقلة...',
    );
    updatedToolCalls.add(startCall);
    _updateAssistantMessage(
      assistantMsgId,
      content: currentAssistantContent,
      toolCalls: List.from(updatedToolCalls),
      isStreaming: true,
      statusBadge: '⚙️ يُنفّذ المهمة...',
    );
    state = state.copyWith(activeStatus: '⚙️ يُنفّذ المهمة المستقلة...');

    // تشغيل المحرك مع callbacks ترسل التحديثات للشات مباشرة
    final task = await TaskExecutionEngine.instance.startTask(
      goal: goal,
      callbacks: TaskExecutionCallbacks(
        onToolCall: (tc) {
          updatedToolCalls.add(tc.copyWith(
            status: ToolCallStatus.running,
            summary: '🔄 ينفّذ: ${tc.toolName}...',
          ));
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
            statusBadge: '🛠️ ${tc.toolName}',
          );
        },
        onToolResult: (tc) {
          final idx =
              updatedToolCalls.indexWhere((c) => c.callId == tc.callId);
          if (idx != -1) {
            updatedToolCalls[idx] = tc;
          } else {
            updatedToolCalls.add(tc);
          }
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
          );
        },
        onTextChunk: (chunk) {
          // تجاهل — النص يصدر في onComplete
        },
        onProgress: (progress) {
          state = state.copyWith(activeStatus: '📊 $progress');
        },
        onAskUser: (question) {
          _activeAutonomousTaskId = null;
          // أضف بطاقة السؤال
          final askCall = ToolCallInfo(
            callId: _uuid.v4(),
            toolName: 'ask_user',
            arguments: {'question': question},
            status: ToolCallStatus.success,
            summary: '❓ $question',
            result: jsonEncode({'question': question}),
          );
          updatedToolCalls.add(askCall);
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent.isEmpty
                ? question
                : '$currentAssistantContent\n\n❓ **$question**',
            toolCalls: List.from(updatedToolCalls),
            isStreaming: false,
            statusBadge: null,
          );
          state = state.copyWith(isStreaming: false, clearStatus: true);
          // حفظ الرسالة بالحالة الحالية
          final msg = state.messages.firstWhere(
            (m) => m.id == assistantMsgId,
            orElse: () => ChatMessage(
              id: assistantMsgId,
              role: MessageRole.assistant,
              content: question,
              timestamp: DateTime.now(),
            ),
          );
          _persistMessage(msg);
        },
        onComplete: (summary) {
          _activeAutonomousTaskId = null;
          final completeCall = ToolCallInfo(
            callId: _uuid.v4(),
            toolName: 'complete_task',
            arguments: {'summary': summary},
            status: ToolCallStatus.success,
            summary: '✅ اكتملت المهمة',
            result: jsonEncode({'summary': summary}),
          );
          updatedToolCalls.add(completeCall);
          _updateAssistantMessage(
            assistantMsgId,
            content: summary,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: false,
            statusBadge: null,
          );
          state = state.copyWith(isStreaming: false, clearStatus: true);
          // حفظ الرسالة النهائية
          final msg = state.messages.firstWhere(
            (m) => m.id == assistantMsgId,
            orElse: () => ChatMessage(
              id: assistantMsgId,
              role: MessageRole.assistant,
              content: summary,
              timestamp: DateTime.now(),
            ),
          );
          _persistMessage(msg);
        },
        onTaskUpdated: (task) {
          // تحديث قائمة المحادثات لتعكس آخر تحديث
          loadConversations();
        },
      ),
    );
    _activeAutonomousTaskId = task.id;
  }

  /// يستأنف مهمة معلقة عبر TaskExecutionEngine
  Future<void> _handleResumeTask({
    required ToolCallInfo toolCall,
    required String taskId,
    required String answer,
    required String assistantMsgId,
    required String currentAssistantContent,
    required List<ToolCallInfo> updatedToolCalls,
    required List<ChatMessage> newMessages,
  }) async {
    final resumeCall = toolCall.copyWith(
      status: ToolCallStatus.success,
      result:
          jsonEncode({'status': 'task_resumed', 'taskId': taskId, 'answer': answer}),
      summary: '▶️ استئناف المهمة...',
    );
    updatedToolCalls.add(resumeCall);
    _updateAssistantMessage(
      assistantMsgId,
      content: currentAssistantContent,
      toolCalls: List.from(updatedToolCalls),
      isStreaming: true,
      statusBadge: '▶️ يستأنف...',
    );
    state = state.copyWith(activeStatus: '▶️ يستأنف المهمة...');

    _activeAutonomousTaskId = taskId;
    // استئناف المهمة مع نفس منطق الـ callbacks
    await TaskExecutionEngine.instance.resumeTask(
      taskId,
      answer,
      callbacks: TaskExecutionCallbacks(
        onToolCall: (tc) {
          updatedToolCalls.add(tc.copyWith(
            status: ToolCallStatus.running,
            summary: '🔄 ينفّذ: ${tc.toolName}...',
          ));
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
            statusBadge: '🛠️ ${tc.toolName}',
          );
        },
        onToolResult: (tc) {
          final idx =
              updatedToolCalls.indexWhere((c) => c.callId == tc.callId);
          if (idx != -1) {
            updatedToolCalls[idx] = tc;
          } else {
            updatedToolCalls.add(tc);
          }
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
          );
        },
        onProgress: (progress) {
          state = state.copyWith(activeStatus: '📊 $progress');
        },
        onAskUser: (question) {
          _activeAutonomousTaskId = null;
          final askCall = ToolCallInfo(
            callId: _uuid.v4(),
            toolName: 'ask_user',
            arguments: {'question': question},
            status: ToolCallStatus.success,
            summary: '❓ $question',
            result: jsonEncode({'question': question}),
          );
          updatedToolCalls.add(askCall);
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent.isEmpty
                ? question
                : '$currentAssistantContent\n\n❓ **$question**',
            toolCalls: List.from(updatedToolCalls),
            isStreaming: false,
            statusBadge: null,
          );
          state = state.copyWith(isStreaming: false, clearStatus: true);
        },
        onComplete: (summary) {
          _activeAutonomousTaskId = null;
          final completeCall = ToolCallInfo(
            callId: _uuid.v4(),
            toolName: 'complete_task',
            arguments: {'summary': summary},
            status: ToolCallStatus.success,
            summary: '✅ اكتملت المهمة',
            result: jsonEncode({'summary': summary}),
          );
          updatedToolCalls.add(completeCall);
          _updateAssistantMessage(
            assistantMsgId,
            content: summary,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: false,
            statusBadge: null,
          );
          state = state.copyWith(isStreaming: false, clearStatus: true);
          final msg = state.messages.firstWhere(
            (m) => m.id == assistantMsgId,
            orElse: () => ChatMessage(
              id: assistantMsgId,
              role: MessageRole.assistant,
              content: summary,
              timestamp: DateTime.now(),
            ),
          );
          _persistMessage(msg);
        },
        onTaskUpdated: (task) {
          loadConversations();
        },
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _updateAssistantMessage(
    String id, {
    required String content,
    List<ToolCallInfo>? toolCalls,
    required bool isStreaming,
    String? statusBadge,
    String? thinkingContent,
  }) {
    final updated = state.messages.map((m) {
      if (m.id == id) {
        return m.copyWith(
          content: content,
          toolCalls: toolCalls ?? m.toolCalls,
          isStreaming: isStreaming,
          statusBadge: statusBadge,
          thinkingContent: thinkingContent ?? m.thinkingContent,
        );
      }
      return m;
    }).toList();

    state = state.copyWith(messages: updated);
  }
}
