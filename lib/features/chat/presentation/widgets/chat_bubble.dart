import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/layout_controller.dart';
import 'package:khwarizmi/features/chat/presentation/models/chat_turn.dart';
import 'package:khwarizmi/features/chat/presentation/models/file_attachment_info.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_controller.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/file_attachment_card.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/tool_call_card.dart';

/// Unified chat bubble widget rendering both individual messages and unified turns.
class ChatBubble extends ConsumerWidget {
  final ChatTurn turn;
  final void Function(ChatMessage message)? onEdit;

  ChatBubble({super.key, required ChatMessage message, this.onEdit})
    : turn = message.role == MessageRole.user
          ? UserTurn(message)
          : message.role == MessageRole.system
              ? SystemTurn(message)
              : AssistantTurn(
                  id: message.id,
                  steps: [
                    AssistantStep(
                      id: message.id,
                      thinkingContent: message.thinkingContent,
                      content: message.content.isNotEmpty ? message.content : null,
                      toolCalls: message.toolCalls ?? [],
                      files: (message.toolCalls ?? [])
                          .map(FileAttachmentInfo.fromToolCall)
                          .whereType<FileAttachmentInfo>()
                          .toList(),
                      isStreaming: message.isStreaming,
                      activeStatus: message.statusBadge,
                    ),
                  ],
                  isStreaming: message.isStreaming,
                  activeStatus: message.statusBadge,
                  timestamp: message.timestamp,
                );

  const ChatBubble.fromTurn({super.key, required this.turn, this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSimplified = ref.watch(
      layoutProvider.select((s) => s.isSimplifiedView),
    );
    return switch (turn) {
      UserTurn(:final message) => _buildUserBubble(context, message),
      SystemTurn(:final message) => _buildSystemBubble(context, message),
      AssistantTurn(:final steps, :final isStreaming, :final activeStatus) =>
        _CollapsibleAssistantBubble(
          steps: steps,
          isStreaming: isStreaming,
          activeStatus: activeStatus,
          onEdit: onEdit,
          isSimplifiedView: isSimplified,
        ),
    };
  }

  // ── System Bubble ──────────────────────────────────────────────────────────
  Widget _buildSystemBubble(BuildContext context, ChatMessage message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark
        ? DesignTokens.surfaceDark
        : DesignTokens.surfaceLight;
    final borderColor = isDark
        ? DesignTokens.borderDark
        : DesignTokens.borderLight;
    final textColor = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignTokens.space8,
        horizontal: DesignTokens.space16,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space16,
            vertical: DesignTokens.space12,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            border: Border.all(
              color: borderColor,
              width: DesignTokens.hairlineThick,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: textColor,
              ),
              const SizedBox(width: DesignTokens.space12),
              Expanded(
                child: Text(
                  message.content,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSm,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── User Bubble ────────────────────────────────────────────────────────────
  Widget _buildUserBubble(BuildContext context, ChatMessage message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark
        ? DesignTokens.surfaceDark
        : DesignTokens.surfaceLight;
    final borderColor = isDark
        ? DesignTokens.borderDark
        : DesignTokens.borderLight;
    final textColor = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

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
                    border: Border.all(
                      color: borderColor,
                      width: DesignTokens.hairline,
                    ),
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
          color: isDark
              ? DesignTokens.textSecondaryDark
              : DesignTokens.textSecondaryLight,
        ),
      ),
    );
  }
}

// ── Collapsible Assistant Bubble ──────────────────────────────────────────────
// ── Assistant Bubble (Borderless, Minimal, Right-Aligned, Collapsible Thinking) ──────
class _CollapsibleAssistantBubble extends ConsumerWidget {
  final List<AssistantStep> steps;
  final bool isStreaming;
  final String? activeStatus;
  final void Function(ChatMessage message)? onEdit;

  /// الوضع المبسط: يخفي التفكير والبطاقات الثانوية.
  /// ملاحظة (إصلاح 04): البطاقات التفاعلية التوكيدية (Diff، خطط العمل، أسئلة
  /// الخيارات) تبقى ظاهرة دائماً حتى بهذا الوضع لأنها تتطلب قراراً صريحاً من المستخدم.
  final bool isSimplifiedView;

