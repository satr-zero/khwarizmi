import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/domain/entities/conversation.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final String? activeStatus;
  final String selectedProviderId;
  final String selectedModel;
  final String? apiKey;
  final String? systemPrompt;
  final String? errorMessage;

  // ── سجل المحادثات ───────────────────────────────────────────────────────
  /// المحادثة النشطة حالياً (null = محادثة جديدة لم تُحفظ بعد)
  final Conversation? activeConversation;

  /// قائمة جميع المحادثات المحفوظة (مرتبة بالأحدث أولاً)
  final List<Conversation> conversations;

  /// هل يتم تحميل قائمة المحادثات من قاعدة البيانات
  final bool isLoadingHistory;

  /// هل وضع (وكيل برمجي) مفعل حالياً في الشات
  final bool isCodingAgentMode;

  /// هل ميزة التفكير الموسّع مفعّلة يدويًا للمحادثة الحالية
  final bool thinkingEnabled;

  /// هل تم عرض تنبيه عدم دعم التفكير في وضع الكود مرة واحدة
  final bool codingModeThinkingBannerShown;

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.activeStatus,
    this.selectedProviderId = 'gemini',
    this.selectedModel = 'gemini-3.8-flash',
    this.apiKey,
    this.systemPrompt,
    this.errorMessage,
    this.activeConversation,
    this.conversations = const [],
    this.isLoadingHistory = false,
    this.isCodingAgentMode = false,
    this.thinkingEnabled = false,
    this.codingModeThinkingBannerShown = false,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    String? activeStatus,
    String? selectedProviderId,
    String? selectedModel,
    String? apiKey,
    String? systemPrompt,
    String? errorMessage,
    bool clearStatus = false,
    bool clearError = false,
    Conversation? activeConversation,
    bool clearActiveConversation = false,
    List<Conversation>? conversations,
    bool? isLoadingHistory,
    bool? isCodingAgentMode,
    bool? thinkingEnabled,
    bool? codingModeThinkingBannerShown,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      activeStatus: clearStatus ? null : (activeStatus ?? this.activeStatus),
      selectedProviderId: selectedProviderId ?? this.selectedProviderId,
      selectedModel: selectedModel ?? this.selectedModel,
      apiKey: apiKey ?? this.apiKey,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activeConversation: clearActiveConversation
          ? null
          : (activeConversation ?? this.activeConversation),
      conversations: conversations ?? this.conversations,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      isCodingAgentMode: isCodingAgentMode ?? this.isCodingAgentMode,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      codingModeThinkingBannerShown:
          codingModeThinkingBannerShown ?? this.codingModeThinkingBannerShown,
    );
  }
}
