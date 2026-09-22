import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import 'package:khwarizmi/core/security/browser_security_interceptor.dart';

/// Service managing Khwarizmi's dedicated, isolated Agent Browser.
///
/// Features:
/// 1. Strict Isolation: Custom User Data Folder at `%APPDATA%\Khwarizmi\BrowserProfile`.
///    Zero cookie or session sharing with user's default Edge/Chrome browsers.
/// 2. Programmatic Security Barrier: Intercepts financial/payment actions before execution.
/// 3. Headless + Visual: Can run headlessly for background tools or be mounted in Flutter UI.
/// 4. Controlled Downloads: Dedicated directory at `%USERPROFILE%\Downloads\Khwarizmi\`.
class AgentBrowserService {
  static final AgentBrowserService instance = AgentBrowserService._internal();
  AgentBrowserService._internal();

  WebviewController? _controller;
  bool _isEnvironmentInitialized = false;
  bool _isInitializing = false;

  final ValueNotifier<String> currentUrlNotifier = ValueNotifier<String>('about:blank');
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> pageTitleNotifier = ValueNotifier<String>('');

  WebviewController? get controller => _controller;
  bool get isReady => _controller != null && _controller!.value.isInitialized;

  /// Gets the dedicated User Data Folder for full session isolation.
  static String get profileDirectory {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    return p.canonicalize(p.join(appData, 'Khwarizmi', 'BrowserProfile'));
  }

  /// Gets the dedicated download directory.
  static String get downloadDirectory {
    final userProfile = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return p.canonicalize(p.join(userProfile, 'Downloads', 'Khwarizmi'));
  }

