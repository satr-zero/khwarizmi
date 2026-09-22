import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/core/security/browser_security_interceptor.dart';

void main() {
  setUp(() {
    BrowserSecurityInterceptor.cleanupExpiredTokens();
  });

  group('Phase 6 Critical Payment Security Barrier Unit Tests', () {
    test('1. Normal navigation and ordinary element clicks are directly allowed', () {
      final res = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://docs.flutter.dev/get-started',
        selector: '#search-box',
        elementText: 'Search documentation',
      );

      expect(res.isBlocked, isFalse);
      expect(res.riskReason, isNull);
    });

    test('2. Clicks on payment gateway domains (e.g. Stripe, PayPal) are programmatically blocked', () {
      final gateways = [
        'https://checkout.stripe.com/c/pay/cs_live_123',
        'https://www.paypal.com/checkoutnow',
        'https://checkout.shopify.com/123/checkouts/abc',
        'https://pay.google.com/gp/p/ui/pay',
        'https://checkout.tabby.ai/payment',
      ];

      for (final url in gateways) {
        final res = BrowserSecurityInterceptor.inspectClickAction(
          currentUrl: url,
          selector: 'button[type="submit"]',
          elementText: 'Submit',
        );

        expect(res.isBlocked, isTrue, reason: 'Failed to block gateway URL: $url');
        expect(res.confirmationToken, isNotNull);
        expect(res.riskReason, contains('إجراء مالي'));
      }
    });

    test('3. Clicks on checkout URL paths (e.g. /checkout, /billing, /pay) are blocked', () {
      final checkoutUrls = [
        'https://store.example.com/checkout/step3',
        'https://myshop.com/cart/checkout',
        'https://service.com/billing?step=payment',
        'https://ecommerce.org/order/confirm',
      ];

      for (final url in checkoutUrls) {
        final res = BrowserSecurityInterceptor.inspectClickAction(
          currentUrl: url,
          selector: '#continue-btn',
          elementText: 'Continue to Place Order',
        );

        expect(res.isBlocked, isTrue, reason: 'Failed to block checkout path: $url');
        expect(res.confirmationToken, isNotNull);
      }
    });

    test('4. Element selectors or button text with payment keywords are blocked even on generic URLs', () {
      final paymentSelectors = [
        '#pay-now-btn',
        'button.complete-purchase',
        'input[value="Place Order"]',
        '#submit-payment',
        'button#buy-now',
      ];

      for (final sel in paymentSelectors) {
        final res = BrowserSecurityInterceptor.inspectClickAction(
          currentUrl: 'https://generalstore.com/cart',
          selector: sel,
        );

        expect(res.isBlocked, isTrue, reason: 'Failed to block payment selector: $sel');
        expect(res.confirmationToken, isNotNull);
      }

      // Test Arabic payment text
      final arabicTexts = [
        'ادفع الآن',
        'إتمام الدفع',
        'إتمام الشراء',
        'تأكيد الطلب',
        'سداد المبلغ',
      ];

      for (final txt in arabicTexts) {
        final res = BrowserSecurityInterceptor.inspectClickAction(
          currentUrl: 'https://souq.com/cart',
          selector: 'button.action-btn',
          elementText: txt,
        );

        expect(res.isBlocked, isTrue, reason: 'Failed to block Arabic payment text: $txt');
      }
    });

    test('5. Credit card and CVV field inputs are intercepted and require confirmation', () {
      // Sensitive selector check
      final resCard = BrowserSecurityInterceptor.inspectFillAction(
        currentUrl: 'https://store.com/billing',
        selector: '#credit-card-number',
        text: '1234',
      );
      expect(resCard.isBlocked, isTrue);

      final resCvv = BrowserSecurityInterceptor.inspectFillAction(
        currentUrl: 'https://store.com/billing',
        selector: 'input[name="cvv"]',
        text: '999',
      );
      expect(resCvv.isBlocked, isTrue);

      // Card number digit pattern check (16 digits)
      final resDigits = BrowserSecurityInterceptor.inspectFillAction(
        currentUrl: 'https://store.com/checkout',
        selector: '#random-field',
        text: '4111 2222 3333 4444',
      );
      expect(resDigits.isBlocked, isTrue);
    });

    test('6. Single-use confirmation token workflow allows authorized action and is consumed once', () {
      // 1. Initial click is blocked and yields a token
      final initialRes = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://checkout.stripe.com/pay',
        selector: '#pay-btn',
        elementText: 'Pay \$99',
      );
      expect(initialRes.isBlocked, isTrue);
      final token = initialRes.confirmationToken!;
      expect(token, isNotEmpty);

      // 2. Unapproved token still gets blocked
      final unapprovedRes = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://checkout.stripe.com/pay',
        selector: '#pay-btn',
        confirmationToken: token,
      );
      expect(unapprovedRes.isBlocked, isTrue);

      // 3. User explicitly approves
      final authOk = BrowserSecurityInterceptor.authorizeConfirmationToken(token);
      expect(authOk, isTrue);

      // 4. Approved token succeeds
      final approvedRes = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://checkout.stripe.com/pay',
        selector: '#pay-btn',
        confirmationToken: token,
      );
      expect(approvedRes.isBlocked, isFalse);
      expect(approvedRes.usedConfirmationToken, isTrue);

      // 5. Token is consumed — subsequent reuse is strictly blocked (single-use)
      final replayedRes = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://checkout.stripe.com/pay',
        selector: '#pay-btn',
        confirmationToken: token,
      );
      expect(replayedRes.isBlocked, isTrue);
    });

    test('7. Explicit user confirmation via chat ("نعم", "أكد") authorizes pending tokens', () {
      // Intercept action
      final res = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://shop.com/checkout',
        selector: '#confirm-order',
        elementText: 'Confirm and Pay',
      );
      expect(res.isBlocked, isTrue);

      // User says "نعم، أؤكد الدفع"
      final handled = BrowserSecurityInterceptor.handleUserChatConfirmationOrRejection('نعم، أؤكد الدفع');
      expect(handled, isTrue);

      // Subsequent click on the exact action now succeeds automatically
      final allowedRes = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://shop.com/checkout',
        selector: '#confirm-order',
      );
      expect(allowedRes.isBlocked, isFalse);
      expect(allowedRes.usedConfirmationToken, isTrue);
    });

    test('8. Explicit user rejection via chat ("لا", "إلغاء") invalidates pending tokens', () {
      final res = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://shop.com/checkout',
        selector: '#confirm-order',
        elementText: 'Confirm and Pay',
      );
      expect(res.isBlocked, isTrue);

      // User says "إلغاء، لا تكمل"
      BrowserSecurityInterceptor.handleUserChatConfirmationOrRejection('إلغاء، لا تكمل');

      // Subsequent click remains blocked
      final blockedAgain = BrowserSecurityInterceptor.inspectClickAction(
        currentUrl: 'https://shop.com/checkout',
        selector: '#confirm-order',
      );
      expect(blockedAgain.isBlocked, isTrue);
    });
  });
}
