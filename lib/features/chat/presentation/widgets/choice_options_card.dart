import 'dart:async';
import 'package:flutter/material.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';

/// بطاقة خيارات تفاعلية مع آلية التصعيد التلقائي بعد 30 ثانية للأسئلة غير الحرجة.
class ChoiceOptionsCard extends StatefulWidget {
  final String question;
  final List<String> options;
  final String? defaultOption;
  final bool isCritical;
  final ValueChanged<String> onSelected;

  const ChoiceOptionsCard({
    super.key,
    required this.question,
    required this.options,
    this.defaultOption,
    this.isCritical = false,
    required this.onSelected,
  });

  @override
  State<ChoiceOptionsCard> createState() => _ChoiceOptionsCardState();
}

class _ChoiceOptionsCardState extends State<ChoiceOptionsCard> {
  Timer? _countdownTimer;
  int _secondsLeft = 30;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    // يبدأ المؤقت فقط إن كانت خيارات غير حرجة
    if (!widget.isCritical && widget.options.isNotEmpty) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        _handleAutoEscalate();
      } else {
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  void _handleAutoEscalate() {
    if (_answered) return;
    _answered = true;
    final pick = widget.defaultOption ?? widget.options.first;
    widget.onSelected(pick);
  }

  void _selectOption(String option) {
    if (_answered) return;
    _answered = true;
    _countdownTimer?.cancel();
    widget.onSelected(option);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    final defaultChoice = widget.defaultOption ?? (widget.options.isNotEmpty ? widget.options.first : '');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: DesignTokens.space8),
      padding: const EdgeInsets.all(DesignTokens.space12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: widget.isCritical
              ? (isDark ? Colors.red.shade800 : Colors.red.shade300)
              : (isDark ? Colors.blue.shade800 : Colors.blue.shade300),
          width: DesignTokens.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── رأس السؤال والمؤشر ──────────────────────────────────────────
          Row(
            children: [
              Icon(
                widget.isCritical ? Icons.security_rounded : Icons.help_outline_rounded,
                size: 16,
                color: widget.isCritical
                    ? (isDark ? Colors.red.shade300 : Colors.red.shade700)
                    : (isDark ? Colors.blue.shade300 : Colors.blue.shade700),
              ),
              const SizedBox(width: DesignTokens.space8),
              Expanded(
                child: Text(
                  widget.question,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSm,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ),
              if (!widget.isCritical && widget.options.isNotEmpty && !_answered) ...[
                const SizedBox(width: DesignTokens.space8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF282810) : const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isDark ? Colors.amber.shade700 : Colors.amber.shade400,
                      width: DesignTokens.hairline,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 11, color: isDark ? Colors.amber.shade300 : Colors.amber.shade800),
                      const SizedBox(width: 3),
                      Text(
                        '$_secondsLeft ث',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                          fontFamily: DesignTokens.fontFamilyMono,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          // ── رسالة التصعيد التلقائي إن كانت غير حرجة ─────────────────────
          if (!widget.isCritical && defaultChoice.isNotEmpty && !_answered) ...[
            const SizedBox(height: DesignTokens.space4),
            Text(
              'إذا لم تختر خلال $_secondsLeft ثانية، سيعتمد خوارزمي تلقائياً: "$defaultChoice"',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: secondary,
              ),
            ),
          ],

          const SizedBox(height: DesignTokens.space12),

          // ── قائمة الخيارات التفاعلية ───────────────────────────────────
          Wrap(
            spacing: DesignTokens.space8,
            runSpacing: DesignTokens.space8,
            children: widget.options.map((option) {
              final isDefault = option == defaultChoice;
              return ActionChip(
                label: Text(
                  isDefault ? '$option (موصى به)' : option,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    fontWeight: isDefault ? FontWeight.w700 : FontWeight.w500,
                    color: primary,
                  ),
                ),
                backgroundColor: isDefault
                    ? (isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50)
                    : (isDark ? DesignTokens.bgDark : DesignTokens.surfaceInputLight),
                side: BorderSide(
                  color: isDefault
                      ? (isDark ? Colors.blue.shade600 : Colors.blue.shade400)
                      : border,
                  width: DesignTokens.hairline,
                ),
                onPressed: _answered ? null : () => _selectOption(option),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