  const _CollapsibleAssistantBubble({
    required this.steps,
    required this.isStreaming,
    this.activeStatus,
    this.onEdit,
    this.isSimplifiedView = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    final allTextContent = steps
        .map((s) => s.content)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join('\n\n');

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: DesignTokens.space8,
        horizontal: DesignTokens.space16,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesignTokens.chatMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── الوضع المبسط: نقطة صغيرة تدل على التفكير الجاري، بلا تفاصيل ──
              if (isSimplifiedView) ...[
                // أثناء البث: مؤشر بسيط (نقطة + حالة نصية فقط)
                if (isStreaming &&
                    (activeStatus != null ||
                        steps.any((s) => s.thinkingContent != null)))
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              secondary,
                            ),
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
                // بطاقات الملفات المسلمة (إن وجدت في الوضع المبسط)
                for (final step in steps)
                  for (final file in step.files)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: DesignTokens.space8,
                      ),
                      child: FileAttachmentCard(file: file),
                    ),
                // بطاقات الأدوات التفاعلية التوكيدية — تظهر دائماً حتى بالوضع
                // المبسط (إصلاح 04): بطاقات الـ Diff وخطط العمل وأسئلة الخيارات
                // تتطلب قراراً صريحاً من المستخدم، فإخفاؤها كان يحجب أزرار
                // الموافقة/الرفض كلياً ويترك القرار ينتظر دون زر للرد عليه.
                for (final step in steps)
                  for (int i = 0; i < step.toolCalls.length; i++)
                    if (_isInteractiveToolCall(step.toolCalls[i]))
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: DesignTokens.space8,
                        ),
                        child: _buildInteractiveToolCard(
                          ref,
                          step.toolCalls[i],
                          i,
                          step.toolCalls.length,
                        ),
                      ),
                // نصوص جميع الخطوات
                for (final step in steps)
                  if (step.content != null && step.content!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: DesignTokens.space8,
                      ),
                      child: _buildMarkdownBody(step.content!, isDark, primary),
                    ),
              ] else ...[
                // ── الوضع التفصيلي: عرض كل مرحلة (تفكير -> ملفات -> نص -> أدوات) بالترتيب الزمني الصحيح ──
                for (int stepIdx = 0; stepIdx < steps.length; stepIdx++) ...[
                  () {
                    final step = steps[stepIdx];
                    final hasThinking =
                        step.thinkingContent != null &&
                        step.thinkingContent!.trim().isNotEmpty;
                    final isLastStep = stepIdx == steps.length - 1;
                    final isStepStreaming =
                        step.isStreaming || (isLastStep && isStreaming);
                    final showThinking =
                        hasThinking ||
                        (isStepStreaming &&
                            ((activeStatus != null &&
                                    activeStatus!.isNotEmpty) ||
                                (step.activeStatus != null &&
                                    step.activeStatus!.isNotEmpty) ||
                                hasThinking));
                    final hasContent =
                        step.content != null && step.content!.trim().isNotEmpty;
                    final hasTools = step.toolCalls.isNotEmpty;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. قسم التفكير الخاص بهذه الخطوة (في موضعها الزمني الطبيعي!)
                        if (showThinking)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: DesignTokens.space8,
                            ),
                            child: _ThinkingSection(
                              activeStatus: isStepStreaming
                                  ? (step.activeStatus ?? activeStatus)
                                  : null,
                              thinkingContent: step.thinkingContent,
                              isStreaming: isStepStreaming,
                              isDark: isDark,
                              stepNumber: steps.length > 1 ? stepIdx + 1 : null,
                            ),
                          ),

                        // 2. بطاقات الملفات المسلمة والمُنشأة (تظهر كبطاقات تفاعلية أنيقة تفتح اللوحة الجانبية)
                        if (step.files.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: DesignTokens.space8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final file in step.files)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: DesignTokens.space4,
                                    ),
                                    child: FileAttachmentCard(file: file),
                                  ),
                              ],
                            ),
                          ),

                        // 3. النص البرمجي / الشرح الخاص بهذه الخطوة
                        if (hasContent)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: hasTools ? DesignTokens.space8 : 0,
                            ),
                            child: _buildMarkdownBody(
                              step.content!,
                              isDark,
                              primary,
                            ),
                          ),

                        // 4. بطاقات الأدوات الخاصة بهذه الخطوة مع خط زمني
                        if (hasTools) ...[
                          for (int i = 0; i < step.toolCalls.length; i++) ...[
                            () {
                              final tc = step.toolCalls[i];
                              return ToolCallCard(
                                toolCall: tc,
                                stepIndex: i + 1,
                                totalSteps: step.toolCalls.length,
                                onConfirm: tc.toolName == 'task_plan'
                                    ? () {
                                        final raw = tc.arguments['plan'];
                                        String? taskId;
                                        if (raw is Map<String, dynamic>) {
                                          taskId = raw['taskId'] as String?;
                                        }
                                        if (taskId != null) {
                                          ref
                                              .read(chatProvider.notifier)
                                              .approveTaskPlan(
                                                taskId,
                                                tc.callId,
                                              );
                                        }
                                      }
                                    : null,
                                onReject: tc.toolName == 'task_plan'
                                    ? () {
                                        final raw = tc.arguments['plan'];
                                        String? taskId;
                                        if (raw is Map<String, dynamic>) {
                                          taskId = raw['taskId'] as String?;
                                        }
                                        if (taskId != null) {
                                          ref
                                              .read(chatProvider.notifier)
                                              .rejectTaskPlan(
                                                taskId,
                                                tc.callId,
                                              );
                                        }
                                      }
                                    : null,
                                onChoiceSelected: (choice) {
                                  ref
                                      .read(chatProvider.notifier)
                                      .sendMessage(choice);
                                },
                              );
                            }(),
                            if (i < step.toolCalls.length - 1)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 14,
                                ),
                                child: SizedBox(
                                  height: 8,
                                  child: VerticalDivider(
                                    width: 1,
                                    thickness: 1,
                                    color: isDark
                                        ? DesignTokens.borderDark
                                        : DesignTokens.borderLight,
                                  ),
                                ),
                              ),
                          ],
                          const SizedBox(height: DesignTokens.space4),
                        ],
                      ],
                    );
                  }(),
                  // فاصل لطيف بين الخطوات المتعددة
                  if (stepIdx < steps.length - 1)
                    const SizedBox(height: DesignTokens.space8),
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
                        const SnackBar(
                          content: Text('تم نسخ الرد إلى الحافظة'),
                          duration: Duration(seconds: 1),
                        ),
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

  // ── Interactive Tool Cards (إصلاح 04) ────────────────────────────────────────

  /// الأدوات التفاعلية التوكيدية التي تبقى ظاهرة دائماً حتى بالوضع المبسط:
  /// بطاقات الـ Diff، خطط العمل، وأسئلة الخيارات — كلها تتطلب قراراً صريحاً
  /// من المستخدم (موافقة/رفض/اختيار)، فإخفاؤها يحجب أزرار القرار كلياً.
  static bool _isInteractiveToolCall(ToolCallInfo tc) {
    switch (tc.toolName) {
      case 'propose_file_change':
      case 'propose_file_patch':
      case 'task_plan':
      case 'ask_user':
        return true;
      default:
        return false;
    }
  }

  /// بناء بطاقة أداة تفاعلية توكيدية بكل توصيلات الأزرار (نفس توصيلات
  /// الوضع التفصيلي) — تُستخدم بالوضع المبسط لتبقى هذه البطاقات ظاهرة.
  Widget _buildInteractiveToolCard(
    WidgetRef ref,
    ToolCallInfo tc,
    int index,
    int total,
  ) {
    final isPlan = tc.toolName == 'task_plan';
    return ToolCallCard(
      toolCall: tc,
      stepIndex: index + 1,
      totalSteps: total,
      onConfirm: isPlan
          ? () {
              final raw = tc.arguments['plan'];
              String? taskId;
              if (raw is Map<String, dynamic>) {
                taskId = raw['taskId'] as String?;
              }
              if (taskId != null) {
                ref
                    .read(chatProvider.notifier)
                    .approveTaskPlan(taskId, tc.callId);
              }
            }
          : null,
      onReject: isPlan
          ? () {
              final raw = tc.arguments['plan'];
              String? taskId;
              if (raw is Map<String, dynamic>) {
                taskId = raw['taskId'] as String?;
              }
              if (taskId != null) {
                ref
                    .read(chatProvider.notifier)
                    .rejectTaskPlan(taskId, tc.callId);
              }
            }
          : null,
      onChoiceSelected: (choice) {
        ref.read(chatProvider.notifier).sendMessage(choice);
      },
    );
  }

  // ── Markdown Body ──────────────────────────────────────────────────────────
  Widget _buildMarkdownBody(String content, bool isDark, Color textColor) {
    final codeBg = isDark
        ? DesignTokens.surfaceDark
        : DesignTokens.surfaceInputLight;
    final borderColor = isDark
        ? DesignTokens.borderDark
        : DesignTokens.borderLight;

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
              color: isDark
                  ? DesignTokens.textSecondaryDark
                  : DesignTokens.textSecondaryLight,
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}

