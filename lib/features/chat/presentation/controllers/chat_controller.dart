import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';
import 'package:uuid/uuid.dart';

import 'package:khwarizmi/core/security/browser_security_interceptor.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/core/services/agent_identity_service.dart';
import 'package:khwarizmi/core/execution/execution_types.dart';
import 'package:khwarizmi/features/agent/data/task_database.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/agent/services/task_execution_engine.dart';
import 'package:khwarizmi/features/chat/data/chat_history_database.dart';
import 'package:khwarizmi/features/chat/domain/entities/conversation.dart';
import 'package:khwarizmi/features/chat/presentation/utils/conversation_context_guard.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_detector.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_guard.dart';
import 'package:khwarizmi/features/chat/presentation/utils/task_complexity_router.dart';
import 'package:khwarizmi/features/chat/presentation/utils/unified_interceptor.dart';
import 'package:khwarizmi/features/chat/presentation/utils/tool_presentation_formatter.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/memory/data/memory_repository.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/providers/data/retry_utils.dart';
import 'package:khwarizmi/features/providers/domain/ai_provider.dart';
import 'package:khwarizmi/features/scheduler/data/reminder_database.dart';
import 'package:khwarizmi/features/scheduler/services/scheduler_service.dart';
import 'package:khwarizmi/features/agent/presentation/controllers/task_provider.dart';
import 'package:khwarizmi/features/projects/data/project_database.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_state.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/coding_modes.dart';

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

  /// تعيين النمط البرمجي التخصصي النشط
  void setActiveCodingMode(CodingMode mode) {
    state = state.copyWith(activeCodingMode: mode);
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
    if (activeProvider == 'gemini' && _deprecatedModels.contains(savedModel)) {
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
    await SecureStorageService.setProviderModel(
      state.selectedProviderId,
      model,
    );
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
      final conv = await ChatHistoryDatabase.getConversationById(
        conversationId,
      );
      if (conv == null) {
        state = state.copyWith(isLoadingHistory: false);
        return;
      }
      final messages = await ChatHistoryDatabase.getMessagesForConversation(
        conversationId,
      );

      // استعادة المشروع المرتبط بالمحادثة إن وجد
      final associatedProject = await ProjectDatabase.getProjectForConversation(
        conversationId,
      );
      if (associatedProject != null) {
        await ProjectManager.instance.openProject(associatedProject.rootPath);
      }

      // استعادة النمط البرمجي النشط للمحادثة
      CodingMode restoredMode = CodingMode.manager;
      if (conv.activeCodingMode != null) {
        try {
          restoredMode = CodingMode.values.firstWhere(
            (m) => m.name == conv.activeCodingMode,
            orElse: () => CodingMode.manager,
          );
        } catch (_) {}
      }

      state = state.copyWith(
        activeConversation: conv,
        messages: messages,
        isLoadingHistory: false,
        clearError: true,
        clearStatus: true,
        isCodingAgentMode: associatedProject != null
            ? true
            : state.isCodingAgentMode,
        activeCodingMode: restoredMode,
      );
    } catch (e) {
      state = state.copyWith(isLoadingHistory: false);
      debugPrint('[ChatController] Failed to open conversation: $e');
    }
  }

  /// إعادة تسمية محادثة
  Future<void> renameConversation(
    String conversationId,
    String newTitle,
  ) async {
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
    final updated = state.conversations
        .where((c) => c.id != conversationId)
        .toList();
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
  Future<Conversation> _ensureActiveConversation(
    String firstUserMessage,
  ) async {
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
      activeCodingMode: state.activeCodingMode.name,
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
    if (!state.isStreaming &&
        _activeSubscription == null &&
        _activeAutonomousTaskId == null) {
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

    // إصلاح 03: إنهاء انتظار أي قرار Diff معلّق رفضاً صريحاً — طلب المستخدم
    // الإيقاف هو إلغاء عمداً، لا مهلة صامتة. التعديل المعلّق يبقى معروضاً
    // للمراجعة اللاحقة ولم يُحذف.
    ProjectManager.instance.cancelAllPendingDecisions();

    // إصلاح 10: قطع أي أداة قيد التنفيذ فعلياً — الإيقاف كان يقطع بث
    // الأحداث فقط ويترك الأمر الجاري (مثل أمر ترمينال طويل) حتى نهايته.
    ToolRegistry.cancelActiveTools('تم الإيقاف بواسطة المستخدم');

    final messages = List<ChatMessage>.from(state.messages);
    if (messages.isNotEmpty) {
      final lastMsg = messages.last;
      if (lastMsg.role == MessageRole.assistant) {
        final hasTools =
            lastMsg.toolCalls != null && lastMsg.toolCalls!.isNotEmpty;
        final hasText = lastMsg.content.trim().isNotEmpty;

        if (!hasText && !hasTools) {
          // كانت فارغة قيد التفكير الأولي فقط → نحذف الفقاعة الفارغة تماماً
          messages.removeLast();
          if (state.activeConversation != null) {
            ChatHistoryDatabase.deleteMessage(lastMsg.id);
          }
        } else {
          // تحتوي على نص جزئي أو أدوات نُفذت → نختم الرسالة مع ملاحظة إيقاف
          // (بناء جديد لا copyWith — لنفس سبب الختم: إسقاط الشارة القديمة)
          final stoppedContent = hasText
              ? '${lastMsg.content}\n\n*(تم إيقاف التوليد بواسطة المستخدم)*'
              : '*(تم إيقاف التفكير بواسطة المستخدم)*';
          final stoppedMsg = ChatMessage(
            id: lastMsg.id,
            role: lastMsg.role,
            content: stoppedContent,
            timestamp: lastMsg.timestamp,
            toolCalls: lastMsg.toolCalls,
            toolCallId: lastMsg.toolCallId,
            toolName: lastMsg.toolName,
            thinkingContent: lastMsg.thinkingContent,
            isStreaming: false,
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

    final currentMessages = List<ChatMessage>.from(state.messages)
      ..add(userMessage);

    state = state.copyWith(
      messages: currentMessages,
      isStreaming: true,
      clearError: true,
      activeStatus: 'يفكّر...',
    );

    final apiKey = state.apiKey;
    final activeProvider = ProviderRegistry.getProvider(
      state.selectedProviderId,
    );
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
    int promiseRecoveryAttempt = 0,
  }) async {
    conversationHistory = ConversationContextGuard.compressIfNeeded(
      conversationHistory,
    );

    final provider = ProviderRegistry.getProvider(state.selectedProviderId);
    final allTools = ToolRegistry.getChatDefinitions();

    // ── تصفية الأدوات حسب النمط البرمجي النشط ───────────────────────────────
    final activeMode = state.activeCodingMode;
    final filteredTools = ToolFilter.filterForMode(allTools, activeMode);

    final systemPrompt =
        state.systemPrompt ?? await AgentIdentityService.loadSystemPrompt();

    // Auto-retrieve relevant memories to inject into system prompt
    String effectiveSystemPrompt = systemPrompt;
    try {
      final userMessages = conversationHistory.where(
        (m) => m.role == MessageRole.user,
      );
      if (userMessages.isNotEmpty) {
        final lastUserText = userMessages.last.content;
        if (TaskComplexityRouter.shouldRouteToAutonomousTask(lastUserText)) {
          effectiveSystemPrompt += TaskComplexityRouter.systemPromptAddendum;
        }
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
              .map((sm) => '- [${sm.entry.category}] ${sm.entry.content}')
              .join('\n');
          effectiveSystemPrompt +=
              '''

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
      final pendingTasks = await TaskDatabase.getTasksByStatus(
        TaskStatus.waitingForUser,
      );
      if (pendingTasks.isNotEmpty) {
        final pendingInfo = pendingTasks
            .map(
              (t) =>
                  '- مهمة ID=${t.id}: "${t.goal}" — سؤالها المعلق: "${t.pendingQuestion ?? ''}"',
            )
            .join('\n');
        effectiveSystemPrompt +=
            '''

\n[مهام معلقة تنتظر رد المستخدم — قرّر بنفسك هل رسالة المستخدم الحالية إجابة على إحداها]:
$pendingInfo
إذا كانت رسالة المستخدم رداً فعلياً على سؤال مهمة معلقة، استدعِ أداة resume_task(taskId, answer).
إذا كانت رسالة المستخدم شيئاً مختلفاً تماماً، أجب عنها طبيعياً ولا تستدعِ resume_task.
''';
      }
    } catch (_) {}

    // ── حقن الفهرس الخفيف للمهارات النصية (Text Skills Index) ────────────
    try {
      final textSkillsIndex = await TextSkillService.instance
          .getLightweightIndexPrompt();
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
        debugPrint(
          '[ChatController] 📌 Project map injection: ${mapInjected ? "✅ YES ($mapLen chars)" : "❌ NO — map is null/empty"}',
        );
        effectiveSystemPrompt +=
            '''

[سياق المشروع البرمجي النشط — وكيل برمجي]:
أنت تعمل الآن كـ "وكيل برمجي" (Software Coding Agent) على المشروع التالي:
- اسم المشروع: ${activeProj.name}
- مسار جذر المشروع: ${activeProj.rootPath}
${mapInjected ? '\n[خريطة بنية المشروع — اقرأها كاملاً قبل أي خطوة]:\n$projectMap\n' : ''}
القواعد الإلزامية للتعامل مع هذا المشروع:
1. **خريطة المشروع أعلاه هي مصدرك الأساسي والوحيد لفهم بنية المشروع.** اقرأها كاملاً أولاً.
2. **ممنوع** استدعاء list_project_files لأي مجلد ظاهر بالخريطة — الخريطة تُغني عنه تماماً.
3. استدعِ list_project_files فقط لمجلد غير موجود في الخريطة إطلاقاً (مثلاً: مجلد أُنشئ حديثاً بعد توليد الخريطة).
4. للبحث عن أين يظهر رمز أو دالة أو كلاس أو نص عبر المشروع: **استخدم search_project_code أولاً**، ولا تخمّن الملفات بقراءتها كاملة عبر read_project_file.
5. لقراءة محتوى ملف بعينه بعد تحديد موقعه: استخدم read_project_file (ويُفضّل بالأسطر المحددة start_line و line_count للملفات الكبيرة بدلاً من قراءة الملف كاملاً).
6. لأي تعديل جزئي على ملف موجود: استخدم propose_file_patch، ولإنشاء ملف جديد: استخدم propose_file_change.
7. لتشغيل الأوامر: استخدم run_terminal_command. الأوامر الخطرة تتطلب تأكيداً.
8. إذا تغيّر هيكل المشروع بعد تعديلات: استدعِ refresh_project_map لتحديث الخريطة.
''';
      } else {
        effectiveSystemPrompt += '''

[سياق وضع الوكيل البرمجي]:
أنت في وضع "وكيل برمجي"، لكن المستخدم لم يحدد مسار المشروع بعد. اطلب منه اختيار مجلد المشروع من الزر المخصص أعلى شريط الإدخال.
''';
      }
    }

    // ── إضافة توجيه النمط البرمجي النشط للـ system prompt ───────────────────
    final modeConfig = codingModeConfigs[state.activeCodingMode];
    if (modeConfig != null && modeConfig.systemPromptAddendum.isNotEmpty) {
      effectiveSystemPrompt += '\n\n${modeConfig.systemPromptAddendum}';
    }

    // ── توجيه إرسال وإنشاء الملفات كبطاقات تفاعلية للمستخدم ─────────────────
    effectiveSystemPrompt += '''

[إرسال وإنشاء الملفات للمستخدم كبطاقات تفاعلية]:
عندما يطلب منك المستخدم إرسال ملف، أو إنشاء ملف، أو كتابة ملف كود أو ماركداون (مثل: "ارسل ملف md", "اكتب لي ملف...", "احفظ التقرير في ملف"):
1. استدعِ أداة deliver_file فوراً لكتابة محتوى الملف كاملاً وتسليمه.
2. لا تكتب مسارات الملفات الطويلة كنصوص جافة في المحادثة، ولا تقل للمستخدم "حفظته في مكان ما وهذا مساره".
3. واجهة خوارزمي ستقوم تلقائياً بتحويل الملف إلى بطاقة ملف تفاعلية أنيقة تمكن المستخدم من النقر عليها وفتح الملف في اللوحة الجانبية فوراً أو تحميله.
4. اكتفِ في رسالتك بملخص سريع وجميل لمحتوى الملف وما يتضمنه.
''';

    // ── توجيه مشدد عند وجود وعود تنفيذ سابقة دون استدعاء فعلي ─────────────
    final priorPromises = ExecutionPromiseDetector.countConsecutivePromises(
      conversationHistory,
    );
    if (priorPromises >= 1) {
      effectiveSystemPrompt += '''

[تنبيه نظام حاسم — منع الوعد بلا تنفيذ]:
لقد وعدت المستخدم بالتنفيذ في رد سابق دون استدعاء أداة فعلية.
ممنوع منعاً باتاً كتابة أي وعد أو نية تنفيذ ("سأقوم بـ/سأنشئ/سأكتب...") دون استدعاء أداة فعلية في هذا الرد مباشرة.
إما أن تستدعي الأداة المناسبة فوراً (مثل deliver_file أو propose_file_change)، أو تشرح للمستخدم ما يمنعك بصراحة ودون أي وعود.
''';
    }

    // ── إعداد التفكير الموسَّع (ThinkingConfig) ──────────────────────────
    final providerConfig = ProviderRegistry.getConfig(state.selectedProviderId);
    final modelSupportsThinking =
        providerConfig?.doesModelSupportThinking(state.selectedModel) ?? false;
    final modelSupportsAdaptiveThinking =
        providerConfig?.doesModelSupportAdaptiveThinking(state.selectedModel) ??
        false;

    ThinkingConfig? thinkingConfig;
    final isCoding = state.isCodingAgentMode;
    final isThinkingEnabled = state.thinkingEnabled;

    if (isCoding) {
      // في وضع الكود: تفضيل التفكير التكيّفي بأقصى جهد، وإلا fallback للميزانية الثابتة
      if (modelSupportsAdaptiveThinking) {
        thinkingConfig = ThinkingConfig.adaptiveCoding;
      } else if (modelSupportsThinking) {
        thinkingConfig = ThinkingConfig.coding;
      }
    } else if (isThinkingEnabled) {
      // في المحادثة العادية مع تفعيل التفكير: تفضيل التكيّفي بمستوى high، وإلا fallback للميزانية الثابتة
      if (modelSupportsAdaptiveThinking) {
        thinkingConfig = ThinkingConfig.adaptiveRegular;
      } else if (modelSupportsThinking) {
        thinkingConfig = ThinkingConfig.regular;
      }
    }

    _isAborted = false;
    final assistantMsgId = _uuid.v4();
    var currentAssistantContent = '';
    var currentThinkingContent = '';
    final List<ToolCallInfo> toolCalls = [];

    // Add initial assistant streaming placeholder
    var updatedMessages = List<ChatMessage>.from(conversationHistory)
      ..add(
        ChatMessage(
          id: assistantMsgId,
          role: MessageRole.assistant,
          content: '',
          timestamp: DateTime.now(),
          isStreaming: true,
        ),
      );

    state = state.copyWith(messages: updatedMessages);

    // ── Fix 1: Proactive programmatic routing to autonomous task ─────────────────
    // Check if this is a complex task that should route to autonomous execution
    // This runs BEFORE the model call to guarantee routing (not just prompt advisory)
    final userMessages = conversationHistory.where(
      (m) => m.role == MessageRole.user,
    );
    if (userMessages.isNotEmpty) {
      final lastUserText = userMessages.last.content;
      if (TaskComplexityRouter.shouldRouteToAutonomousTask(lastUserText)) {
        debugPrint(
          '[ChatController] 🔀 Proactive routing: Complex task detected — invoking start_autonomous_task directly',
        );
        // Synthetically invoke autonomous task handling
        await _handleStartAutonomousTask(
          toolCall: ToolCallInfo(
            callId: _uuid.v4(),
            toolName: 'start_autonomous_task',
            arguments: {'goal': lastUserText},
            status: ToolCallStatus.running,
            summary: '🧠 يُحلّل المهمة ويضع الخطة...',
          ),
          goal: lastUserText,
          assistantMsgId: assistantMsgId,
          currentAssistantContent: currentAssistantContent,
          updatedToolCalls: toolCalls,
          newMessages: updatedMessages,
        );
        return; // The autonomous task handler takes over from here
      }
    }

    try {
      final stream = RetryUtils.executeStreamWithRetry(
        streamFactory: () => provider.sendMessage(
          history: conversationHistory,
          availableTools: filteredTools,
          systemPrompt: effectiveSystemPrompt,
          apiKey: state.apiKey ?? '',
          modelName: state.selectedModel,
          thinking: thinkingConfig,
        ),
        config: RetryConfig.apiStream,
        correlationId: assistantMsgId,
        context: 'ChatController._runAgentLoop',
      );

      final completer = Completer<void>();
      StreamSubscription<AgentEvent>? activeSubscription;
      bool streamHadError = false;
      bool providerErrorSeen = false;

      // تاريخ حلقة استرداد «الوعد بلا تنفيذ» — تُشغَّل الحلقة الجديدة من
      // خارج الـ listener بعد إحكام إغلاق هذه الحلقة (لا حلقة شبح معلقة).
      List<ChatMessage>? promiseRecoveryHistory;
      Timer? progressTimer;
      int progressSeconds = 0;

      // ── تتبع طور النموذج — ليعرف المستخدم ماذا يحدث فعلاً ────────────────
      DateTime? lastEventAt;
      bool sawThinking = false;
      bool sawText = false;

      // ── ميكانيكية opencode: لا قتل للبث الصامت ─────────────────────────────
      // النماذج الضخمة (مثل nemotron-550b) تولّد الرد على الخادم دفعة
      // واحدة وتؤجل الإرسال، فيصمت البث دقائق وهو حي ويعمل — قتله بعد 90
      // ثانية كان يهدر الرد الكامل عند وصوله ويعيد الطلب من الصفر.
      // الآن: عدّاد انتظار حي بلا سقف يُظهر للمستخدم أين وصل الطلب،
      // وقطع البث الوحيد هو زر الإيقاف اليدوي أو خطأ فعلي من المزوّد.
      //
      // العدّاد واعٍ بالطور: يميّز «لم يصل شيء بعد» من «وصل تفكير ثم سكت
      // (الخادم يجهّز الرد)» من «وصل نص جزئي» — فلا يقول «انتظر الرد»
      // بعدما انتهى التفكير فعلاً.
      progressTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (completer.isCompleted) {
          timer.cancel();
          return;
        }
        progressSeconds += 15;
        final lastAt = lastEventAt;
        final String status;
        if (lastAt == null) {
          // لم يصل أي حدث بعد — مرحلة time-to-first-token
          status = '⏳ ينتظر أول استجابة من الخادم... ($progressSecondsث)';
        } else {
          final silentSecs = DateTime.now().difference(lastAt).inSeconds;
          // الأحداث تتدفق بكثافة الآن (نص/تفكير يتراكم أمام عينيك) —
          // التحديث هنا سيطغى بلا فائدة، والتغذية البصرية موجودة أصلاً.
          if (silentSecs < 10) return;
          final phase = sawText
              ? '✍️ آخر نشاط: كتابة الرد — بانتظار بقية الرد'
              : '🧠 آخر نشاط: تفكير — اكتمل استقباله والخادم يجهّز الرد الآن';
          status = '$phase... بلا استجابة جديدة منذ $silentSecsث '
              '(البث مفتوح والخادم يعمل)';
        }
        state = state.copyWith(activeStatus: status);
      });

      // السقف المطلق — الحماية الوحيدة من اتصال ميت فعلاً (بلا إيقاف يدوي):
      // بعد 10 دقائق كاملة دون أي اكتمال نعتبر الاتصال ميتاً ونختم برسالة
      // واضحة. صمت النماذج الضخمة (دقائق معدودة) لا يقترب من هذا السقف.
      final absoluteCapTimer = Timer(
        TaskExecutionEngineDefaults.absoluteStreamCap,
        () {
          if (completer.isCompleted) return;
          debugPrint(
            '[ChatController] Absolute stream cap '
            '(${TaskExecutionEngineDefaults.absoluteStreamCap.inMinutes} min) '
            '— dead connection, finalizing.',
          );
          if (currentAssistantContent.trim().isEmpty) {
            currentAssistantContent =
                '⚠️ انقطع الاتصال بالخادم (تجاوز 10 دقائق دون اكتمال الرد). '
                'تحقق من الشبكة وأعد المحاولة، أو جرّب موديلاً أخف.';
          }
          streamHadError = true;
          activeSubscription?.cancel();
          if (!completer.isCompleted) completer.complete();
        },
      );

      activeSubscription = stream.listen(
        (event) async {
          if (_isAborted) return;
          if (event is AgentTextChunk) {
            // تتبع الطور: أول نص وصل → النموذج يكتب الرد فعلاً الآن
            lastEventAt = DateTime.now();
            if (!sawText) {
              sawText = true;
              state = state.copyWith(activeStatus: '✍️ يكتب الرد...');
            }
            currentAssistantContent += event.text;
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              thinkingContent: currentThinkingContent.isNotEmpty
                  ? currentThinkingContent
                  : null,
              isStreaming: true,
              statusBadge: null,
            );
          } else if (event is AgentThinkingChunkEvent) {
            // تتبع الطور: أول تفكير وصل → النموذج يفكّر فعلاً الآن
            lastEventAt = DateTime.now();
            if (!sawThinking) {
              sawThinking = true;
              state = state.copyWith(activeStatus: '🧠 يفكّر بعمق...');
            }
            currentThinkingContent += event.text;
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              thinkingContent: currentThinkingContent,
              isStreaming: true,
              statusBadge: '🧠 يفكّر بعمق...',
            );
          } else if (event is AgentToolCallEvent) {
            lastEventAt = DateTime.now();
            final friendlyToolName = ToolPresentationFormatter
                .getFriendlyToolName(
                  event.toolCall.toolName,
                  event.toolCall.arguments,
                );
            state = state.copyWith(activeStatus: '⚙️ $friendlyToolName...');
            toolCalls.add(event.toolCall);
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              thinkingContent: currentThinkingContent.isNotEmpty
                  ? currentThinkingContent
                  : null,
              toolCalls: List.from(toolCalls),
              isStreaming: true,
              // نستخدم الاسم الإنساني بدلاً من اسم الدالة البرمجي
              statusBadge: '⚙️ $friendlyToolName',
            );
          } else if (event is AgentRetryEvent) {
            // عرض بانر إعادة الاتصال التلقائي (مثل Zoo Code)
            final delaySec = event.delay.inSeconds;
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              thinkingContent: currentThinkingContent.isNotEmpty
                  ? currentThinkingContent
                  : null,
              // إصلاح: قائمة فارغة صريحة تمسح بطاقات الأدوات القديمة المعروضة
              // من المحاولة الفاشلة — تمرير null كان يُبقيها (copyWith ??).
              toolCalls: const [],
              isStreaming: true,
              statusBadge:
                  '🔄 انقطع الاتصال — إعادة المحاولة خلال $delaySec ثوانٍ (${event.attempt}/${event.maxAttempts})...',
            );
            // إعادة تعيين النص المتراكم لتجنب التكرار المشوه عند إعادة البث
            currentAssistantContent = '';
            currentThinkingContent = '';
            toolCalls.clear();
            // تصفير تتبع الطور — البث يبدأ من جديد فتعود الحالة الدقيقة
            lastEventAt = null;
            sawThinking = false;
            sawText = false;
          } else if (event is AgentStatusEvent) {
            lastEventAt = DateTime.now();
            state = state.copyWith(activeStatus: event.status);
          } else if (event is AgentErrorEvent) {
            // إصلاح: حدّث المتغير المحلي أيضاً — كان يُحدَّث فقط عرض الرسالة
            // فيُمسح التنبيه فوراً عند الختم لاحقاً بالمحتوى القديم.
            providerErrorSeen = true;
            currentAssistantContent = currentAssistantContent.isEmpty
                ? '⚠️ ${event.message}'
                : '$currentAssistantContent\n\n*(تنبيه: ${event.message})*';
            _updateAssistantMessage(
              assistantMsgId,
              content: currentAssistantContent,
              thinkingContent: currentThinkingContent.isNotEmpty
                  ? currentThinkingContent
                  : null,
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
            // ── نقطة الاعتراض الموحدة: تحدث فور انتهاء البث، قبل وصول الرد للمستخدم ──
            final assistantMsg = ChatMessage(
              id: assistantMsgId,
              role: MessageRole.assistant,
              content: currentAssistantContent,
              timestamp: DateTime.now(),
              toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
              thinkingContent: currentThinkingContent.isNotEmpty
                  ? currentThinkingContent
                  : null,
            );

            final interception = UnifiedInterceptor.intercept(
              conversationHistory: conversationHistory,
              assistantMessage: assistantMsg,
              toolCalls: toolCalls,
              promiseRecoveryAttempt: promiseRecoveryAttempt,
              timing: InterceptionTiming.postAssistantTurn,
            );

            if (interception.isIntercepted) {
              debugPrint(
                '[ChatController] UnifiedInterceptor triggered: ${interception.debugInfo}',
              );

              // تطبيق الاعتراض على الحالة الحالية — نص الاستبدال حسب نوع
              // الاعتراض (استرداد فعلي أم تنبيه فقط بعد استنفاد المحاولات)
              final interceptedMessages = UnifiedInterceptor.applyInterception(
                currentMessages: state.messages,
                result: interception,
                assistantMsgId: assistantMsgId,
                interceptedAssistantStub:
                    interception.action ==
                        ExecutionPromiseGuardAction.interceptAndRecover
                    ? ExecutionPromiseGuard.interceptedAssistantStub
                    : ExecutionPromiseGuard.interceptedAssistantNoticeOnlyStub,
              );

              state = state.copyWith(messages: interceptedMessages);

              // حفظ الرسائل المحقونة
              for (final msg in interceptedMessages) {
                if (msg.id != assistantMsgId ||
                    interception.shouldInjectSystemTurn ||
                    interception.shouldInjectRecoveryUserMessage) {
                  await _persistMessage(msg);
                }
              }

              // ── إصلاح الحلقة الشبح ──────────────────────────────────────
              // لا تُستدعى حلقة الاسترداد من داخل الـ listener أبداً: كانت
              // تُستدعى هنا ثم return دون إكمال الـ completer، فتبقى هذه
              // الحلقة معلقة إلى الأبد عند completer.future ومعها الـ
              // progressTimer والـ watchdog المسلّح — وبعد 90 ثانية كان
              // الـ watchdog يستيقظ ويضبط isStreaming=false ويحقن خطأ
              // «حدث خطأ غير متوقع» بينما حلقة الاسترداد الحية ما زالت
              // تعمل. الآن نُغلق هذه الحلقة بإحكام ونُطلق الاسترداد من
              // خارج الـ listener بعد اكتمال completer.future.
              if (interception.action ==
                  ExecutionPromiseGuardAction.interceptAndRecover) {
                promiseRecoveryHistory = interceptedMessages;
              }
              if (!completer.isCompleted) completer.complete();
              return;
            }

            if (!completer.isCompleted) completer.complete();
          }
        },
        onError: (e) {
          if (_isAborted) return;
          debugPrint('[ChatController] Stream error: $e');
          streamHadError = true;
          if (currentAssistantContent.trim().isEmpty) {
            currentAssistantContent =
                '⚠️ انقطع البث قبل اكتمال الرد. (${e.toString()})';
          }
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: false,
      );

      // إصلاح: اربط الاشتراك الفعلي بحقل الإلغاء — كان الحقل لا يُعيَّن أبداً
      // فيبقى زر الإيقاف عاجزاً عن قطع بث الشات فعلياً.
      _activeSubscription = activeSubscription;

      await completer.future;

      progressTimer.cancel();
      absoluteCapTimer.cancel();
      _activeSubscription = null;

      if (_isAborted) return;

      // ── مسار استرداد «الوعد بلا تنفيذ» — من خارج الـ listener ───────────
      // الحلقة الحالية أُغلقت بإحكام (المؤقتات أُلغيت) قبل تشغيل حلقة
      // الاسترداد، فلا مؤقت شبح يستيقظ لاحقاً ليقتلها.
      if (promiseRecoveryHistory != null) {
        await _runAgentLoop(
          promiseRecoveryHistory!,
          promiseRecoveryAttempt: promiseRecoveryAttempt + 1,
        );
        return;
      }

      // ── انقطاع البث بعد نص جزئي: تنبيه صريح بدل الختم الصامت ──────────
      if (streamHadError && currentAssistantContent.trim().isNotEmpty) {
        final alreadyNoted = currentAssistantContent.contains('انقطع البث');
        if (!alreadyNoted) {
          currentAssistantContent +=
              '\n\n*(⚠️ انقطع البث قبل اكتمال الرد — قد يكون النص أعلاه ناقصاً)*';
        }
      }

      // Finalize the current assistant message — يُبنى من جديد (لا copyWith)
      // لأن تمرير statusBadge:null في copyWith يُبقي الشارة القديمة
      // ("🧠 يفكّر...") معلقة على الرسالة المكتملة للأبد، فيعرضها شريط
      // التفكير الثابت بدل "اكتمل التفكير"
      final currentMsgs = List<ChatMessage>.from(state.messages);
      final finalizedIdx = currentMsgs.indexWhere(
        (m) => m.id == assistantMsgId,
      );
      if (finalizedIdx != -1) {
        final old = currentMsgs[finalizedIdx];
        currentMsgs[finalizedIdx] = ChatMessage(
          id: old.id,
          role: old.role,
          content: currentAssistantContent,
          timestamp: old.timestamp,
          toolCalls: toolCalls.isNotEmpty
              ? toolCalls
              : (old.toolCalls?.isNotEmpty == true ? old.toolCalls : null),
          thinkingContent: currentThinkingContent.isNotEmpty
              ? currentThinkingContent
              : old.thinkingContent,
          isStreaming: false,
        );
        state = state.copyWith(messages: currentMsgs);
      }

      // حفظ رسالة المساعد
      final assistantMsg = state.messages.firstWhere(
        (m) => m.id == assistantMsgId,
        orElse: () => ChatMessage(
          id: assistantMsgId,
          role: MessageRole.assistant,
          content: currentAssistantContent,
          timestamp: DateTime.now(),
          thinkingContent: currentThinkingContent.isNotEmpty
              ? currentThinkingContent
              : null,
        ),
      );
      await _persistMessage(assistantMsg);

      // خطأ مزوّد صريح (AgentErrorEvent): لا تُنفَّذ أدوات ردٍّ فاشل ولا
      // تُستأنف الحلقة — الرسالة خُتمت بالتنبيه أعلاه وتوقفت الحالة.
      if (providerErrorSeen) {
        state = state.copyWith(isStreaming: false, clearStatus: true);
        return;
      }

      // If the model called any tools, execute them and continue the agent loop
      if (toolCalls.isNotEmpty) {
        state = state.copyWith(activeStatus: 'جارٍ استكمال تنفيذ الأداة...');

        final newMessages = List<ChatMessage>.from(state.messages);
        final List<ToolCallInfo> updatedToolCalls = [];

        for (final toolCall in toolCalls) {
          if (_isAborted) return;
          // ── اعتراض start_autonomous_task ─────────────────────────────
          if (toolCall.toolName == 'start_autonomous_task') {
            final goal =
                toolCall.arguments['goal'] as String? ??
                currentAssistantContent;
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
            final taskId = toolCall.arguments['taskId'] as String? ?? '';
            final answer = toolCall.arguments['answer'] as String? ?? '';
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
          final isSensitive = BrowserSecurityInterceptor.isAwaitingConfirmation;
          if (isSensitive) {
            final pendingCall = toolCall.copyWith(
              status: ToolCallStatus.awaitingConfirmation,
              summary: 'بانتظار تأكيدك لمتابعة هذا الإجراء الحساس...',
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
            _ref
                ?.read(tasksProvider.notifier)
                .setBrowserPanelVisible(
                  true,
                  lastAction: '${toolCall.toolName}: $paramPreview',
                );
          }

          String resultJson;
          ToolCallStatus execStatus = ToolCallStatus.success;
          String? errorMsg;

          // تحديث حالة الواجهة قبل بدء تنفيذ الأداة حتى يعرف المستخدم ماذا يحدث
          final friendlyExecName =
              ToolPresentationFormatter.getFriendlyToolName(
                toolCall.toolName,
                toolCall.arguments,
              );
          state = state.copyWith(activeStatus: '⚙️ يُنفّذ — $friendlyExecName');

          try {
            // إصلاح 06: مهلة ديناميكية لكل أداة (timeoutSeconds في تعريفها)
            // بدل 60 ثانية ثابتة للجميع — وعند انتهائها نلغي التنفيذ فعلياً
            // (تُقتل العملية الداخلية للأدوات القابلة للإلغاء) لا الاكتفاء
            // بتجاهل النتيجة.
            final toolTimeout = ToolRegistry.timeoutFor(toolCall.toolName);
            resultJson =
                await ToolRegistry.executeTool(
                  toolCall.toolName,
                  toolCall.arguments,
                ).timeout(
                  toolTimeout,
                  onTimeout: () {
                    ToolRegistry.cancelToolExecution(
                      toolCall.toolName,
                      'انتهت مهلة الأداة',
                    );
                    return jsonEncode({
                      'error':
                          'انتهت مهلة الأداة (${toolTimeout.inSeconds} ثانية) — تجمّد محتمل أو تأخر في الشبكة.',
                      'timed_out': true,
                      'tool': toolCall.toolName,
                    });
                  },
                );
            if (resultJson.contains('"timed_out":true')) {
              execStatus = ToolCallStatus.error;
              errorMsg =
                  'انتهت مهلة الأداة (${toolTimeout.inSeconds}ث) — تجمّد أو تأخر في الشبكة';
            } else if (resultJson.contains('"error"') ||
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
              arguments: toolCall.arguments,
              errorMessage: errorMsg,
            ),
            errorMessage: errorMsg,
          );

          // Replace or add the finished tool call
          final existingIdx = updatedToolCalls.indexWhere(
            (c) => c.callId == toolCall.callId,
          );
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
            // إصلاح 01: اسم الأداة صراحةً بدل استخراجه لاحقاً من
            // toolCallId عبر split('_').last فيتقطّع الأسماء المركّبة.
            toolName: toolCall.toolName,
          );
          newMessages.add(toolResultMsg);
          await _persistMessage(toolResultMsg);
        }

        if (_isAborted) return;
        state = state.copyWith(messages: newMessages);

        // ── Fix 5: Fallback suggestion if complex request completed without autonomous task ────
        // Check if the original user request was complex but no autonomous task was started
        final userMessages = conversationHistory.where(
          (m) => m.role == MessageRole.user,
        );
        if (userMessages.isNotEmpty) {
          final lastUserText = userMessages.last.content;
          if (TaskComplexityRouter.shouldRouteToAutonomousTask(lastUserText)) {
            // Check if start_autonomous_task was called in this turn
            final autonomousCalled = updatedToolCalls.any(
              (tc) => tc.toolName == 'start_autonomous_task',
            );
            if (!autonomousCalled) {
              debugPrint(
                '[ChatController] ⚠️ Complex request completed without autonomous task — injecting fallback suggestion',
              );
              // Inject a system message to guide the model to use autonomous task next time
              final fallbackMsg = ChatMessage(
                id: _uuid.v4(),
                role: MessageRole.system,
                content:
                    '[تنبيه نظام: طلب المستخدم كان معقداً (${TaskComplexityRouter.getComplexityReason(lastUserText)}) '
                    'لكن لم يتم استدعاء start_autonomous_task. '
                    'في المرات القادمة، يرجى استدعاء start_autonomous_task فوراً للمهام المعقدة بدلاً من معالجتها مباشرة.]',
                timestamp: DateTime.now(),
              );
              newMessages.add(fallbackMsg);
              await _persistMessage(fallbackMsg);
            }
          }
        }

        // Feed tool results back to the model to generate the final response
        await _runAgentLoop(newMessages);
      } else {
        // Final Answer Enforcement: فحص هل انتهى النموذج بصمت بعد استدعاء أدوات
        if (currentAssistantContent.trim().isEmpty) {
          final hadPreviousTools = conversationHistory.any(
            (m) => m.role == MessageRole.tool,
          );
          if (hadPreviousTools) {
            if (recoveryAttempt == 0) {
              debugPrint(
                '[SilentEnd] provider=${state.selectedProviderId} model=${state.selectedModel} attempt=1',
              );
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

              final retryHistory = List<ChatMessage>.from(conversationHistory)
                ..add(reminderMsg);
              await _runAgentLoop(
                retryHistory,
                recoveryAttempt: 1,
                promiseRecoveryAttempt: promiseRecoveryAttempt,
              );
              return;
            } else {
              debugPrint(
                '[SilentEnd] provider=${state.selectedProviderId} model=${state.selectedModel} attempt=2',
              );
              final executedTools = conversationHistory
                  .where((m) => m.toolCalls != null)
                  .expand((m) => m.toolCalls!)
                  .toList();

              final toolSummaries = executedTools
                  .map((t) => '- ${t.summary ?? t.toolName}')
                  .join('\n');
              final fallbackAnswer =
                  'خوارزمي نفّذ العمليات التالية بنجاح:\n$toolSummaries\n\n(تم إنجاز المطلوب. أخبرني إن كنت بحاجة لأي استفسار إضافي).';

              currentAssistantContent = fallbackAnswer;
              _updateAssistantMessage(
                assistantMsgId,
                content: currentAssistantContent,
                thinkingContent: currentThinkingContent.isNotEmpty
                    ? currentThinkingContent
                    : null,
                isStreaming: false,
                statusBadge: null,
              );
              final fallbackMsg = ChatMessage(
                id: assistantMsgId,
                role: MessageRole.assistant,
                content: currentAssistantContent,
                timestamp: DateTime.now(),
                thinkingContent: currentThinkingContent.isNotEmpty
                    ? currentThinkingContent
                    : null,
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
        content: '$currentAssistantContent\n\n*(حدث خطأ غير متوقع: $e)*',
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

  /// يبدأ TaskExecutionEngine ويعرض خطة العمل أولاً لاعتماد المستخدم،
  /// ثم ينفّذ المهام الفرعية مع تحديث حي لبطاقة الخطة.
  Future<void> _handleStartAutonomousTask({
    required ToolCallInfo toolCall,
    required String goal,
    required String assistantMsgId,
    required String currentAssistantContent,
    required List<ToolCallInfo> updatedToolCalls,
    required List<ChatMessage> newMessages,
  }) async {
    // إظهار حالة "جارٍ التخطيط" مؤقتاً
    final planningCall = toolCall.copyWith(
      status: ToolCallStatus.running,
      result: jsonEncode({'status': 'planning', 'goal': goal}),
      summary: '🧠 يُحلّل المهمة ويضع الخطة...',
    );
    updatedToolCalls.add(planningCall);
    _updateAssistantMessage(
      assistantMsgId,
      content: currentAssistantContent,
      toolCalls: List.from(updatedToolCalls),
      isStreaming: true,
      statusBadge: '🧠 يُحلّل المهمة ويضع الخطة...',
    );
    state = state.copyWith(activeStatus: '🧠 يُحلّل المهمة ويضع الخطة...');

    // معرف ثابت لبطاقة الخطة — يسمح بتحديثها حياً أثناء التنفيذ
    final planCardCallId = _uuid.v4();

    // تشغيل المحرك مع requirePlanApproval=true
    final task = await TaskExecutionEngine.instance.startTask(
      goal: goal,
      requirePlanApproval: true,
      callbacks: TaskExecutionCallbacks(
        // ── 1. عرض الخطة وانتظار الاعتماد ──────────────────────────────────
        onPlanAwaitingApproval: (plan) {
          // أزل بطاقة "جارٍ التخطيط" واستبدلها ببطاقة الخطة الحقيقية
          updatedToolCalls.removeWhere((c) => c.callId == planningCall.callId);

          final planCall = ToolCallInfo(
            callId: planCardCallId,
            toolName: 'task_plan',
            arguments: {'plan': plan.toJson()},
            status: ToolCallStatus.awaitingConfirmation,
            summary: '📋 خطة العمل — ${plan.taskList.length} خطوات فرعية',
            result: jsonEncode(plan.toJson()),
          );
          updatedToolCalls.add(planCall);

          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent.isEmpty
                ? 'وضعتُ خطة عمل من **${plan.taskList.length} خطوات**. راجعها وأعتمدها للبدء في التنفيذ.'
                : currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: false,
            statusBadge: null,
          );
          // رفع عدّاد تنبيه الاعتماد — تراقبه الشاشة للتمرير التلقائي نحو
          // بطاقة الخطة (تحديثها يتم في فقاعة قديمة ولا يغيّر عدد الرسائل)
          state = state.copyWith(
            isStreaming: false,
            clearStatus: true,
            planApprovalNonce: state.planApprovalNonce + 1,
          );

          final msg = state.messages.firstWhere(
            (m) => m.id == assistantMsgId,
            orElse: () => ChatMessage(
              id: assistantMsgId,
              role: MessageRole.assistant,
              content: 'وضعتُ خطة عمل. راجعها وأعتمدها للبدء.',
              timestamp: DateTime.now(),
            ),
          );
          _persistMessage(msg);
        },

        // ── 2. خطوة بدأت — تحديث الكرت حياً ──────────────────────────────
        onSubTaskStarted: (subTask) {
          _updatePlanCard(
            updatedToolCalls: updatedToolCalls,
            planCardCallId: planCardCallId,
            updatedSubTask: subTask,
            cardStatus: ToolCallStatus.running,
          );
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent.isEmpty
                ? 'تنفيذ الخطوة ${subTask.index + 1}: ${subTask.description}'
                : currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
            statusBadge:
                '🔄 الخطوة ${subTask.index + 1}/${_getPlanSize(updatedToolCalls, planCardCallId)}: ${subTask.description}',
          );
          state = state.copyWith(activeStatus: '🔄 ${subTask.description}');
        },

        // ── 3. خطوة اكتملت ─────────────────────────────────────────────────
        onSubTaskCompleted: (subTask) {
          _updatePlanCard(
            updatedToolCalls: updatedToolCalls,
            planCardCallId: planCardCallId,
            updatedSubTask: subTask,
            cardStatus: ToolCallStatus.running,
          );
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent.isEmpty
                ? 'يُنفّذ الخطة...'
                : currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
          );
        },

        // ── 4. خطوة فشلت ───────────────────────────────────────────────────
        onSubTaskFailed: (subTask, error) {
          _updatePlanCard(
            updatedToolCalls: updatedToolCalls,
            planCardCallId: planCardCallId,
            updatedSubTask: subTask,
            cardStatus: ToolCallStatus.error,
          );
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent.isEmpty
                ? '⚠️ فشلت الخطوة ${subTask.index + 1}: $error'
                : currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: false,
            statusBadge: null,
          );
          state = state.copyWith(isStreaming: false, clearStatus: true);
        },

        // ── 5. أداة فردية داخل المهمة الفرعية ────────────────────────────
        onToolCall: (tc) {
          updatedToolCalls.add(
            tc.copyWith(
              status: ToolCallStatus.running,
              summary: '🔄 ${tc.toolName}...',
            ),
          );
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
            statusBadge: '🛠️ ${tc.toolName}',
          );
        },
        onToolResult: (tc) {
          final idx = updatedToolCalls.indexWhere((c) => c.callId == tc.callId);
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
        onTextChunk: (_) {},
        onProgress: (progress) {
          state = state.copyWith(activeStatus: '📊 $progress');
        },

        // ── 6. سؤال للمستخدم أثناء التنفيذ ───────────────────────────────
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

        // ── 7. اكتملت كل الخطوات ──────────────────────────────────────────
        onComplete: (summary) {
          _activeAutonomousTaskId = null;
          // تحديث بطاقة الخطة إلى ✅ مكتملة
          final planIdx = updatedToolCalls.indexWhere(
            (c) => c.callId == planCardCallId,
          );
          if (planIdx != -1) {
            updatedToolCalls[planIdx] = updatedToolCalls[planIdx].copyWith(
              status: ToolCallStatus.success,
            );
          }
          final completeCall = ToolCallInfo(
            callId: _uuid.v4(),
            toolName: 'complete_task',
            arguments: {'summary': summary},
            status: ToolCallStatus.success,
            summary: '✅ اكتملت جميع خطوات الخطة',
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
        onTaskUpdated: (_) => loadConversations(),
      ),
    );
    _activeAutonomousTaskId = task.id;
    debugPrint(
      '[ChatController] Plan-and-Execute task ${task.id} created — awaiting approval.',
    );
  }

  /// يُحدّث بطاقة الخطة (task_plan ToolCallInfo) بحالة مهمة فرعية جديدة
  void _updatePlanCard({
    required List<ToolCallInfo> updatedToolCalls,
    required String planCardCallId,
    required SubTask updatedSubTask,
    required ToolCallStatus cardStatus,
  }) {
    final planIdx = updatedToolCalls.indexWhere(
      (c) => c.callId == planCardCallId,
    );
    if (planIdx == -1) return;

    final old = updatedToolCalls[planIdx];
    try {
      final raw = old.arguments['plan'];
      if (raw is Map<String, dynamic>) {
        final currentPlan = TaskPlan.fromJson(raw);
        final updatedPlan = currentPlan.updateSubTask(
          updatedSubTask.index,
          updatedSubTask,
        );
        updatedToolCalls[planIdx] = old.copyWith(
          arguments: {'plan': updatedPlan.toJson()},
          result: jsonEncode(updatedPlan.toJson()),
          status: cardStatus,
        );
      }
    } catch (_) {}
  }

  /// يُرجع عدد الخطوات الكلي للخطة من الـ ToolCallInfo
  int _getPlanSize(List<ToolCallInfo> calls, String planCardCallId) {
    try {
      final planCall = calls.firstWhere((c) => c.callId == planCardCallId);
      final raw = planCall.arguments['plan'];
      if (raw is Map<String, dynamic>) {
        final plan = TaskPlan.fromJson(raw);
        return plan.taskList.length;
      }
    } catch (_) {}
    return 0;
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
      result: jsonEncode({
        'status': 'task_resumed',
        'taskId': taskId,
        'answer': answer,
      }),
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
        // ── تحديث بطاقة الخطة حياً أثناء الاستئناف (كانت غائبة) ──────────
        onSubTaskStarted: (subTask) {
          final planCallId = _findPlanCardCallId(taskId);
          if (planCallId != null) {
            _updatePlanCardInState(
              planCallId,
              subTask,
              ToolCallStatus.running,
            );
            state = state.copyWith(
              activeStatus:
                  '🔄 الخطوة ${subTask.index + 1}: ${subTask.description}',
            );
          }
        },
        onSubTaskCompleted: (subTask) {
          final planCallId = _findPlanCardCallId(taskId);
          if (planCallId != null) {
            _updatePlanCardInState(
              planCallId,
              subTask,
              ToolCallStatus.running,
            );
          }
        },
        onSubTaskFailed: (subTask, error) {
          final planCallId = _findPlanCardCallId(taskId);
          if (planCallId != null) {
            _updatePlanCardInState(planCallId, subTask, ToolCallStatus.error);
          }
        },
        onToolCall: (tc) {
          updatedToolCalls.add(
            tc.copyWith(
              status: ToolCallStatus.running,
              summary: '🔄 ينفّذ: ${tc.toolName}...',
            ),
          );
          _updateAssistantMessage(
            assistantMsgId,
            content: currentAssistantContent,
            toolCalls: List.from(updatedToolCalls),
            isStreaming: true,
            statusBadge: '🛠️ ${tc.toolName}',
          );
        },
        onToolResult: (tc) {
          final idx = updatedToolCalls.indexWhere((c) => c.callId == tc.callId);
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

  /// يعتمد خطة العمل المعروضة ويبدأ تنفيذها بتصميم Timeline نظيف:
  /// 1. يبدّل النمط النشط فعلياً إلى «كود» + رسالة اعتماد تلقائية محفوظة.
  /// 2. بطاقة الخطة تبقى مجمّدة في فقاعتها (تحديث الحالات فقط).
  /// 3. فقاعة تنفيذ جديدة مستقلة تستقبل بطاقات الأدوات والأسئلة والملخص —
  ///    سطر جديد لكل طور بدل حشو كل شيء في فقاعة واحدة (شات مرتب).
  /// 4. عند الاكتمال: ملخص نهائي + بطاقة ✅ + العودة لوضع «مدير».
  Future<void> approveTaskPlan(String taskId, String planCardCallId) async {
    // ── 1. تبديل الوضع إلى «كود» + رسالة اعتماد تلقائية ──────────────────
    setActiveCodingMode(CodingMode.code);
    setCodingAgentMode(true);

    final approvalMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: 'موافق على الخطة — جارٍ التنفيذ بوضع الكود',
      timestamp: DateTime.now(),
    );
    final messagesWithApproval = List<ChatMessage>.from(state.messages)
      ..add(approvalMsg);
    state = state.copyWith(
      messages: messagesWithApproval,
      activeStatus: '🚀 جاري تنفيذ الخطة المعتمدة...',
    );
    await _ensureActiveConversation(approvalMsg.content);
    await _persistMessage(approvalMsg);

    // ── 2. تحديث حالة بطاقة الخطة في الـ State إلى running ───────────────
    final messages = state.messages.map((m) {
      if (m.toolCalls != null) {
        final updatedCalls = m.toolCalls!.map((tc) {
          if (tc.callId == planCardCallId || tc.toolName == 'task_plan') {
            return tc.copyWith(status: ToolCallStatus.running);
          }
          return tc;
        }).toList();
        return m.copyWith(toolCalls: updatedCalls);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: messages);

    // ── 3. فقاعة تنفيذ جديدة مستقلة — سطر جديد للتنفيذ (Timeline نظيف) ────
    // بطاقة الخطة تبقى مجمّدة في فقاعتها (تحديث الحالات فقط)، وكل نشاط
    // التنفيذ (أدوات/أسئلة/ملخص) يتراكم في هذه الفقاعة الجديدة بدل حشو
    // كل شيء في فقاعة واحدة مزدحمة.
    final execMsgId = _uuid.v4();
    final execMsg = ChatMessage(
      id: execMsgId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      toolCalls: const [],
      isStreaming: true,
      statusBadge: '🚀 بدء تنفيذ الخطة المعتمدة...',
    );
    messages.add(execMsg);

    final execToolCalls = <ToolCallInfo>[];
    _activeAutonomousTaskId = taskId;

    // ── حالة البث أثناء تنفيذ الخطة ────────────────────────────────────────
    // بدونها: زر الإيقاف لا يظهر، وحقل الإدخال يبقى مفتوحاً، ولا يعرف
    // المستخدم هل بدأ التنفيذ فعلاً. تُختم false عند onAskUser / onComplete
    // / إيقاف المستخدم، ويعرض أسفل المحادثة مؤشر التقدم الحي تلقائياً.
    state = state.copyWith(messages: messages, isStreaming: true);

    // ── 4. إطلاق التنفيذ عبر محرك المهام مع callbacks كاملة ──────────────
    await TaskExecutionEngine.instance.approveAndExecutePlan(
      taskId,
      callbacks: TaskExecutionCallbacks(
        onSubTaskStarted: (subTask) {
          _updatePlanCardInState(
            planCardCallId,
            subTask,
            ToolCallStatus.running,
          );
          _updateAssistantMessage(
            execMsgId,
            content: '',
            toolCalls: List.from(execToolCalls),
            isStreaming: true,
            statusBadge:
                '🔄 الخطوة ${subTask.index + 1}: ${subTask.description}',
          );
          state = state.copyWith(
            activeStatus:
                '🔄 الخطوة ${subTask.index + 1}: ${subTask.description}',
          );
        },
        onSubTaskCompleted: (subTask) {
          _updatePlanCardInState(
            planCardCallId,
            subTask,
            ToolCallStatus.running,
          );
        },
        onSubTaskFailed: (subTask, error) {
          _updatePlanCardInState(planCardCallId, subTask, ToolCallStatus.error);
          _updateAssistantMessage(
            execMsgId,
            content: '⚠️ فشلت الخطوة ${subTask.index + 1}: $error',
            toolCalls: List.from(execToolCalls),
            isStreaming: true,
          );
        },
        onToolCall: (tc) {
          execToolCalls.add(
            tc.copyWith(
              status: ToolCallStatus.running,
              summary: '🔄 ${tc.toolName}...',
            ),
          );
          _updateAssistantMessage(
            execMsgId,
            content: '',
            toolCalls: List.from(execToolCalls),
            isStreaming: true,
            statusBadge: '🛠️ ${tc.toolName}',
          );
        },
        onToolResult: (tc) {
          final idx = execToolCalls.indexWhere((c) => c.callId == tc.callId);
          if (idx != -1) {
            execToolCalls[idx] = tc;
          } else {
            execToolCalls.add(tc);
          }
          _updateAssistantMessage(
            execMsgId,
            content: '',
            toolCalls: List.from(execToolCalls),
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
          execToolCalls.add(askCall);
          _updateAssistantMessage(
            execMsgId,
            content: '❓ **$question**',
            toolCalls: List.from(execToolCalls),
            isStreaming: false,
            statusBadge: null,
          );
          final msg = state.messages.firstWhere(
            (m) => m.id == execMsgId,
            orElse: () => ChatMessage(
              id: execMsgId,
              role: MessageRole.assistant,
              content: '❓ **$question**',
              timestamp: DateTime.now(),
            ),
          );
          _persistMessage(msg);
          state = state.copyWith(isStreaming: false, clearStatus: true);
        },
        onComplete: (summary) {
          _activeAutonomousTaskId = null;

          // بطاقة الخطة → ✅ في نسخة الرسائل المحدثة
          final msgs = state.messages.map((m) {
            if (m.toolCalls != null) {
              final updatedCalls = m.toolCalls!.map((tc) {
                if (tc.callId == planCardCallId || tc.toolName == 'task_plan') {
                  return tc.copyWith(status: ToolCallStatus.success);
                }
                return tc;
              }).toList();
              return m.copyWith(toolCalls: updatedCalls);
            }
            return m;
          }).toList();

          final completeCall = ToolCallInfo(
            callId: _uuid.v4(),
            toolName: 'complete_task',
            arguments: {'summary': summary},
            status: ToolCallStatus.success,
            summary: '✅ اكتملت جميع خطوات الخطة',
            result: jsonEncode({'summary': summary}),
          );

          // فقاعة التنفيذ تُختم بالملخص النهائي (بناء جديد = لا شارة معلقة)
          final finalMsg = ChatMessage(
            id: execMsgId,
            role: MessageRole.assistant,
            content: '✅ **اكتملت الخطة**\n\n$summary',
            timestamp: DateTime.now(),
            toolCalls: [...execToolCalls, completeCall],
            isStreaming: false,
          );
          final execIdx = msgs.indexWhere((m) => m.id == execMsgId);
          if (execIdx != -1) {
            msgs[execIdx] = finalMsg;
          } else {
            msgs.add(finalMsg);
          }
          state = state.copyWith(
            messages: msgs,
            isStreaming: false,
            clearStatus: true,
          );

          // العودة لوضع «مدير» بعد اكتمال الخطة — منسجم مع برومبت المدير
          setActiveCodingMode(CodingMode.manager);
          _persistMessage(finalMsg);
        },
        onTaskUpdated: (_) => loadConversations(),
      ),
    );
  }

  /// يرفض خطة العمل المعروضة ويلغي المهمة
  Future<void> rejectTaskPlan(String taskId, String planCardCallId) async {
    final messages = state.messages.map((m) {
      if (m.toolCalls != null) {
        final updatedCalls = m.toolCalls!.map((tc) {
          if (tc.callId == planCardCallId || tc.toolName == 'task_plan') {
            return tc.copyWith(status: ToolCallStatus.error);
          }
          return tc;
        }).toList();
        return m.copyWith(toolCalls: updatedCalls);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: messages, activeStatus: null);
    await TaskExecutionEngine.instance.cancelTask(taskId);
  }

  /// يُستدعى عند إلغاء مهمة من خارج زر الإيقاف الرئيسي (لوحة المهام أو
  /// شريط المهام الحي) — يضمن عدم بقاء حالة البث متجمدة على مهمة توقفت.
  void handleExternalTaskCancel(String taskId) {
    if (_activeAutonomousTaskId != taskId) return;
    _activeAutonomousTaskId = null;
    state = state.copyWith(isStreaming: false, clearStatus: true);
  }

  /// يجد معرف بطاقة الخطة في رسائل المحادثة الحالية انطلاقاً من معرف المهمة
  String? _findPlanCardCallId(String taskId) {
    for (final m in state.messages) {
      final calls = m.toolCalls;
      if (calls == null) continue;
      for (final tc in calls) {
        if (tc.toolName != 'task_plan') continue;
        final raw = tc.arguments['plan'];
        if (raw is Map<String, dynamic> && raw['taskId'] == taskId) {
          return tc.callId;
        }
        if (tc.result != null && tc.result!.isNotEmpty) {
          try {
            final decoded = jsonDecode(tc.result!);
            if (decoded is Map<String, dynamic> &&
                decoded['taskId'] == taskId) {
              return tc.callId;
            }
          } catch (_) {}
        }
      }
    }
    return null;
  }

  void _updatePlanCardInState(
    String planCardCallId,
    SubTask updatedSubTask,
    ToolCallStatus cardStatus,
  ) {
    final updated = state.messages.map((m) {
      if (m.toolCalls != null) {
        final calls = m.toolCalls!.map((tc) {
          if (tc.callId == planCardCallId || tc.toolName == 'task_plan') {
            try {
              final raw = tc.arguments['plan'];
              if (raw is Map<String, dynamic>) {
                final currentPlan = TaskPlan.fromJson(raw);
                final updatedPlan = currentPlan.updateSubTask(
                  updatedSubTask.index,
                  updatedSubTask,
                );
                return tc.copyWith(
                  arguments: {'plan': updatedPlan.toJson()},
                  result: jsonEncode(updatedPlan.toJson()),
                  status: cardStatus,
                );
              }
            } catch (_) {}
          }
          return tc;
        }).toList();
        return m.copyWith(toolCalls: calls);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }
}
