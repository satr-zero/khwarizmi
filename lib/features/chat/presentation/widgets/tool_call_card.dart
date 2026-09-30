import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';
import 'package:khwarizmi/features/agent/presentation/widgets/task_plan_card.dart';
import 'package:khwarizmi/features/chat/presentation/utils/tool_presentation_formatter.dart';
import 'package:khwarizmi/core/security/question_criticality_classifier.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/choice_options_card.dart';
import 'package:khwarizmi/features/projects/presentation/widgets/inline_diff_card.dart';
import 'package:khwarizmi/features/projects/services/project_file_service.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';

/// An inline, collapsible tool execution card strictly following the monochrome
/// visual identity and supporting 4 distinct states:
/// 1. Running
/// 2. Success
/// 3. Error
/// 4. Awaiting Confirmation
class ToolCallCard extends StatefulWidget {
  final ToolCallInfo toolCall;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;
  final ValueChanged<String>? onChoiceSelected;
  final int? stepIndex;
  final int? totalSteps;

  const ToolCallCard({
    super.key,
    required this.toolCall,
    this.onConfirm,
    this.onReject,
    this.onChoiceSelected,
    this.stepIndex,
    this.totalSteps,
  });

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  late bool _isExpanded;
  final Set<int> _expandedResultIndices = {};

  @override
  void initState() {
    super.initState();
    // Awaiting confirmation starts expanded; success/running starts collapsed
    _isExpanded = widget.toolCall.status == ToolCallStatus.awaitingConfirmation;
  }