// ── شريط التفكير (ثابت — لا يُوسّع، التفاصيل دائماً مخفية) ──────────────────
class _ThinkingSection extends StatelessWidget {
  final String? activeStatus;
  final String? thinkingContent;
  final bool isStreaming;
  final bool isDark;
  final int? stepNumber;

  const _ThinkingSection({
    required this.activeStatus,
    this.thinkingContent,
    required this.isStreaming,
    required this.isDark,
    this.stepNumber,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final hasThinkingText =
        thinkingContent != null && thinkingContent!.trim().isNotEmpty;

    final String statusText;
    final stepSuffix = stepNumber != null ? ' (مرحلة $stepNumber)' : '';
    final isExecutingTool =
        activeStatus != null && activeStatus!.startsWith('⚙️');
    if (isStreaming) {
      if (isExecutingTool) {
        statusText = activeStatus!;
      } else if (hasThinkingText) {
        final rawLines = thinkingContent!
            .trim()
            .split('\n')
            .map((l) => l.replaceAll(RegExp(r'^[#*_\-\s>]+'), '').trim())
            .where((l) => l.isNotEmpty && l.length > 2)
            .toList();
        final latestIdea = rawLines.isNotEmpty ? rawLines.last : null;
        if (latestIdea != null && latestIdea.isNotEmpty) {
          statusText = '🧠 $latestIdea';
        } else {
          statusText = activeStatus ?? 'يفكّر بعمق...$stepSuffix';
        }
      } else {
        statusText = activeStatus ?? 'يفكّر...$stepSuffix';
      }
    } else if (hasThinkingText) {
      statusText = activeStatus ?? 'اكتمل التفكير$stepSuffix';
    } else {
      statusText = activeStatus ?? 'عملية التفكير$stepSuffix';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignTokens.space4,
        horizontal: DesignTokens.space4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isStreaming)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                end: DesignTokens.space8,
              ),
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
              padding: const EdgeInsetsDirectional.only(
                end: DesignTokens.space8,
              ),
              child: Icon(
                Icons.psychology_outlined,
                size: 15,
                color: secondary,
              ),
            ),
          Flexible(
            child: Text(
              statusText,
              style: TextStyle(
                color: secondary,
                fontSize: DesignTokens.fontSizeSm,
                fontWeight: FontWeight.w500,
                fontFamily: DesignTokens.fontFamilySans,
                fontFamilyFallback: DesignTokens.sansFallbacks,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isStreaming) ...[
            const SizedBox(width: DesignTokens.space8),
            _LiveElapsedTimer(
              key: ValueKey(activeStatus ?? 'thinking'),
              color: secondary,
            ),
          ],
        ],
      ),
    );
  }
}

// ── عداد وقت حي لعمليات الأدوات ──────────────────────────────────────────────
/// يعدّ الثواني من 0 ويُعيد تشغيله تلقائياً عند تغيّر الـ [key].
/// يُستخدم لإظهار كم وقت مضى على العملية الجارية لطمأنة المستخدم.
class _LiveElapsedTimer extends StatefulWidget {
  final Color color;
  const _LiveElapsedTimer({super.key, required this.color});

  @override
  State<_LiveElapsedTimer> createState() => _LiveElapsedTimerState();
}

class _LiveElapsedTimerState extends State<_LiveElapsedTimer> {
  late final DateTime _startTime;
  Timer? _timer;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime).inSeconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = _elapsed % 60;
    final mins = _elapsed ~/ 60;
    final label = mins > 0 ? '$minsم $secsث' : '$secsث';
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: widget.color.withValues(alpha: 0.55),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
