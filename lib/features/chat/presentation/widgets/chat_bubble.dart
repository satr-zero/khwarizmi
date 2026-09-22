import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/layout_controller.dart';
import 'package:khwarizmi/features/chat/presentation/models/chat_turn.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/tool_call_card.dart';

/// Unified chat bubble widget rendering both individual messages and unified turns.
class ChatBubble extends ConsumerWidget {
  final ChatTurn turn;
  final void Function(ChatMessage message)? onEdit;

  ChatBubble({
    super.key,
    required ChatMessage message,
    this.onEdit,
  }) : turn = message.role == MessageRole.user
            ? UserTurn(message)
            : AssistantTurn(
                id: message.id,
                textSegments: message.content.isNotEmpty ? [message.content] : [],
                toolCalls: message.toolCalls ?? [],
                isStreaming: message.isStreaming,
                activeStatus: message.statusBadge,
                timestamp: message.timestamp,
                thinkingContent: message.thinkingContent,
              );

  const ChatBubble.fromTurn({
    super.key,
    required this.turn,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSimplified = ref.watch(layoutProvider.select((s) => s.isSimplifiedView));
    return switch (turn) {
      UserTurn(:final message) => _buildUserBubble(context, message),
      AssistantTurn(
        :final textSegments,
        :final toolCalls,
        :final isStreaming,
        :final activeStatus,
        :final thinkingContent,
      ) =>
        _CollapsibleAssistantBubble(
          textSegments: textSegments,
          toolCalls: toolCalls,
          isStreaming: isStreaming,
          activeStatus: activeStatus,
          thinkingContent: thinkingContent,
          onEdit: onEdit,
          isSimplifiedView: isSimplified,
        ),
    };
  }

  // ── User Bubble ────────────────────────────────────────────────────────────
  Widget _buildUserBubble(BuildContext context, ChatMessage message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final textColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignTokens.space8,
        horizontal: DesignTokens.space16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.space16,
                    vertical: DesignTokens.space12,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                    border: Border.all(color: borderColor, width: DesignTokens.hairline),
                  ),
                  child: SelectableText(
                    message.content,
                    style: TextStyle(
                      color: textColor,
                      fontSize: DesignTokens.fontSizeBase,
                      height: 1.5,
                      fontFamily: DesignTokens.fontFamilySans,
                      fontFamilyFallback: DesignTokens.sansFallbacks,
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.space4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null) ...[
                      IconButton(
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 13,
                          color: secondaryTextColor,
                        ),
                        tooltip: 'تعديل الرسالة',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onEdit!(message),
                      ),
                    ],
                    IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: secondaryTextColor,
                      ),
                      tooltip: 'نسخ الرسالة',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: message.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ الرسالة إلى الحافظة'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.space12),
          _buildUserAvatar(isDark),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(bool isDark) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight,
        border: Border.all(
          color: isDark ? DesignTokens.borderDark : DesignTokens.borderLight,
          width: DesignTokens.hairline,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: 16,
          color: isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight,
        ),
      ),
    );
  }
}

// ── Collapsible Assistant Bubble ──────────────────────────────────────────────
// ── Assistant Bubble (Borderless, Minimal, Right-Aligned, Collapsible Thinking) ──────
class _CollapsibleAssistantBubble extends StatelessWidget {
  final List<String> textSegments;
  final List<ToolCallInfo> toolCalls;
  final bool isStreaming;
  final String? activeStatus;
  final String? thinkingContent;
  final void Function(ChatMessage message)? onEdit;
  /// الوضع المبسط: يخفي التفكير وبطاقات الأدوات
  final bool isSimplifiedView;

