import 'dart:math';

/// Programmatic Safety Barrier for Financial & Checkout Actions.
///
/// CRITICAL ARCHITECTURAL NOTE:
/// This class enforces a code-level defense-in-depth safety barrier against
/// unauthorized financial actions, purchases, payments, and sensitive credit card
/// inputs.
///
/// LIMITATION NOTICE:
/// As noted in the system requirements, this programmatic detection is heuristic
/// and precautionary (defense-in-depth); it cannot guarantee 100% detection of
/// every conceivable custom payment UI on the internet, but it reliably intercepts
/// standard payment gateways, common checkout paths, credit card form fields,
/// and purchase submission buttons before execution.
class BrowserSecurityInterceptor {
  // Known payment gateways & processors
  static const List<String> knownPaymentDomains = [
    'checkout.stripe.com',
    'stripe.com',
    'paypal.com',
    'pay.google.com',
    'pay.apple.com',
    'checkout.shopify.com',
    'klarna.com',
    'square.com',
    'squareup.com',
    'razorpay.com',
    'adyen.com',
    'checkout.tabby.ai',
    'tamara.co',
    'hyperpay.com',
    'paytabs.com',
    'authorize.net',
    'checkout.com',
  ];

  // URL path / query fragments strongly indicative of checkout or final payment
  static const List<String> checkoutUrlPatterns = [
    '/checkout',
    '/pay',
    '/payment',
    '/billing',
    '/cart/checkout',
    'step=payment',
    'order/confirm',
    'order-confirm',
    'buy-now',
    'purchase',
    'place-order',
    'finalize-order',
  ];

  // Element selectors, IDs, classes, values, or text indicative of final payment/purchase submission
  static const List<String> paymentElementKeywords = [
    'pay now',
    'pay-now',
    'pay',
    'complete purchase',
    'complete-purchase',
    'place order',
    'place-order',
    'submit payment',
    'submit-payment',
    'confirm payment',
    'confirm-payment',
    'confirm order',
    'confirm-order',
    'confirm',
    'order',
    'authorize payment',
    'buy now',
    'buy-now',
    'checkout',
    'purchase',
    'cvv',
    'cvc',
    'credit-card',
    'creditcard',
    'card-number',
    'cardnumber',
    'exp-date',
    'expiry',
    // Arabic keywords
    'دفع',
    'ادفع الآن',
    'إتمام الدفع',
    'إتمام الشراء',
    'إتمام الطلب',
    'تأكيد الدفع',
    'تأكيد الشراء',
    'تأكيد الطلب',
    'شراء الآن',
    'سداد',
    'بطاقة الائتمان',
    'رقم البطاقة',
    'رمز الأمان',
  ];

  // Active single-use confirmation tokens: Map<Token, TokenRecord>
  static final Map<String, _ConfirmationToken> _activeTokens = {};
  static final Random _rng = Random.secure();

