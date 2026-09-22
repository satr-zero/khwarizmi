import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/presentation/controllers/task_provider.dart';
import 'package:khwarizmi/features/browser/presentation/browser_view.dart';
import 'package:khwarizmi/features/browser/services/agent_browser_service.dart';

/// لوحة المتصفح الحية — تعرض نفس WebView2 المُستخدَم فعلياً من أدوات المتصفح
/// لحظة بلحظة أثناء تنفيذ مهمة مستقلة.
///
/// تُضاف كعمود جانبي في تخطيط [ChatScreen] وتستخدم نفس [AgentBrowserService.instance]
/// بلا نسخة منفصلة — الحركة الفعلية (تنقل، نقر، تعبئة) مرئية لحظياً.
class LiveBrowserPanel extends ConsumerStatefulWidget {
  const LiveBrowserPanel({super.key});

  @override
  ConsumerState<LiveBrowserPanel> createState() => _LiveBrowserPanelState();
}

class _LiveBrowserPanelState extends ConsumerState<LiveBrowserPanel> {
  final _service = AgentBrowserService.instance;
  bool _isInit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initBrowser();
  }

  Future<void> _initBrowser() async {
    if (_service.isReady) {
      if (mounted) setState(() => _isInit = true);
      return;
    }
    try {
      await _service.initialize();
      if (mounted) setState(() => _isInit = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final bg = isDark ? DesignTokens.bgDark : DesignTokens.bgLight;

    final currentAction = ref.watch(lastBrowserActionProvider);
    final ctrl = _service.controller;

    final panelWidth = math.min(
      540.0,
      math.max(380.0, MediaQuery.of(context).size.width * 0.44),
    );

    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(color: border, width: DesignTokens.hairline),
        ),
      ),
      child: Column(
        children: [
          // ── شريط الحالة والتحكم العلوي ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.space8,
              vertical: 6,
            ),
            color: surface,
            child: Row(
              children: [
                // أزرار التنقل السريع
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, size: 14, color: secondary),
                  tooltip: 'رجوع',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => ctrl?.goBack(),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_forward_rounded, size: 14, color: secondary),
                  tooltip: 'تقدم',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => ctrl?.goForward(),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, size: 14, color: secondary),
                  tooltip: 'إعادة تحميل',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => ctrl?.reload(),
                ),

                const SizedBox(width: DesignTokens.space4),

                // أزرار التمرير السريع
                IconButton(
                  icon: Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: secondary),
                  tooltip: 'تمرير لأعلى (Scroll Up)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => _service.scrollPage(direction: 'up', amount: 400),
                ),
                IconButton(
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: secondary),
                  tooltip: 'تمرير لأسفل (Scroll Down)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => _service.scrollPage(direction: 'down', amount: 400),
                ),

                const SizedBox(width: DesignTokens.space4),

                // مؤشر الإجراء الحالي (ToolCallCard مصغّر)
                if (currentAction != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.space4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? DesignTokens.surfaceInputDark
                            : DesignTokens.surfaceInputLight,
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusSm),
                        border: Border.all(color: border, width: DesignTokens.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: secondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              currentAction,
                              style: TextStyle(
                                fontSize: DesignTokens.fontSizeXs,
                                fontFamily: DesignTokens.fontFamilyMono,
                                color: secondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _service.currentUrlNotifier,
                      builder: (_, url, child) {
                        final display =
                            url == 'about:blank' ? 'المتصفح الحي' : _shortenUrl(url);
                        return Text(
                          display,
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: secondary,
                            fontFamily: DesignTokens.fontFamilyMono,
                          ),
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ),

                const SizedBox(width: DesignTokens.space4),

                // مؤشر التحميل
                ValueListenableBuilder<bool>(
                  valueListenable: _service.isLoadingNotifier,
                  builder: (_, loading, child) => loading
                      ? SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: secondary,
                          ),
                        )
                      : const SizedBox(width: 6),
                ),

                const SizedBox(width: DesignTokens.space4),

                // فتح في نافذة كبيرة منفصلة
                IconButton(
                  icon: Icon(Icons.open_in_full_rounded, size: 13, color: secondary),
                  tooltip: 'فتح في نافذة كاملة',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (ctx) => const AgentBrowserView(),
                    );
                  },
                ),

                const SizedBox(width: DesignTokens.space4),

                // زر إغلاق اللوحة
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 15, color: secondary),
                  tooltip: 'إخفاء لوحة المتصفح',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  onPressed: () {
                    ref.read(tasksProvider.notifier).toggleBrowserPanel();
                  },
                ),
              ],
            ),
          ),

          // ── جسم المتصفح ──────────────────────────────────────────────
          Expanded(
            child: _error != null
                ? _ErrorView(message: _error!, secondary: secondary)
                : (_isInit && ctrl != null && ctrl.value.isInitialized)
                    ? Webview(ctrl) // نفس الـ WebviewController من AgentBrowserService
                    : _LoadingView(secondary: secondary),
          ),
        ],
      ),
    );
  }

  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return url.length > 30 ? '${url.substring(0, 30)}...' : url;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final Color secondary;

  const _ErrorView({required this.message, required this.secondary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 24, color: secondary),
            const SizedBox(height: DesignTokens.space8),
            Text(
              'خطأ في تشغيل WebView2:\n$message',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final Color secondary;
  const _LoadingView({required this.secondary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: secondary),
          ),
          const SizedBox(height: DesignTokens.space8),
          Text(
            'جارٍ تهيئة متصفح الوكيل...',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }
}