  const _CollapsibleAssistantBubble({
    required this.textSegments,
    required this.toolCalls,
    required this.isStreaming,
    this.activeStatus,
    this.thinkingContent,
    this.onEdit,
    this.isSimplifiedView = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    final hasContent = textSegments.isNotEmpty;
    final hasTools = toolCalls.isNotEmpty;
    final allTextContent = textSegments.join('\n\n');

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: DesignTokens.space8,
        horizontal: DesignTokens.space16,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: DesignTokens.chatMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── الوضع المبسط: نقطة صغيرة تدل على التفكير الجاري، بلا تفاصيل ──
              if (isSimplifiedView) ...[
                // أثناء البث: مؤشر بسيط (نقطة + حالة نصية فقط)
                if (isStreaming && (activeStatus != null || thinkingContent != null))
                  Padding(
                    padding: const EdgeInsets.only(bottom: DesignTokens.space8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(secondary),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.space8),
                        Text(
                          activeStatus ?? 'يعالج...',
                          style: TextStyle(
                            color: secondary,
                            fontSize: DesignTokens.fontSizeXs,
                            fontFamily: DesignTokens.fontFamilySans,
                            fontFamilyFallback: DesignTokens.sansFallbacks,
                          ),
                        ),
                      ],
                    ),
                  ),
                // النص النهائي فقط (بلا أدوات، بلا تفكير)
                if (hasContent)
                  _buildMarkdownBody(textSegments.first, isDark, primary),
                // نصوص لاحقة
                if (textSegments.length > 1) ...[
                  const SizedBox(height: DesignTokens.space8),
                  for (int i = 1; i < textSegments.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DesignTokens.space8),
                      child: _buildMarkdownBody(textSegments[i], isDark, primary),
                    ),
                ],
              ] else ...[
              // ── الوضع التفصيلي: كل شيء ظاهر (الأصلي) ──

              // قسم التفكير مع سهم قابل للطي/التوسيع
              if (isStreaming ||
                  (activeStatus != null && activeStatus!.isNotEmpty) ||
                  (thinkingContent != null && thinkingContent!.trim().isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(bottom: DesignTokens.space8),
                  child: _ThinkingSection(
                    activeStatus: activeStatus,
                    thinkingContent: thinkingContent,
                    isStreaming: isStreaming,
                    isDark: isDark,
                  ),
                ),

              // النص الأول (يعرض كاملاً بدون حجب أو زر عرض المزيد)
              if (hasContent)
                _buildMarkdownBody(textSegments.first, isDark, primary),

              // بطاقات الأدوات مع خط زمني وتعداد خطوات
              if (hasTools) ...[
                const SizedBox(height: DesignTokens.space8),
                for (int i = 0; i < toolCalls.length; i++) ...[
                  ToolCallCard(
                    toolCall: toolCalls[i],
                    stepIndex: i + 1,
                    totalSteps: toolCalls.length,
                  ),
                  if (i < toolCalls.length - 1)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 14),
                      child: SizedBox(
                        height: 8,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: isDark ? DesignTokens.borderDark : DesignTokens.borderLight,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: DesignTokens.space4),
              ],

              // نصوص لاحقة
              if (textSegments.length > 1) ...[
                const SizedBox(height: DesignTokens.space8),
                for (int i = 1; i < textSegments.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DesignTokens.space8),
                    child: _buildMarkdownBody(textSegments[i], isDark, primary),
                  ),
              ],
              ], // end of detailed view

              // زر نسخ الرد (مشترك بين الوضعين)
              if (!isStreaming && allTextContent.isNotEmpty) ...[
                const SizedBox(height: DesignTokens.space4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    icon: Icon(Icons.copy_rounded, size: 13, color: secondary),
                    tooltip: 'نسخ الرد',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: allTextContent));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ الرد إلى الحافظة'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Markdown Body ──────────────────────────────────────────────────────────
  Widget _buildMarkdownBody(String content, bool isDark, Color textColor) {
    final codeBg = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceInputLight;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: textColor,
          fontSize: DesignTokens.fontSizeBase,
          height: 1.55,
          fontFamily: DesignTokens.fontFamilySans,
          fontFamilyFallback: DesignTokens.sansFallbacks,
        ),
        code: TextStyle(
          backgroundColor: codeBg,
          color: textColor,
          fontFamily: DesignTokens.fontFamilyMono,
          fontFamilyFallback: DesignTokens.monoFallbacks,
          fontSize: DesignTokens.fontSizeSm,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(color: borderColor, width: DesignTokens.hairline),
        ),
        blockquoteDecoration: BoxDecoration(
          color: codeBg,
          border: Border(
            right: BorderSide(
              color: isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight,
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}

// ── قسم التفكير القابل للطي مع سهم ───────────────────────────────────────────
class _ThinkingSection extends StatefulWidget {
  final String? activeStatus;
  final String? thinkingContent;
  final bool isStreaming;
  final bool isDark;

  const _ThinkingSection({
    required this.activeStatus,
    this.thinkingContent,
    required this.isStreaming,
    required this.isDark,
  });

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final secondary =
        widget.isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final hasThinkingText =
        widget.thinkingContent != null && widget.thinkingContent!.trim().isNotEmpty;

    final String statusText;
    if (widget.isStreaming) {
      statusText = widget.activeStatus ?? (hasThinkingText ? 'يفكّر بعمق...' : 'يفكّر...');
    } else if (hasThinkingText) {
      statusText = 'عملية التفكير';
    } else {
      statusText = widget.activeStatus ?? 'عملية التفكير';
    }

    final cardBg =
        widget.isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceInputLight;
    final borderColor =
        widget.isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.space4,
              horizontal: DesignTokens.space4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isStreaming)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: DesignTokens.space8),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(secondary),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: DesignTokens.space8),
                    child: Icon(Icons.psychology_outlined, size: 15, color: secondary),
                  ),
                Text(
                  statusText,
                  style: TextStyle(
                    color: secondary,
                    fontSize: DesignTokens.fontSizeSm,
                    fontWeight: FontWeight.w500,
                    fontFamily: DesignTokens.fontFamilySans,
                    fontFamilyFallback: DesignTokens.sansFallbacks,
                  ),
                ),
                const SizedBox(width: DesignTokens.space4),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: DesignTokens.space8,
              top: DesignTokens.space4,
              bottom: DesignTokens.space4,
            ),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              width: double.infinity,
              padding: const EdgeInsets.all(DesignTokens.space12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(
                  color: borderColor,
                  width: DesignTokens.hairline,
                ),
              ),
              child: hasThinkingText
                  ? SingleChildScrollView(
                      child: SelectableText(
                        widget.thinkingContent!.trim(),
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          height: 1.5,
                          color: secondary,
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontFamilyFallback: DesignTokens.monoFallbacks,
                        ),
                      ),
                    )
                  : Text(
                      widget.activeStatus != null && widget.activeStatus != 'يفكّر...'
                          ? 'العملية الحالية: ${widget.activeStatus}'
                          : 'جارٍ تحليل السياق واستدعاء الأدوات وصياغة الرد المنطقي...',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        color: secondary,
                        fontFamily: DesignTokens.fontFamilySans,
                        fontFamilyFallback: DesignTokens.sansFallbacks,
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}