  /// Initializes the browser environment and controller.
  Future<void> initialize() async {
    if (isReady || _isInitializing) return;
    _isInitializing = true;

    try {
      // 1. Ensure directories exist
      final profileDir = Directory(profileDirectory);
      if (!await profileDir.exists()) {
        await profileDir.create(recursive: true);
      }

      final dlDir = Directory(downloadDirectory);
      if (!await dlDir.exists()) {
        await dlDir.create(recursive: true);
      }

      // 2. Initialize environment with isolated user data folder once
      if (!_isEnvironmentInitialized) {
        try {
          await WebviewController.initializeEnvironment(
            userDataPath: profileDirectory,
            additionalArguments: '--disable-features=Translate',
          );
        } catch (e) {
          // May be thrown if already initialized in this process
          debugPrint('[AgentBrowserService] Environment init notice: $e');
        }
        _isEnvironmentInitialized = true;
      }

      // 3. Create and initialize controller
      final ctrl = WebviewController();
      await ctrl.initialize();

      // Set initial bounds for headless layout rendering
      await ctrl.setSize(const Size(1280, 800));
      await ctrl.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await ctrl.setDefaultContextMenusEnabled(true);

      // Listen to events
      ctrl.url.listen((url) {
        currentUrlNotifier.value = url;
      });

      ctrl.loadingState.listen((state) {
        isLoadingNotifier.value = (state == LoadingState.loading);
      });

      ctrl.title.listen((title) {
        pageTitleNotifier.value = title;
      });

      _controller = ctrl;
    } catch (e) {
      debugPrint('[AgentBrowserService] Controller initialization error: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Navigates to [url] and extracts clean structured content for the agent.
  Future<String> browseUrl(String targetUrl) async {
    await initialize();
    final ctrl = _controller;
    if (ctrl == null) {
      return jsonEncode({'error': 'تعذر تهيئة متصفح الوكيل المستقل'});
    }

    String finalUrl = targetUrl.trim();
    if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
      finalUrl = 'https://$finalUrl';
    }

    try {
      final completer = Completer<void>();
      late StreamSubscription sub;

      sub = ctrl.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted || state == LoadingState.none) {
          if (!completer.isCompleted) completer.complete();
        }
      });

      await ctrl.loadUrl(finalUrl);

      // Wait for page to finish loading or timeout after 15s
      await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
      await sub.cancel();

      // Additional small delay for dynamic JS execution
      await Future.delayed(const Duration(milliseconds: 700));

      // Extract simplified, structured content via JavaScript (no raw bloated HTML)
      const extractionScript = r'''
(() => {
  const result = {
    title: document.title || '',
    url: window.location.href,
    headings: [],
    mainText: '',
    links: [],
    buttons: [],
    hasPaymentForm: false,
    paymentClues: []
  };

  // Check for headings
  document.querySelectorAll('h1, h2, h3').forEach(h => {
    const txt = (h.innerText || '').trim();
    if (txt) result.headings.push({ tag: h.tagName.toLowerCase(), text: txt });
  });

  // Extract clean visible text
  const clone = document.body ? document.body.cloneNode(true) : null;
  if (clone) {
    clone.querySelectorAll('script, style, noscript, svg, nav, footer, header').forEach(el => el.remove());
    let txt = (clone.innerText || '').replace(/\s+/g, ' ').trim();
    if (txt.length > 3500) {
      txt = txt.substring(0, 3500) + '... [تم اقتصار النص المتبقي]';
    }
    result.mainText = txt;
  }

  // Extract interactive links (top 15)
  document.querySelectorAll('a[href]').forEach(a => {
    const txt = (a.innerText || '').trim();
    const href = a.getAttribute('href');
    if (txt && href && !href.startsWith('javascript:') && result.links.length < 15) {
      result.links.push({ text: txt, href: href, selector: a.id ? '#' + a.id : null });
    }
  });

  // Extract clickable buttons
  document.querySelectorAll('button, input[type="button"], input[type="submit"], [role="button"]').forEach(btn => {
    const txt = (btn.innerText || btn.value || btn.getAttribute('aria-label') || '').trim();
    if (txt && result.buttons.length < 15) {
      const id = btn.id ? '#' + btn.id : null;
      result.buttons.push({ text: txt, selector: id, type: btn.type || 'button' });
    }
  });

  // Check for payment / checkout indicators on page
  const pageContent = (document.body ? document.body.innerText : '').toLowerCase();
  const paymentKeywords = ['checkout', 'pay now', 'credit card', 'cvv', 'card number', 'ادفع', 'شراء', 'دفع', 'سداد', 'إتمام الطلب'];
  for (const kw of paymentKeywords) {
    if (pageContent.includes(kw)) {
      result.paymentClues.push(kw);
    }
  }
  if (result.paymentClues.length > 0 || window.location.href.includes('checkout') || window.location.href.includes('pay')) {
    result.hasPaymentForm = true;
  }

  return JSON.stringify(result);
})()
''';

      final scriptOutput = await ctrl.executeScript(extractionScript);
      Map<String, dynamic> extractedData = {};
      if (scriptOutput != null) {
        try {
          if (scriptOutput is String) {
            extractedData = jsonDecode(scriptOutput) as Map<String, dynamic>;
          } else if (scriptOutput is Map) {
            extractedData = Map<String, dynamic>.from(scriptOutput);
          }
        } catch (_) {}
      }

      final pageTitle = extractedData['title'] ?? pageTitleNotifier.value;
      final currentUrl = extractedData['url'] ?? finalUrl;
      final mainText = extractedData['mainText'] ?? '';
      final hasPaymentForm = extractedData['hasPaymentForm'] == true;

      return jsonEncode({
        'status': 'success',
        'url': currentUrl,
        'title': pageTitle,
        'has_payment_form': hasPaymentForm,
        'content_summary': mainText,
        'headings': extractedData['headings'] ?? [],
        'sample_links': extractedData['links'] ?? [],
        'interactive_buttons': extractedData['buttons'] ?? [],
        if (hasPaymentForm)
          'security_warning':
              '⚠️ تحذير أمني: تم رصد عناصر دفع أو شراء بهذه الصفحة. أي نقر على زر دفع يتطلب تأكيداً صريحاً من المستخدم.',
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل تصفح الرابط: $e'});
    }
  }

  /// Scrolls the page smoothly in [direction] ('down', 'up', 'top', 'bottom')
  /// or scrolls [selector] into view, and returns the new viewport state.
  Future<String> scrollPage({
    String direction = 'down',
    dynamic amount = 500,
    String? selector,
  }) async {
    await initialize();
    final ctrl = _controller;
    if (ctrl == null) {
      return jsonEncode({'error': 'متصفح الوكيل غير مهيأ'});
    }

    final scrollScript = '''
(() => {
  const dir = ${jsonEncode(direction.toLowerCase())};
  const sel = ${jsonEncode(selector)};
  const rawAmt = ${jsonEncode(amount)};

  let delta = 500;
  if (typeof rawAmt === 'number') {
    delta = rawAmt;
  } else if (rawAmt === 'half_page') {
    delta = Math.round(window.innerHeight * 0.5);
  } else if (rawAmt === 'full_page') {
    delta = Math.round(window.innerHeight * 0.85);
  }

  if (sel) {
    const el = document.querySelector(sel);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      // مؤشر بصري وميضي للعنصر المُمرر إليه
      el.style.outline = '2px dashed #007aff';
      setTimeout(() => { el.style.outline = ''; }, 1200);
      return JSON.stringify({ success: true, scrolledToElement: sel });
    }
  }

  if (dir === 'top') {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  } else if (dir === 'bottom') {
    window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
  } else if (dir === 'up') {
    window.scrollBy({ top: -Math.abs(delta), left: 0, behavior: 'smooth' });
  } else {
    window.scrollBy({ top: Math.abs(delta), left: 0, behavior: 'smooth' });
  }

  return JSON.stringify({ success: true, delta: delta, direction: dir });
})()
''';

    try {
      await ctrl.executeScript(scrollScript);
      // مهلة للسماح للرسوم المتحركة للتمرير السلس بالظهور بوضوح أمام المستخدم
      await Future.delayed(const Duration(milliseconds: 500));

      // استخراج حالة الصفحة بعد التمرير
      const postScrollScript = r'''
(() => {
  const scrollY = window.scrollY || window.pageYOffset || 0;
  const scrollHeight = document.body.scrollHeight || document.documentElement.scrollHeight || 1;
  const innerHeight = window.innerHeight || 1;
  const maxScroll = Math.max(1, scrollHeight - innerHeight);
  const percent = Math.min(100, Math.max(0, Math.round((scrollY / maxScroll) * 100)));

  // العناصر المرئية حالياً في الشاشة
  const visibleHeadings = [];
  document.querySelectorAll('h1, h2, h3, h4').forEach(h => {
    const rect = h.getBoundingClientRect();
    if (rect.top >= 0 && rect.top <= innerHeight) {
      const txt = (h.innerText || '').trim();
      if (txt) visibleHeadings.push({ tag: h.tagName.toLowerCase(), text: txt });
    }
  });

  const visibleButtons = [];
  document.querySelectorAll('button, a[href], [role="button"]').forEach(el => {
    const rect = el.getBoundingClientRect();
    if (rect.top >= 0 && rect.top <= innerHeight && rect.width > 0 && rect.height > 0) {
      const txt = (el.innerText || el.getAttribute('aria-label') || '').trim();
      if (txt && visibleButtons.length < 10) {
        visibleButtons.push({
          text: txt,
          selector: el.id ? '#' + el.id : (el.tagName.toLowerCase() + (el.className ? '.' + el.className.split(' ')[0] : ''))
        });
      }
    }
  });

  // مقتطف من النص المعروض حالياً داخل النافذة المرئية
  let viewportText = '';
  document.querySelectorAll('p, li, article, section').forEach(el => {
    const rect = el.getBoundingClientRect();
    if (rect.top >= 0 && rect.top <= innerHeight) {
      const txt = (el.innerText || '').trim();
      if (txt && viewportText.length < 1500) {
        viewportText += txt + '\n';
      }
    }
  });

  return JSON.stringify({
    scrollY: Math.round(scrollY),
    totalHeight: Math.round(scrollHeight),
    viewportHeight: Math.round(innerHeight),
    scrollPercentage: percent,
    visibleHeadings: visibleHeadings,
    visibleButtons: visibleButtons,
    visibleTextExcerpt: viewportText.trim()
  });
})()
''';

      final metricsRaw = await ctrl.executeScript(postScrollScript);
      Map<String, dynamic> metrics = {};
      if (metricsRaw != null) {
        try {
          metrics = (metricsRaw is String)
              ? jsonDecode(metricsRaw) as Map<String, dynamic>
              : Map<String, dynamic>.from(metricsRaw as Map);
        } catch (_) {}
      }

      return jsonEncode({
        'status': 'success',
        'message': 'تم التمرير بنجاح على الصفحة',
        'direction': direction,
        'scroll_position_y': metrics['scrollY'] ?? 0,
        'scroll_percentage': '${metrics['scrollPercentage'] ?? 0}%',
        'page_total_height': metrics['totalHeight'] ?? 0,
        'visible_headings_in_view': metrics['visibleHeadings'] ?? [],
        'visible_interactive_elements': metrics['visibleButtons'] ?? [],
        'visible_text_snippet': metrics['visibleTextExcerpt'] ?? '',
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل التمرير في المتصفح: $e'});
    }
  }

  /// Inspects the visual styling, color palette, layout, and visible elements
  /// of the current web page.
  Future<String> inspectVisualPage() async {
    await initialize();
    final ctrl = _controller;
    if (ctrl == null) {
      return jsonEncode({'error': 'متصفح الوكيل غير مهيأ'});
    }

    const visualScript = r'''
(() => {
  const result = {
    title: document.title || '',
    url: window.location.href,
    viewport: {
      width: window.innerWidth,
      height: window.innerHeight
    },
    scroll: {
      y: Math.round(window.scrollY),
      totalHeight: Math.round(document.body.scrollHeight),
      percent: Math.min(100, Math.round((window.scrollY / Math.max(1, document.body.scrollHeight - window.innerHeight)) * 100))
    },
    colors: {
      pageBackground: window.getComputedStyle(document.body).backgroundColor,
      textColor: window.getComputedStyle(document.body).color,
      isDarkMode: false,
      accentColors: []
    },
    visibleButtons: [],
    visibleInputs: [],
    visibleCards: []
  };

  // فحص هل الخلفية داكنة أم فاتحة
  const bg = result.colors.pageBackground;
  const rgbMatch = bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
  if (rgbMatch) {
    const r = parseInt(rgbMatch[1]);
    const g = parseInt(rgbMatch[2]);
    const b = parseInt(rgbMatch[3]);
    const brightness = (r * 299 + g * 587 + b * 114) / 1000;
    result.colors.isDarkMode = brightness < 128;
  }

  // جمع الألوان البارزة المستخدمة في الأزرار والعناوين
  const accentSet = new Set();
  document.querySelectorAll('button, a.btn, header, nav, [role="button"]').forEach(el => {
    const style = window.getComputedStyle(el);
    const c = style.backgroundColor;
    if (c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent' && c !== bg) {
      accentSet.add(c);
    }
  });
  result.colors.accentColors = Array.from(accentSet).slice(0, 6);

  // حصر الأزرار المرئية حالياً في نافذة العرض مع أشكالها وألوانها
  document.querySelectorAll('button, input[type="button"], input[type="submit"], [role="button"], a[href]').forEach(btn => {
    const rect = btn.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0 && rect.top >= 0 && rect.top <= window.innerHeight) {
      const style = window.getComputedStyle(btn);
      const text = (btn.innerText || btn.value || btn.getAttribute('aria-label') || '').trim();
      if (text && result.visibleButtons.length < 12) {
        const radius = parseFloat(style.borderRadius) || 0;
        result.visibleButtons.push({
          text: text,
          selector: btn.id ? '#' + btn.id : (btn.className ? '.' + btn.className.trim().split(/\s+/)[0] : btn.tagName.toLowerCase()),
          shape: radius >= 20 ? 'بيضاوي (Pill)' : (radius > 4 ? 'حواف مستديرة (Rounded)' : 'مستطيل حاد (Sharp)'),
          backgroundColor: style.backgroundColor,
          textColor: style.color,
          position: { x: Math.round(rect.left), y: Math.round(rect.top), width: Math.round(rect.width), height: Math.round(rect.height) }
        });
      }
    }
  });

  // حصر حقول الإدخال المرئية حالياً
  document.querySelectorAll('input:not([type="hidden"]), textarea, select').forEach(inp => {
    const rect = inp.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0 && rect.top >= 0 && rect.top <= window.innerHeight) {
      if (result.visibleInputs.length < 8) {
        result.visibleInputs.push({
          type: inp.type || inp.tagName.toLowerCase(),
          placeholder: inp.placeholder || '',
          selector: inp.id ? '#' + inp.id : (inp.name ? `[name="${inp.name}"]` : inp.tagName.toLowerCase()),
          value: inp.value || '',
          position: { x: Math.round(rect.left), y: Math.round(rect.top), width: Math.round(rect.width), height: Math.round(rect.height) }
        });
      }
    }
  });

  return JSON.stringify(result);
})()
''';

    try {
      final visualRaw = await ctrl.executeScript(visualScript);
      Map<String, dynamic> visualData = {};
      if (visualRaw != null) {
        visualData = (visualRaw is String)
            ? jsonDecode(visualRaw) as Map<String, dynamic>
            : Map<String, dynamic>.from(visualRaw as Map);
      }

      return jsonEncode({
        'status': 'success',
        'visual_overview': 'تم فحص المظهر البصري للصفحة الحالية بنجاح',
        'title': visualData['title'] ?? '',
        'url': visualData['url'] ?? '',
        'viewport_size': visualData['viewport'] ?? {},
        'scroll_state': visualData['scroll'] ?? {},
        'color_scheme': visualData['colors'] ?? {},
        'visible_buttons_and_shapes': visualData['visibleButtons'] ?? [],
        'visible_input_fields': visualData['visibleInputs'] ?? [],
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل فحص المظهر البصري للصفحة: $e'});
    }
  }

  /// Clicks an element by [selector] or visible [text], enforcing the Payment Security Barrier.
  /// Injects a visible pulsing beacon so the user literally watches Khwarizmi click the element live!
  Future<String> clickElement(
    String selector, {
    String? text,
    String? confirmationToken,
    bool forceApproved = false,
  }) async {
    await initialize();
    final ctrl = _controller;
    if (ctrl == null) {
      return jsonEncode({'error': 'متصفح الوكيل غير مهيأ'});
    }

    final currentUrl = currentUrlNotifier.value;

    // 1. فحص العنصر مسبقاً (سواء عبر CSS selector أو عبر النص الظاهر)
    final inspectScript = '''
(() => {
  try {
    const sel = ${jsonEncode(selector)};
    const targetText = ${jsonEncode(text)};

    let el = null;
    if (sel && sel.trim().length > 0) {
      try { el = document.querySelector(sel); } catch (_) {}
    }

    // إذا لم يُعثر عليه بالـ selector ووُجد نص، ابحث عن العنصر بمطابقة النص
    if (!el && targetText && targetText.trim().length > 0) {
      const q = targetText.trim().toLowerCase();
      const candidates = document.querySelectorAll('button, a, input[type="button"], input[type="submit"], [role="button"], span, div');
      for (const cand of candidates) {
        const t = (cand.innerText || cand.value || cand.getAttribute('aria-label') || '').trim().toLowerCase();
        if (t === q || (t.includes(q) && t.length < q.length + 20)) {
          el = cand;
          break;
        }
      }
    }

    if (!el) return JSON.stringify({ exists: false });

    return JSON.stringify({
      exists: true,
      tagName: el.tagName.toLowerCase(),
      text: (el.innerText || el.value || el.getAttribute('aria-label') || '').trim(),
      type: el.type || '',
      id: el.id || '',
      className: el.className || ''
    });
  } catch(e) {
    return JSON.stringify({ exists: false, error: e.toString() });
  }
})()
''';

    String? elementText;
    try {
      final inspectRes = await ctrl.executeScript(inspectScript);
      if (inspectRes != null) {
        final decoded = (inspectRes is String)
            ? jsonDecode(inspectRes) as Map<String, dynamic>
            : Map<String, dynamic>.from(inspectRes as Map);
        if (decoded['exists'] == false) {
          return jsonEncode({
            'error': 'لم يتم العثور على العنصر المراد النقر عليه (المحدد: "$selector"${text != null ? '، النص: "$text"' : ''})'
          });
        }
        elementText = decoded['text']?.toString();
      }
    } catch (e) {
      debugPrint('[AgentBrowserService] Element pre-inspection error: $e');
    }

    // 2. فحص حاجز الأمان للدفع والعمليات المالية الحساسة
    if (!forceApproved) {
      final inspection = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: currentUrl,
        selector: selector,
        elementText: elementText,
        confirmationToken: confirmationToken,
      );

      if (inspection.isBlocked) {
        return jsonEncode(inspection.toJson());
      }
    }

    // 3. تنفيذ النقر مع تأثير بصري متحرك يراه المستخدم مباشرة في واجهة المتصفح
    final clickScript = '''
(() => {
  try {
    const sel = ${jsonEncode(selector)};
    const targetText = ${jsonEncode(text)};

    let el = null;
    if (sel && sel.trim().length > 0) {
      try { el = document.querySelector(sel); } catch (_) {}
    }

    if (!el && targetText && targetText.trim().length > 0) {
      const q = targetText.trim().toLowerCase();
      const candidates = document.querySelectorAll('button, a, input[type="button"], input[type="submit"], [role="button"], span, div');
      for (const cand of candidates) {
        const t = (cand.innerText || cand.value || cand.getAttribute('aria-label') || '').trim().toLowerCase();
        if (t === q || (t.includes(q) && t.length < q.length + 20)) {
          el = cand;
          break;
        }
      }
    }

    if (!el) return JSON.stringify({ success: false, error: 'العنصر غير موجود' });

    // تمرير العنصر للمركز بسلاسة
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });

    // إضافة تأثير بصري (ومضة حمراء أنيقة) تظهر للمستخدم مكان النقر
    const rect = el.getBoundingClientRect();
    const ripple = document.createElement('div');
    ripple.id = 'khwarizmi-click-beacon';
    ripple.style.position = 'fixed';
    ripple.style.left = (rect.left + rect.width / 2 - 16) + 'px';
    ripple.style.top = (rect.top + rect.height / 2 - 16) + 'px';
    ripple.style.width = '32px';
    ripple.style.height = '32px';
    ripple.style.borderRadius = '50%';
    ripple.style.backgroundColor = 'rgba(255, 59, 48, 0.4)';
    ripple.style.border = '2px solid #ff3b30';
    ripple.style.boxShadow = '0 0 16px rgba(255, 59, 48, 0.8)';
    ripple.style.zIndex = '9999999';
    ripple.style.pointerEvents = 'none';
    ripple.style.transition = 'transform 0.4s ease-out, opacity 0.4s ease-out';
    ripple.style.transform = 'scale(0.5)';
    document.body.appendChild(ripple);

    requestAnimationFrame(() => {
      ripple.style.transform = 'scale(2.2)';
      ripple.style.opacity = '0';
    });

    setTimeout(() => { ripple.remove(); }, 600);

    // تفعيل أحداث الماوس والنقر الفعلية
    el.focus();
    el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
    el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
    el.click();

    return JSON.stringify({
      success: true,
      tagName: el.tagName.toLowerCase(),
      text: (el.innerText || el.value || '').trim()
    });
  } catch(e) {
    return JSON.stringify({ success: false, error: e.toString() });
  }
})()
''';

    try {
      final clickRes = await ctrl.executeScript(clickScript);
      await Future.delayed(const Duration(milliseconds: 600));

      return jsonEncode({
        'status': 'success',
        'message': 'تم النقر على العنصر بنجاح وشوهد التأثير مباشرة في المتصفح',
        'selector': selector,
        'clicked_text': elementText ?? '',
        'current_url': currentUrlNotifier.value,
        'page_title': pageTitleNotifier.value,
        'details': clickRes,
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل تنفيذ النقر: $e'});
    }
  }

  /// Fills an input field [selector] with [text], enforcing the Payment Security Barrier.
  Future<String> fillInput(
    String selector,
    String text, {
    String? confirmationToken,
    bool forceApproved = false,
  }) async {
    await initialize();
    final ctrl = _controller;
    if (ctrl == null) {
      return jsonEncode({'error': 'متصفح الوكيل غير مهيأ'});
    }

    final currentUrl = currentUrlNotifier.value;

    // 1. CRITICAL SECURITY BARRIER for sensitive fields (credit cards, CVV)
    if (!forceApproved) {
      final inspection = BrowserSecurityInterceptor.inspectFillAction(
        currentUrl: currentUrl,
        selector: selector,
        text: text,
        confirmationToken: confirmationToken,
      );

      if (inspection.isBlocked) {
        return jsonEncode(inspection.toJson());
      }
    }

    // 2. Set input value and dispatch native input & change events with visible focus indicator
    final fillScript = '''
(() => {
  try {
    const sel = ${jsonEncode(selector)};
    let el = null;
    try { el = document.querySelector(sel); } catch (_) {}

    if (!el) {
      // محاولة البحث بالاسم أو الـ placeholder
      el = document.querySelector(`input[name="\${sel}"], input[placeholder*="\${sel}"], textarea[name="\${sel}"]`);
    }

    if (!el) return JSON.stringify({ success: false, error: 'حقل الإدخال غير موجود' });

    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.focus();

    // وميض أزرق أنيق يوضح للمستخدم الحقل الذي يكتب فيه خوارزمي
    const prevOutline = el.style.outline;
    const prevBoxShadow = el.style.boxShadow;
    el.style.outline = '2px solid #007aff';
    el.style.boxShadow = '0 0 12px rgba(0, 122, 255, 0.5)';
    setTimeout(() => {
      el.style.outline = prevOutline;
      el.style.boxShadow = prevBoxShadow;
    }, 1200);

    el.value = ${jsonEncode(text)};
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return JSON.stringify({ success: true, tagName: el.tagName.toLowerCase(), value: el.value });
  } catch(e) {
    return JSON.stringify({ success: false, error: e.toString() });
  }
})()
''';

    try {
      final res = await ctrl.executeScript(fillScript);
      return jsonEncode({
        'status': 'success',
        'message': 'تم إدخال النص بالحقل بنجاح',
        'selector': selector,
        'details': res,
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل تعبئة الحقل: $e'});
    }
  }

  /// Downloads a file from [fileUrl] into `%USERPROFILE%\Downloads\Khwarizmi\`.
  ///
  /// Strictly verifies physical existence and size of the file on disk before reporting success.
  Future<String> downloadFile(String fileUrl) async {
    final dlDir = Directory(downloadDirectory);
    if (!await dlDir.exists()) {
      await dlDir.create(recursive: true);
    }

    try {
      final uri = Uri.parse(fileUrl.trim());
      String fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'download_${DateTime.now().millisecondsSinceEpoch}';
      if (fileName.isEmpty) fileName = 'download_${DateTime.now().millisecondsSinceEpoch}.bin';

      final destinationPath = p.canonicalize(p.join(downloadDirectory, fileName));
      final destFile = File(destinationPath);

      // Perform controlled HTTP download
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await destFile.writeAsBytes(response.bodyBytes, flush: true);

        // Physical verification on disk
        if (await destFile.exists()) {
          final fileSize = await destFile.length();
          return jsonEncode({
            'status': 'success',
            'message': 'اكتمل تحميل الملف وحفظه بنجاح على القرص',
            'file_name': fileName,
            'saved_path': destinationPath,
            'size_bytes': fileSize,
          });
        } else {
          return jsonEncode({'error': 'تعذر التحقق من وجود الملف المحفوظ على القرص بعد التنزيل'});
        }
      } else {
        return jsonEncode({'error': 'فشل تحميل الملف: استجابة الخادم ${response.statusCode}'});
      }
    } catch (e) {
      return jsonEncode({'error': 'حدث خطأ أثناء تحميل الملف: $e'});
    }
  }

  /// Releases resources
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
