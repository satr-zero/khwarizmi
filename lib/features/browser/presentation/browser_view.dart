import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/browser/services/agent_browser_service.dart';

/// Interactive UI view for Khwarizmi's dedicated Agent Browser.
class AgentBrowserView extends StatefulWidget {
  final String? initialUrl;
  const AgentBrowserView({super.key, this.initialUrl});

  @override
  State<AgentBrowserView> createState() => _AgentBrowserViewState();
}

class _AgentBrowserViewState extends State<AgentBrowserView> {
  final _service = AgentBrowserService.instance;
  late final TextEditingController _urlController;
  bool _isInit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? 'about:blank');
    _initBrowser();
  }

  Future<void> _initBrowser() async {
    try {
      await _service.initialize();
      if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
        await _service.controller?.loadUrl(widget.initialUrl!);
      }
      if (mounted) {
        setState(() {
          _isInit = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _service.controller;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final surfaceColor = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Column(
          children: [
            // Top Toolbar
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.space16,
                vertical: DesignTokens.space8,
              ),
              color: surfaceColor,
              child: Row(
                children: [
                  // Shield / Isolation Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.space8,
                      vertical: DesignTokens.space4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? DesignTokens.hoverDark : DesignTokens.hoverLight,
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      border: Border.all(color: borderColor, width: DesignTokens.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_outlined, size: 14, color: primaryTextColor),
                        const SizedBox(width: DesignTokens.space4),
                        Text(
                          'جلسة معزولة (خوارزمي)',
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space12),

                  // Navigation buttons
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, size: 16, color: secondaryTextColor),
                    tooltip: 'رجوع',
                    onPressed: () => ctrl?.goBack(),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, size: 16, color: secondaryTextColor),
                    tooltip: 'تحديث',
                    onPressed: () => ctrl?.reload(),
                  ),
                  const SizedBox(width: DesignTokens.space8),

                  // URL Address Bar
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _service.currentUrlNotifier,
                      builder: (context, currentUrl, _) {
                        if (!_urlController.text.startsWith(currentUrl)) {
                          _urlController.text = currentUrl;
                        }
                        return Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? DesignTokens.bgDark : DesignTokens.bgLight,
                            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                            border: Border.all(color: borderColor, width: DesignTokens.hairline),
                          ),
                          child: TextField(
                            controller: _urlController,
                            style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: primaryTextColor),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: DesignTokens.space8,
                                vertical: DesignTokens.space8,
                              ),
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                currentUrl.startsWith('https') ? Icons.lock_outline_rounded : Icons.public_rounded,
                                size: 14,
                                color: secondaryTextColor,
                              ),
                            ),
                            onSubmitted: (val) {
                              if (val.trim().isNotEmpty) {
                                String u = val.trim();
                                if (!u.startsWith('http')) u = 'https://$u';
                                ctrl?.loadUrl(u);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space12),

                  // Loading indicator
                  ValueListenableBuilder<bool>(
                    valueListenable: _service.isLoadingNotifier,
                    builder: (context, isLoading, _) {
                      return isLoading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(secondaryTextColor),
                              ),
                            )
                          : const SizedBox(width: 14);
                    },
                  ),
                  const SizedBox(width: DesignTokens.space12),

                  // Close Button
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: secondaryTextColor),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Browser Body
            Expanded(
              child: _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 36, color: primaryTextColor),
                          const SizedBox(height: DesignTokens.space8),
                          Text(
                            'خطأ في تشغيل محرك WebView2: $_error',
                            style: TextStyle(color: secondaryTextColor, fontSize: DesignTokens.fontSizeSm),
                          ),
                        ],
                      ),
                    )
                  : (_isInit && ctrl != null && ctrl.value.isInitialized)
                      ? Webview(ctrl)
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: secondaryTextColor),
                              ),
                              const SizedBox(height: DesignTokens.space12),
                              Text(
                                'جارٍ تهيئة متصفح الوكيل المعزول (WebView2)...',
                                style: TextStyle(color: secondaryTextColor, fontSize: DesignTokens.fontSizeSm),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