  /// Inspects a click action before it is forwarded to the browser engine.
  ///
  /// Returns a [SecurityInspectionResult] indicating whether the click is allowed
  /// or requires explicit user confirmation.
  static SecurityInspectionResult inspectClickAction({
    required String currentUrl,
    required String selector,
    String? elementText,
    String? confirmationToken,
  }) {
    // 1. Verify single-use confirmation token if provided explicitly
    if (confirmationToken != null && confirmationToken.isNotEmpty) {
      final tokenRecord = _activeTokens[confirmationToken];
      if (tokenRecord != null && !tokenRecord.isExpired && tokenRecord.matches(currentUrl, selector)) {
        // Invalidate token immediately upon single use
        _activeTokens.remove(confirmationToken);
        return const SecurityInspectionResult.allowed(usedConfirmationToken: true);
      }
    }

    // 1b. Check if an approved unexpired token exists for this URL & selector
    String? approvedToken;
    for (final entry in _activeTokens.entries) {
      if (!entry.value.isExpired && entry.value.matches(currentUrl, selector)) {
        approvedToken = entry.key;
        break;
      }
    }
    if (approvedToken != null) {
      _activeTokens.remove(approvedToken);
      return const SecurityInspectionResult.allowed(usedConfirmationToken: true);
    }

    final lowerUrl = currentUrl.toLowerCase();
    final lowerSelector = selector.toLowerCase();
    final lowerText = elementText?.toLowerCase() ?? '';

    // 2. Check if URL matches a known payment gateway or checkout path
    final domainMatch = knownPaymentDomains.firstWhere(
      (d) => lowerUrl.contains(d),
      orElse: () => '',
    );

    final urlPatternMatch = checkoutUrlPatterns.firstWhere(
      (p) => lowerUrl.contains(p),
      orElse: () => '',
    );

    // 3. Check if selector or text matches payment keywords
    final keywordMatch = paymentElementKeywords.firstWhere(
      (kw) => lowerSelector.contains(kw) || lowerText.contains(kw),
      orElse: () => '',
    );

    final isPaymentUrl = domainMatch.isNotEmpty || urlPatternMatch.isNotEmpty;
    final isPaymentElement = keywordMatch.isNotEmpty;

    // If an element click looks like payment submission or occurs inside a checkout URL
    if (isPaymentElement || (isPaymentUrl && _isPotentiallyActionable(lowerSelector))) {
      final token = _generateToken(currentUrl, selector);
      return SecurityInspectionResult.blocked(
        riskReason: 'إجراء مالي أو خطوة دفع / شراء نهائية',
        matchedPattern: keywordMatch.isNotEmpty ? keywordMatch : (domainMatch.isNotEmpty ? domainMatch : urlPatternMatch),
        confirmationToken: token,
        details: {
          'url': currentUrl,
          'selector': selector,
          'element_text': elementText ?? '',
          'detected_domain': domainMatch,
          'detected_url_pattern': urlPatternMatch,
          'detected_keyword': keywordMatch,
        },
      );
    }

    return const SecurityInspectionResult.allowed();
  }

  /// Inspects an input fill action (e.g. typing credit card or CVV details).
  static SecurityInspectionResult inspectFillAction({
    required String currentUrl,
    required String selector,
    required String text,
    String? confirmationToken,
  }) {
    // Check token if provided
    if (confirmationToken != null && confirmationToken.isNotEmpty) {
      final tokenRecord = _activeTokens[confirmationToken];
      if (tokenRecord != null && !tokenRecord.isExpired && tokenRecord.matches(currentUrl, selector)) {
        _activeTokens.remove(confirmationToken);
        return const SecurityInspectionResult.allowed(usedConfirmationToken: true);
      }
    }

    final lowerSelector = selector.toLowerCase();
    final sensitiveKeywords = ['card', 'cc', 'cvv', 'cvc', 'exp', 'بطاقة', 'ائتمان'];
    final isSensitiveField = sensitiveKeywords.any((kw) => lowerSelector.contains(kw));

    // Also check if text resembles credit card number (13-19 digits)
    final cleanDigits = text.replaceAll(RegExp(r'\s|-'), '');
    final looksLikeCardNumber = RegExp(r'^\d{13,19}$').hasMatch(cleanDigits);

    if (isSensitiveField || looksLikeCardNumber) {
      final token = _generateToken(currentUrl, selector);
      return SecurityInspectionResult.blocked(
        riskReason: 'إدخال بيانات دفع أو بطاقة ائتمانية حساسة',
        matchedPattern: isSensitiveField ? 'حقل بطاقة دفع ($lowerSelector)' : 'أرقام تطابق بطاقة دفع',
        confirmationToken: token,
        details: {
          'url': currentUrl,
          'selector': selector,
          'is_card_number': looksLikeCardNumber,
        },
      );
    }

    return const SecurityInspectionResult.allowed();
  }

  /// Manually authorizes an existing token after explicit user confirmation in chat/UI.
  static bool authorizeConfirmationToken(String token) {
    final record = _activeTokens[token];
    if (record != null && !record.isExpired) {
      record.isApproved = true;
      return true;
    }
    return false;
  }

