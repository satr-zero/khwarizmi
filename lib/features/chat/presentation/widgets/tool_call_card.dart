import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/utils/tool_presentation_formatter.dart';

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
  final int? stepIndex;
  final int? totalSteps;

  const ToolCallCard({
    super.key,
    required this.toolCall,
    this.onConfirm,
    this.onReject,
    this.stepIndex,
    this.totalSteps,
  });

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  late bool _isExpanded;

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
    final disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    final status = widget.toolCall.status;
    final friendlyName = ToolPresentationFormatter.getFriendlyToolName(
      widget.toolCall.toolName,
      widget.toolCall.arguments,
    );

    final summaryText = widget.toolCall.summary ??
        ToolPresentationFormatter.getFriendlySummary(
          widget.toolCall.toolName,
          widget.toolCall.result,
          errorMessage: widget.toolCall.errorMessage,
        );

    final isAwaiting = status == ToolCallStatus.awaitingConfirmation;

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
                  if (widget.stepIndex != null && widget.totalSteps != null && widget.totalSteps! > 1) ...[
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
                      status == ToolCallStatus.running ? friendlyName : summaryText,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeSm,
                        fontWeight: status == ToolCallStatus.error ? FontWeight.w600 : FontWeight.w400,
                        color: status == ToolCallStatus.running ? secondaryTextColor : primaryTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space4),

                  // Down arrow for collapsing/expanding
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
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

          // Expanded Raw Parameters & Result view (shown when arrow is clicked)
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
                  // Tool identification
                  Row(
                    children: [
                      Text(
                        'الأداة: ',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          color: secondaryTextColor,
                        ),
                      ),
                      Text(
                        widget.toolCall.toolName,
                        style: const TextStyle(
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontFamilyFallback: DesignTokens.monoFallbacks,
                          fontSize: DesignTokens.fontSizeXs,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.space4),

                  // Arguments
                  if (widget.toolCall.arguments.isNotEmpty) ...[
                    Text(
                      'المدخلات (Arguments):',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space4),
                    _buildCodeBox(
                      const JsonEncoder.withIndent('  ').convert(widget.toolCall.arguments),
                      isDark,
                    ),
                    const SizedBox(height: DesignTokens.space4),
                  ],

                  // Raw result
                  if (widget.toolCall.result != null && widget.toolCall.result!.isNotEmpty) ...[
                    Text(
                      'المخرجات (Output):',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space4),
                    _buildCodeBox(
                      _formatResult(widget.toolCall.result!),
                      isDark,
                    ),
                  ],

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
              isDark ? DesignTokens.statusPendingDark : DesignTokens.statusPendingLight,
            ),
          ),
        );

      case ToolCallStatus.success:
        return Icon(
          Icons.check_rounded,
          size: 14,
          color: isDark ? DesignTokens.statusSuccessDark : DesignTokens.statusSuccessLight,
        );

      case ToolCallStatus.error:
        return Icon(
          Icons.error_outline_rounded,
          size: 14,
          weight: 700,
          color: isDark ? DesignTokens.statusErrorDark : DesignTokens.statusErrorLight,
        );

      case ToolCallStatus.awaitingConfirmation:
        return Icon(
          Icons.help_outline_rounded,
          size: 14,
          color: isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight,
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
            color: isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight,
          ),
        ),
      ),
    );
  }

  String _formatResult(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
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
    final lineColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final total = toolCalls.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عداد الخطوات الكلي
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: DesignTokens.space4),
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