  @override
  void didUpdateWidget(covariant ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toolCall.status != widget.toolCall.status) {
      if (widget.toolCall.status == ToolCallStatus.awaitingConfirmation) {
        _isExpanded = true;
      }
    }
  }

  void _toggleExpanded() {
    // If awaiting confirmation, keep it prominent and open
    if (widget.toolCall.status == ToolCallStatus.awaitingConfirmation) return;

    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final primaryTextColor = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    final status = widget.toolCall.status;
    final friendlyName = ToolPresentationFormatter.getFriendlyToolName(
      widget.toolCall.toolName,
      widget.toolCall.arguments,
    );

    final summaryText =
        widget.toolCall.summary ??
        ToolPresentationFormatter.getFriendlySummary(
          widget.toolCall.toolName,
          widget.toolCall.result,
          arguments: widget.toolCall.arguments,
          errorMessage: widget.toolCall.errorMessage,
        );

    final isAwaiting = status == ToolCallStatus.awaitingConfirmation;

    // ── 1. عرض بطاقة خطة العمل التفاعلية المخصصة ──────────────────────────
    if (widget.toolCall.toolName == 'task_plan') {
      TaskPlan? plan;
      try {
        final planData = widget.toolCall.arguments['plan'];
        if (planData is Map<String, dynamic>) {
          plan = TaskPlan.fromJson(planData);
        } else if (planData is Map) {
          plan = TaskPlan.fromJson(Map<String, dynamic>.from(planData));
        } else if (widget.toolCall.result != null &&
            widget.toolCall.result!.isNotEmpty) {
          final decoded = jsonDecode(widget.toolCall.result!);
          if (decoded is Map<String, dynamic>) {
            plan = TaskPlan.fromJson(decoded);
          }
        }
      } catch (_) {}

      if (plan != null) {
        return TaskPlanCard(
          plan: plan,
          isAwaitingApproval: isAwaiting,
          onApprove: widget.onConfirm,
          onCancel: widget.onReject,
        );
      }
    }

    // ── 2. عرض بطاقة الـ Diff التفاعلية المخصصة ───────────────────────────
    if (widget.toolCall.toolName == 'propose_file_change' ||
        widget.toolCall.toolName == 'propose_file_patch') {
      final filePath = widget.toolCall.arguments['path']?.toString() ?? '';
      String? changeId;
      try {
        if (widget.toolCall.result != null &&
            widget.toolCall.result!.isNotEmpty) {
          final decoded = jsonDecode(widget.toolCall.result!);
          if (decoded is Map<String, dynamic>) {
            changeId = decoded['change_id']?.toString();
          }
        }
      } catch (_) {}

      if (filePath.isNotEmpty) {
        // إصلاح 05: معاملات propose_file_patch لا تتضمن new_content أصلاً
        // (فقط search_text/replace_text)، فكان تمرير arguments['new_content']
        // ينتج null ويظهر الـ Diff فارغاً حتى يُسجَّل التعديل المعلّق ويُربط
        // بالبطاقة. المعاينة المحلية (_PendingPatchPreview) تحسب المحتوى
        // الجديد بنفس منطق الأداة فيظهر الـ Diff فوراً.
        if (widget.toolCall.toolName == 'propose_file_patch') {
          return _PendingPatchPreview(
            filePath: filePath,
            searchText:
                widget.toolCall.arguments['search_text']?.toString() ?? '',
            replaceText:
                widget.toolCall.arguments['replace_text']?.toString() ?? '',
            changeId: changeId,
            onApprove: widget.onConfirm,
            onReject: widget.onReject,
          );
        }
        return InlineDiffCard(
          filePath: filePath,
          newContent: widget.toolCall.arguments['new_content']?.toString(),
          changeId: changeId,
          onApprove: widget.onConfirm,
          onReject: widget.onReject,
        );
      }
    }

    // ── 3. عرض بطاقة خيارات الاختيار التفاعلية (Choice Options Card) مع التصعيد التلقائي
    if (widget.toolCall.toolName == 'ask_user') {
      final question = widget.toolCall.arguments['question']?.toString() ?? '';
      final rawOptions = widget.toolCall.arguments['options'];
      final options = (rawOptions is List)
          ? rawOptions.map((e) => e.toString()).toList()
          : <String>[];
      final defaultOption = widget.toolCall.arguments['default_option']
          ?.toString();
      final explicitCritical = widget.toolCall.arguments['critical'] as bool?;
      final isCritical = QuestionCriticalityClassifier.isCritical(
        question: question,
        explicitTag: explicitCritical,
        arguments: widget.toolCall.arguments,
      );

      if (options.isNotEmpty) {
        return ChoiceOptionsCard(
          question: question,
          options: options,
          defaultOption: defaultOption,
          isCritical: isCritical,
          onSelected: (selected) {
            if (widget.onChoiceSelected != null) {
              widget.onChoiceSelected!(selected);
            }
          },
        );
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: DesignTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header / Summary row (clickable without borders)
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.space4,
                vertical: DesignTokens.space4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // State Icon
                  _buildStatusIndicator(status, isDark),
                  const SizedBox(width: DesignTokens.space8),

                  // Step counter badge if part of a sequence
                  if (widget.stepIndex != null &&
                      widget.totalSteps != null &&
                      widget.totalSteps! > 1) ...[
                    Text(
                      '(${widget.stepIndex}/${widget.totalSteps})',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        color: secondaryTextColor,
                        fontFamily: DesignTokens.fontFamilyMono,
                      ),
                    ),
                    const SizedBox(width: DesignTokens.space8),
                  ],

                  // Operation name
                  Flexible(
                    child: Text(
                      status == ToolCallStatus.running
                          ? friendlyName
                          : summaryText,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeSm,
                        fontWeight: status == ToolCallStatus.error
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: status == ToolCallStatus.running
                            ? secondaryTextColor
                            : primaryTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space4),

                  // Down arrow for collapsing/expanding
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded Human-Friendly View (shown when arrow is clicked)
          if (_isExpanded) ...[
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: DesignTokens.space12,
                top: DesignTokens.space4,
                bottom: DesignTokens.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildExpandedContent(
                    isDark,
                    primaryTextColor,
                    secondaryTextColor,
                  ),

                  // Confirmation buttons if awaiting confirmation
                  if (isAwaiting) ...[
                    const SizedBox(height: DesignTokens.space8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.onReject != null)
                          OutlinedButton(
                            onPressed: widget.onReject,
                            child: const Text('إلغاء الإجراء'),
                          ),
                        const SizedBox(width: DesignTokens.space8),
                        if (widget.onConfirm != null)
                          ElevatedButton(
                            onPressed: widget.onConfirm,
                            child: const Text('تأكيد والمتابعة'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(ToolCallStatus status, bool isDark) {
    switch (status) {
      case ToolCallStatus.running:
        return SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark
                  ? DesignTokens.statusPendingDark
                  : DesignTokens.statusPendingLight,
            ),
          ),
        );

      case ToolCallStatus.success:
        return Icon(
          Icons.check_rounded,
          size: 14,
          color: isDark
              ? DesignTokens.statusSuccessDark
              : DesignTokens.statusSuccessLight,
        );

      case ToolCallStatus.error:
        return Icon(
          Icons.error_outline_rounded,
          size: 14,
          weight: 700,
          color: isDark
              ? DesignTokens.statusErrorDark
              : DesignTokens.statusErrorLight,
        );

      case ToolCallStatus.awaitingConfirmation:
        return Icon(
          Icons.help_outline_rounded,
          size: 14,
          color: isDark
              ? DesignTokens.textPrimaryDark
              : DesignTokens.textPrimaryLight,
        );
    }
  }

  Widget _buildCodeBox(String content, bool isDark) {
    final boxBg = isDark ? DesignTokens.bgDark : DesignTokens.surfaceInputLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(DesignTokens.space8),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: border, width: DesignTokens.hairline),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          content,
          style: TextStyle(
            fontFamily: DesignTokens.fontFamilyMono,
            fontFamilyFallback: DesignTokens.monoFallbacks,
            fontSize: DesignTokens.fontSizeXs,
            height: 1.4,
            color: isDark
                ? DesignTokens.textPrimaryDark
                : DesignTokens.textPrimaryLight,
          ),
        ),
      ),
    );
  }

  Widget _buildCodeSearchResults(
    String? rawResult,
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
  ) {
    if (rawResult == null || rawResult.isEmpty) {
      return Text(
        'جاري البحث في كود المشروع...',
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          color: secondaryColor,
        ),
      );
    }

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(rawResult);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    } catch (_) {}

    if (decoded == null) {
      return _buildCodeBox(rawResult, isDark);
    }

    if (decoded.containsKey('error')) {
      return Text(
        decoded['error'].toString(),
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          color: isDark
              ? DesignTokens.statusErrorDark
              : DesignTokens.statusErrorLight,
        ),
      );
    }

    final query =
        decoded['query']?.toString() ??
        widget.toolCall.arguments['query']?.toString() ??
        '';
    final rawMatches = decoded['matches'] as List?;
    final matches =
        rawMatches?.whereType<Map<String, dynamic>>().toList() ?? [];
    final truncated = decoded['truncated'] == true;

    if (matches.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DesignTokens.space8),
        decoration: BoxDecoration(
          color: isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(
            color: isDark ? DesignTokens.borderDark : DesignTokens.borderLight,
            width: DesignTokens.hairline,
          ),
        ),
        child: Text(
          'لم يتم العثور على أي تطابق لـ "$query" في ملفات المشروع.',
          style: TextStyle(
            fontSize: DesignTokens.fontSizeXs,
            color: secondaryColor,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.search_rounded, size: 13, color: secondaryColor),
            const SizedBox(width: DesignTokens.space4),
            Text(
              'مواقع النتائج (${matches.length}${truncated ? '+' : ''}):',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
            const Spacer(),
            Text(
              'انقر لمعاينة السياق',
              style: TextStyle(fontSize: 10, color: secondaryColor),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.space4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: matches.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: DesignTokens.space4),
            itemBuilder: (context, index) {
              final match = matches[index];
              final file = match['file']?.toString() ?? '';
              final line = match['line'] ?? 0;
              final contextSnippet =
                  match['context']?.toString() ??
                  match['line_content']?.toString() ??
                  '';
              final isSnippetExpanded = _expandedResultIndices.contains(index);

              final fileName = p.basename(file);
              final dirName = p.dirname(file);

              return Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignTokens.surfaceDark
                      : DesignTokens.surfaceLight,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(
                    color: isDark
                        ? DesignTokens.borderDark
                        : DesignTokens.borderLight,
                    width: DesignTokens.hairline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusSm,
                      ),
                      onTap: () {
                        setState(() {
                          if (isSnippetExpanded) {
                            _expandedResultIndices.remove(index);
                          } else {
                            _expandedResultIndices.add(index);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.space8,
                          vertical: DesignTokens.space4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 14,
                              color: secondaryColor,
                            ),
                            const SizedBox(width: DesignTokens.space4),
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: fileName,
                                      style: TextStyle(
                                        fontSize: DesignTokens.fontSizeXs,
                                        fontWeight: FontWeight.w600,
                                        color: primaryColor,
                                      ),
                                    ),
                                    if (dirName.isNotEmpty && dirName != '.')
                                      TextSpan(
                                        text: '  $dirName',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: secondaryColor,
                                        ),
                                      ),
                                  ],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: DesignTokens.space4),
                            // Line badge: #L105
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? DesignTokens.bgDark
                                    : DesignTokens.surfaceInputLight,
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                  color: isDark
                                      ? DesignTokens.borderDark
                                      : DesignTokens.borderLight,
                                  width: DesignTokens.hairline,
                                ),
                              ),
                              child: Text(
                                '#L$line',
                                style: TextStyle(
                                  fontFamily: DesignTokens.fontFamilyMono,
                                  fontFamilyFallback:
                                      DesignTokens.monoFallbacks,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: DesignTokens.space4),
                            Icon(
                              isSnippetExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: secondaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isSnippetExpanded && contextSnippet.isNotEmpty) ...[
                      Divider(
                        height: 1,
                        color: isDark
                            ? DesignTokens.borderDark
                            : DesignTokens.borderLight,
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(DesignTokens.space8),
                        color: isDark
                            ? DesignTokens.bgDark
                            : const Color(0xFFF1F5F9),
                        child: SelectableText(
                          contextSnippet,
                          style: TextStyle(
                            fontFamily: DesignTokens.fontFamilyMono,
                            fontFamilyFallback: DesignTokens.monoFallbacks,
                            fontSize: 11,
                            height: 1.45,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        if (truncated) ...[
          const SizedBox(height: DesignTokens.space4),
          Text(
            '⚠️ تم تقييد العرض بأول ${matches.length} نتيجة — استخدم مساراً أضيق لتحديد نطاق البحث إن لزم.',
            style: TextStyle(fontSize: 10, color: secondaryColor),
          ),
        ],
      ],
    );
  }

  Widget _buildExpandedContent(
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
  ) {
    switch (widget.toolCall.toolName) {
      case 'search_project_code':
        return _buildCodeSearchResults(
          widget.toolCall.result,
          isDark,
          primaryColor,
          secondaryColor,
        );

      case 'list_project_files':
        return _buildFileListResults(
          widget.toolCall.result,
          widget.toolCall.arguments,
          isDark,
          primaryColor,
          secondaryColor,
        );

      case 'read_project_file':
        return _buildFileReadResults(
          widget.toolCall.result,
          widget.toolCall.arguments,
          isDark,
          primaryColor,
          secondaryColor,
        );

      case 'run_terminal_command':
        return _buildTerminalResults(
          widget.toolCall.result,
          widget.toolCall.arguments,
          isDark,
          primaryColor,
          secondaryColor,
        );

      case 'web_search':
        return _buildWebSearchResults(
          widget.toolCall.result,
          widget.toolCall.arguments,
          isDark,
          primaryColor,
          secondaryColor,
        );

      case 'fetch_url':
      case 'browse_url':
        return _buildUrlResults(
          widget.toolCall.result,
          widget.toolCall.arguments,
          isDark,
          primaryColor,
          secondaryColor,
        );

      default:
        return _buildFriendlyGenericResults(
          widget.toolCall.toolName,
          widget.toolCall.arguments,
          widget.toolCall.result,
          isDark,
          primaryColor,
          secondaryColor,
        );
    }
  }

  Widget _buildFileListResults(
    String? rawResult,
    Map<String, dynamic> arguments,
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
  ) {
    final folderPath = arguments['path']?.toString();
    final displayPath =
        (folderPath == null || folderPath.trim().isEmpty || folderPath == '.')
        ? 'جذر المشروع'
        : folderPath.trim();

    if (rawResult == null || rawResult.isEmpty) {
      return Text(
        'جاري استعراض محتويات $displayPath...',
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          color: secondaryColor,
        ),
      );
    }

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(rawResult);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    } catch (_) {}

    if (decoded != null && decoded.containsKey('error')) {
      return Text(
        decoded['error'].toString(),
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          color: isDark
              ? DesignTokens.statusErrorDark
              : DesignTokens.statusErrorLight,
        ),
      );
    }

    final entries =
        (decoded?['entries'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder_open_rounded, size: 14, color: secondaryColor),
            const SizedBox(width: DesignTokens.space6),
            Expanded(
              child: Text(
                'المجلد: $displayPath',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignTokens.surfaceDark
                    : DesignTokens.surfaceInputLight,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(
                  color: isDark
                      ? DesignTokens.borderDark
                      : DesignTokens.borderLight,
                  width: DesignTokens.hairline,
                ),
              ),
              child: Text(
                '${entries.length} عنصر',
                style: TextStyle(fontSize: 10, color: secondaryColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.space6),
        if (entries.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DesignTokens.space8),
            decoration: BoxDecoration(
              color: isDark
                  ? DesignTokens.surfaceDark
                  : DesignTokens.surfaceLight,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: Border.all(
                color: isDark
                    ? DesignTokens.borderDark
                    : DesignTokens.borderLight,
                width: DesignTokens.hairline,
              ),
            ),
            child: Text(
              'المجلد فارغ لا يحتوي على أي ملفات أو مجلدات.',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: secondaryColor,
              ),
            ),
          ),
        ] else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? DesignTokens.surfaceDark
                    : DesignTokens.surfaceLight,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(
                  color: isDark
                      ? DesignTokens.borderDark
                      : DesignTokens.borderLight,
                  width: DesignTokens.hairline,
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: entries.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isDark
                      ? DesignTokens.borderDark
                      : DesignTokens.borderLight,
                ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final name = entry['name']?.toString() ?? '';
                  final isDir = entry['type'] == 'directory';
                  final sizeBytes = entry['size'] as num?;

                  String? sizeLabel;
                  if (!isDir && sizeBytes != null) {
                    if (sizeBytes < 1024) {
                      sizeLabel = '$sizeBytes B';
                    } else if (sizeBytes < 1024 * 1024) {
                      sizeLabel = '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
                    } else {
                      sizeLabel =
                          '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDir
                              ? Icons.folder_rounded
                              : Icons.insert_drive_file_outlined,
                          size: 14,
                          color: isDir
                              ? const Color(0xFF6366F1)
                              : secondaryColor,
                        ),
                        const SizedBox(width: DesignTokens.space6),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: DesignTokens.fontSizeXs,
                              fontWeight: isDir
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: primaryColor,
                              fontFamily: isDir
                                  ? null
                                  : DesignTokens.fontFamilyMono,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (sizeLabel != null)
                          Text(
                            sizeLabel,
                            style: TextStyle(
                              fontFamily: DesignTokens.fontFamilyMono,
                              fontSize: 10,
                              color: secondaryColor,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFileReadResults(
    String? rawResult,
    Map<String, dynamic> arguments,
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
  ) {
    final filePath = arguments['path']?.toString() ?? '';
    final fileName = filePath.isNotEmpty ? p.basename(filePath) : 'الملف';
    final dirName = filePath.isNotEmpty ? p.dirname(filePath) : '';

    if (rawResult == null || rawResult.isEmpty) {
      return Text(
        'جاري قراءة $fileName...',
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          color: secondaryColor,
        ),
      );
    }

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(rawResult);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    } catch (_) {}

    if (decoded != null && decoded.containsKey('error')) {
      return Text(
        decoded['error'].toString(),
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          color: isDark
              ? DesignTokens.statusErrorDark
              : DesignTokens.statusErrorLight,
        ),
      );
    }

    final content = decoded?['content']?.toString() ?? rawResult;
    final shownLines = decoded?['shown_lines']?.toString();
    final totalLines = decoded?['total_lines']?.toString();

    final lines = content.split('\n');

    int startLineNum = 1;
    if (shownLines != null && shownLines.contains('-')) {
      final parts = shownLines.split('-');
      startLineNum = int.tryParse(parts.first.trim()) ?? 1;
    }

    final numberedBuffer = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final currentLineNum = startLineNum + i;
      final pad = '$currentLineNum'.padLeft(4, ' ');
      numberedBuffer.writeln('$pad  ${lines[i]}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 14, color: secondaryColor),
            const SizedBox(width: DesignTokens.space6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: fileName,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                    if (dirName.isNotEmpty && dirName != '.')
                      TextSpan(
                        text: '  $dirName',
                        style: TextStyle(fontSize: 11, color: secondaryColor),
                      ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (shownLines != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignTokens.surfaceDark
                      : DesignTokens.surfaceInputLight,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(
                    color: isDark
                        ? DesignTokens.borderDark
                        : DesignTokens.borderLight,
                    width: DesignTokens.hairline,
                  ),
                ),
                child: Text(
                  '#L$shownLines${totalLines != null ? ' (من أصل $totalLines)' : ''}',
                  style: TextStyle(
                    fontFamily: DesignTokens.fontFamilyMono,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DesignTokens.space6),
        _buildCodeBox(numberedBuffer.toString().trimRight(), isDark),
      ],
    );
  }

  Widget _buildTerminalResults(
    String? rawResult,
    Map<String, dynamic> arguments,
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
  ) {
    final cmd = arguments['command']?.toString() ?? '';

    Map<String, dynamic>? decoded;
    if (rawResult != null && rawResult.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawResult);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      } catch (_) {}
    }

    final exitCode = decoded?['exit_code'] ?? 0;
    final isSuccess =
        exitCode == 0 || exitCode == '0' || decoded?['status'] == 'success';
    final output =
        decoded?['output']?.toString() ??
        decoded?['stdout']?.toString() ??
        decoded?['message']?.toString() ??
        rawResult ??
        '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF262626),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Row(
            children: [
              Text(
                r'$ ',
                style: TextStyle(
                  fontFamily: DesignTokens.fontFamilyMono,
                  fontSize: DesignTokens.fontSizeXs,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF10B981),
                ),
              ),
              Expanded(
                child: Text(
                  cmd,
                  style: const TextStyle(
                    fontFamily: DesignTokens.fontFamilyMono,
                    fontSize: DesignTokens.fontSizeXs,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSuccess
                      ? const Color(0xFF065F46)
                      : const Color(0xFF991B1B),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  isSuccess ? 'ناجح' : 'فشل ($exitCode)',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (output.trim().isNotEmpty) ...[
          const SizedBox(height: DesignTokens.space4),
          _buildCodeBox(output.trim(), isDark),
        ],
      ],
    );
  }

  Widget _buildWebSearchResults(
    String? rawResult,
    Map<String, dynamic> arguments,
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
  ) {
    final query = arguments['query']?.toString() ?? '';

    Map<String, dynamic>? decoded;
    if (rawResult != null && rawResult.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawResult);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      } catch (_) {}
    }

    final rawResults = decoded?['results'] as List?;
    final results =
        rawResults?.whereType<Map<String, dynamic>>().toList() ?? [];

    if (results.isEmpty) {
      return Text(
        'لم يتم العثور على نتائج بحث مباشرة لـ "$query"',
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          color: secondaryColor,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.search_rounded, size: 14, color: secondaryColor),
            const SizedBox(width: DesignTokens.space6),
            Text(
              'نتائج البحث عن "$query":',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.space6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: results.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: DesignTokens.space4),
            itemBuilder: (context, index) {
              final item = results[index];
              final title = item['title']?.toString() ?? '';
              final url = item['url']?.toString() ?? '';
              final snippet = item['snippet']?.toString() ?? '';
              final host = Uri.tryParse(url)?.host ?? '';

              return Container(
                padding: const EdgeInsets.all(DesignTokens.space8),
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignTokens.surfaceDark
                      : DesignTokens.surfaceLight,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(
                    color: isDark
                        ? DesignTokens.borderDark
                        : DesignTokens.borderLight,
                    width: DesignTokens.hairline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    if (host.isNotEmpty)
                      Text(
                        host,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        snippet,
                        style: TextStyle(fontSize: 11, color: secondaryColor),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUrlResults(
    String? rawResult,
    Map<String, dynamic> arguments,
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
  ) {
    final url = arguments['url']?.toString() ?? '';
    final host = Uri.tryParse(url)?.host ?? url;

    Map<String, dynamic>? decoded;
    if (rawResult != null && rawResult.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawResult);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      } catch (_) {}
    }

    final title = decoded?['title']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(DesignTokens.space8),
      decoration: BoxDecoration(
        color: isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
          color: isDark ? DesignTokens.borderDark : DesignTokens.borderLight,
          width: DesignTokens.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.language_rounded,
                size: 14,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(width: DesignTokens.space6),
              Expanded(
                child: Text(
                  title.isNotEmpty ? title : host,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (url.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              url,
              style: TextStyle(fontSize: 10, color: secondaryColor),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFriendlyGenericResults(
    String toolName,
    Map<String, dynamic> arguments,
    String? rawResult,
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
  ) {
    Map<String, dynamic>? decoded;
    if (rawResult != null && rawResult.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawResult);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      } catch (_) {}
    }

    final displayParams = <String, String>{};
    for (final entry in arguments.entries) {
      if (entry.key.startsWith('_')) continue;
      final label = _friendlyParamName(entry.key);
      displayParams[label] = entry.value?.toString() ?? '';
    }

    String? resultText;
    if (decoded != null) {
      if (decoded.containsKey('message')) {
        resultText = decoded['message']?.toString();
      } else if (decoded.containsKey('summary')) {
        resultText = decoded['summary']?.toString();
      } else if (decoded.containsKey('status')) {
        resultText = decoded['status']?.toString();
      } else if (decoded.containsKey('error')) {
        resultText = 'خطأ: ${decoded['error']}';
      }
    } else if (rawResult != null && rawResult.isNotEmpty) {
      resultText = rawResult;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (displayParams.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: displayParams.entries.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignTokens.surfaceDark
                      : DesignTokens.surfaceInputLight,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(
                    color: isDark
                        ? DesignTokens.borderDark
                        : DesignTokens.borderLight,
                    width: DesignTokens.hairline,
                  ),
                ),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: TextStyle(fontSize: 11, color: primaryColor),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: DesignTokens.space6),
        ],
        if (resultText != null && resultText.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DesignTokens.space8),
            decoration: BoxDecoration(
              color: isDark
                  ? DesignTokens.surfaceDark
                  : DesignTokens.surfaceLight,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: Border.all(
                color: isDark
                    ? DesignTokens.borderDark
                    : DesignTokens.borderLight,
                width: DesignTokens.hairline,
              ),
            ),
            child: Text(
              resultText,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: primaryColor,
              ),
            ),
          ),
      ],
    );
  }

  String _friendlyParamName(String key) {
    switch (key) {
      case 'path':
        return 'المسار';
      case 'query':
        return 'البحث';
      case 'command':
        return 'الأمر';
      case 'url':
        return 'الرابط';
      case 'title':
        return 'العنوان';
      case 'description':
        return 'الوصف';
      case 'search_type':
        return 'نوع البحث';
      default:
        return key;
    }
  }
}

// ── 5. معاينة Diff المحلية لتعديل propose_file_patch (إصلاح 05) ──────────────

/// بطاقة معاينة Diff محلية لتعديل `propose_file_patch`.
///
/// **إصلاح 05:** معاملات هذه الأداة لا تتضمن `new_content` أصلاً (فقط
/// `search_text`/`replace_text`)، فكانت بطاقة الأداة تمرر null للـ
/// InlineDiffCard ويظهر الـ Diff فارغاً حتى يُربط التعديل المعلّق عبر
/// مطابقة المسار — وهي مطابقة كانت تفشل على Windows بسبب اختلاف فواصل
/// المسار. هذه المعاينة تقرأ الملف الحالي من القرص وتطبّق الاستبدال بنفس
/// منطق الأداة نفسها (readRawContent ثم replaceFirst)، فيظهر الـ Diff
/// صحيحاً فوراً وباستقلال عن الربط بالتعديل المعلّق؛ وعندما يُسجَّل
/// التعديل المعلّق فعلياً تعرض InlineDiffCard الـ diff الرسمي منه مباشرة.
class _PendingPatchPreview extends StatefulWidget {
  final String filePath;
  final String searchText;
  final String replaceText;
  final String? changeId;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _PendingPatchPreview({
    required this.filePath,
    required this.searchText,
    required this.replaceText,
    this.changeId,
    this.onApprove,
    this.onReject,
  });

  @override
  State<_PendingPatchPreview> createState() => _PendingPatchPreviewState();
}

class _PendingPatchPreviewState extends State<_PendingPatchPreview> {
  String? _oldContent;
  String? _newContent;

  @override
  void initState() {
    super.initState();
    _computePreview();
  }

  Future<void> _computePreview() async {
    final project = ProjectManager.instance.activeProject;
    // لا مشروع نشط أو معاملات ناقصة — الأداة نفسها سترفض الطلب لاحقاً
    // برسالة خطأ صريحة؛ لا معاينة ممكنة هنا.
    if (project == null || widget.searchText.isEmpty) return;
    final current = await ProjectFileService.readRawContent(
      project,
      widget.filePath,
    );
    if (!mounted || current == null) return;
    setState(() {
      _oldContent = current;
      _newContent = current.replaceFirst(widget.searchText, widget.replaceText);
    });
  }

  @override
  Widget build(BuildContext context) {
    return InlineDiffCard(
      filePath: widget.filePath,
      oldContent: _oldContent,
      newContent: _newContent,
      changeId: widget.changeId,
      onApprove: widget.onApprove,
      onReject: widget.onReject,
    );
  }
}

// ── Tool Call Timeline ────────────────────────────────────────────────────────

/// يربط سلسلة بطاقات أدوات بخط زمني رأسي بصري يوضح التسلسل والتقدم.
///
/// الاستخدام:
/// ```dart
/// ToolCallTimeline(toolCalls: turn.toolCalls)
/// ```
class ToolCallTimeline extends StatelessWidget {
  final List<ToolCallInfo> toolCalls;

  const ToolCallTimeline({super.key, required this.toolCalls});

  @override
  Widget build(BuildContext context) {
    if (toolCalls.isEmpty) return const SizedBox.shrink();

    // بطاقة واحدة → لا نحتاج الخط الزمني
    if (toolCalls.length == 1) {
      return ToolCallCard(toolCall: toolCalls.first);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark
        ? DesignTokens.borderDark
        : DesignTokens.borderLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final total = toolCalls.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عداد الخطوات الكلي
        Padding(
          padding: const EdgeInsetsDirectional.only(
            bottom: DesignTokens.space4,
          ),
          child: Text(
            '$total خطوات',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        // الخط الزمني
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الخط الرأسي + النقاط
              SizedBox(
                width: 20,
                child: CustomPaint(
                  painter: _TimelinePainter(
                    lineColor: lineColor,
                    dotColor: secondary,
                    itemCount: total,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.space8),

              // البطاقات
              Expanded(
                child: Column(
                  children: [
                    for (int i = 0; i < toolCalls.length; i++) ...[
                      Row(
                        children: [
                          // رقم الخطوة
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${i + 1}',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: DesignTokens.fontSizeXs,
                                color: secondary,
                                fontFamily: DesignTokens.fontFamilyMono,
                                fontFamilyFallback: DesignTokens.monoFallbacks,
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.space8),
                          Expanded(child: ToolCallCard(toolCall: toolCalls[i])),
                        ],
                      ),
                      if (i < toolCalls.length - 1)
                        const SizedBox(height: DesignTokens.space4),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Timeline Painter ──────────────────────────────────────────────────────────

class _TimelinePainter extends CustomPainter {
  final Color lineColor;
  final Color dotColor;
  final int itemCount;

  _TimelinePainter({
    required this.lineColor,
    required this.dotColor,
    required this.itemCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (itemCount <= 0) return;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = DesignTokens.hairline
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    final itemHeight = size.height / itemCount;
    final cx = size.width / 2;

    // رسم الخط الرأسي
    canvas.drawLine(
      Offset(cx, itemHeight * 0.3),
      Offset(cx, size.height - itemHeight * 0.3),
      linePaint,
    );

    // رسم نقاط لكل بطاقة
    for (int i = 0; i < itemCount; i++) {
      final y = itemHeight * i + itemHeight * 0.3;
      canvas.drawCircle(Offset(cx, y), 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.lineColor != lineColor ||
      old.dotColor != dotColor ||
      old.itemCount != itemCount;
}