  /// Processes user chat message for explicit confirmation or rejection.
  /// If user confirms ("نعم", "أكّد", "أوافق", "yes", "confirm"), authorizes pending tokens.
  /// If user rejects ("لا", "إلغاء", "الغاء", "ارفض", "no", "cancel"), invalidates all tokens.
  static bool handleUserChatConfirmationOrRejection(String userText) {
    final trimmed = userText.trim().toLowerCase();
    final isExplicitConfirmation = trimmed == 'نعم' ||
        trimmed == 'أكد' ||
        trimmed == 'أكّد' ||
        trimmed == 'تأكيد' ||
        trimmed == 'موافق' ||
        trimmed == 'أوافق' ||
        trimmed == 'yes' ||
        trimmed == 'confirm' ||
        trimmed.startsWith('نعم') ||
        trimmed.startsWith('أؤكد') ||
        trimmed.startsWith('أوافق') ||
        trimmed.startsWith('أكد');

    if (isExplicitConfirmation) {
      bool anyApproved = false;
      for (final record in _activeTokens.values) {
        if (!record.isExpired && !record.isApproved) {
          record.isApproved = true;
          anyApproved = true;
        }
      }
      return anyApproved;
    }

    final isExplicitRejection = trimmed == 'لا' ||
        trimmed == 'إلغاء' ||
        trimmed == 'الغاء' ||
        trimmed == 'ارفض' ||
        trimmed == 'أرفض' ||
        trimmed == 'no' ||
        trimmed == 'cancel' ||
        trimmed.startsWith('لا') ||
        trimmed.startsWith('إلغاء') ||
        trimmed.startsWith('الغاء') ||
        trimmed.startsWith('ارفض') ||
        trimmed.startsWith('أرفض');

    if (isExplicitRejection) {
      _activeTokens.clear();
      return true;
    }

    return false;
  }

  /// Returns true if there is any pending confirmation token awaiting user action.
  static bool get isAwaitingConfirmation =>
      _activeTokens.values.any((t) => !t.isExpired && !t.isApproved);

  /// Cleans up expired tokens (older than 10 minutes)
  static void cleanupExpiredTokens() {
    _activeTokens.removeWhere((_, record) => record.isExpired);
  }

  static String _generateToken(String url, String selector) {
    cleanupExpiredTokens();
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    final token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _activeTokens[token] = _ConfirmationToken(
      token: token,
      url: url,
      selector: selector,
      createdAt: DateTime.now(),
    );
    return token;
  }

  static bool _isPotentiallyActionable(String lowerSelector) {
    return lowerSelector.contains('submit') ||
        lowerSelector.contains('button') ||
        lowerSelector.contains('btn') ||
        lowerSelector.contains('input[type="submit"]') ||
        lowerSelector.contains('continue') ||
        lowerSelector.contains('next');
  }
}

class _ConfirmationToken {
  final String token;
  final String url;
  final String selector;
  final DateTime createdAt;
  bool isApproved = false;

  _ConfirmationToken({
    required this.token,
    required this.url,
    required this.selector,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().difference(createdAt) > const Duration(minutes: 10);

  bool matches(String targetUrl, String targetSelector) {
    return isApproved && url == targetUrl && selector == targetSelector;
  }
}

class SecurityInspectionResult {
  final bool isBlocked;
  final String? riskReason;
  final String? matchedPattern;
  final String? confirmationToken;
  final Map<String, dynamic> details;
  final bool usedConfirmationToken;

  const SecurityInspectionResult.allowed({this.usedConfirmationToken = false})
      : isBlocked = false,
        riskReason = null,
        matchedPattern = null,
        confirmationToken = null,
        details = const {};

  const SecurityInspectionResult.blocked({
    required this.riskReason,
    required this.matchedPattern,
    required this.confirmationToken,
    this.details = const {},
  })  : isBlocked = true,
        usedConfirmationToken = false;

  Map<String, dynamic> toJson() {
    return {
      'status': isBlocked ? 'payment_confirmation_required' : 'allowed',
      'requires_user_confirmation': isBlocked,
      'risk_reason': riskReason,
      'matched_pattern': matchedPattern,
      'confirmation_token': confirmationToken,
      'details': details,
      'message': isBlocked
          ? '⚠️ حاجز الأمان الحاسم: تم اعتراض إجراء مالي أو خطوة دفع تلقائياً. يتطلب هذا الإجراء موافقة وتأكيداً صريحاً لا لبس فيه من المستخدم قبل المتابعة.'
          : 'مسموح',
    };
  }
}
