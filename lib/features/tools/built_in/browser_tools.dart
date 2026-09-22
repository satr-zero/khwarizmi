import 'dart:convert';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/browser/services/agent_browser_service.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

/// Tool to navigate to a URL using the dedicated agent browser and extract
/// clean readable content and interactive elements.
class BrowseUrlTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'browse_url',
        description:
            'Opens a website in Khwarizmi\'s dedicated isolated browser and extracts a clean, structured summary of its visible text, headings, and interactive elements without raw HTML bloat.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'url': {
              'type': 'STRING',
              'description': 'The web URL to open and read (e.g. https://example.com)',
            },
          },
          'required': ['url'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final url = arguments['url']?.toString();
    if (url == null || url.trim().isEmpty) {
      return jsonEncode({'error': 'رابط الموقع (url) مطلوب'});
    }
    return await AgentBrowserService.instance.browseUrl(url.trim());
  }
}

/// Tool to click a clickable element on the current browser page.
/// Supports clicking by CSS selector or by visible text with live visual click beacon.
/// Enforces the programmatic Payment Security Barrier.
class ClickElementTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'click_element',
        description:
            'Clicks an element on the currently open web page using a CSS selector (e.g., #submit-btn, .action-link, button) or by its visible text label (e.g. "تسجيل الدخول", "Search", "Next"). Shows a live visual click ripple in the browser. Sensitive actions like payment or checkout are intercepted until user confirmation.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'selector': {
              'type': 'STRING',
              'description': 'CSS selector of the target element (e.g., #search-button, a.nav-link, button[type="submit"])',
            },
            'text': {
              'type': 'STRING',
              'description': 'Optional visible text of the button or link to click (e.g. "بحث", "تسجيل", "Read more")',
            },
            'confirmation_token': {
              'type': 'STRING',
              'description':
                  'Optional single-use token provided when user has explicitly approved a previously intercepted payment/sensitive action',
            },
          },
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final selector = arguments['selector']?.toString() ?? '';
    final text = arguments['text']?.toString();
    if (selector.trim().isEmpty && (text == null || text.trim().isEmpty)) {
      return jsonEncode({'error': 'يجب تحديد معرّف العنصر (selector) أو النص الظاهر عليه (text) للنقر'});
    }
    final token = arguments['confirmation_token']?.toString();
    return await AgentBrowserService.instance.clickElement(
      selector.trim(),
      text: text?.trim(),
      confirmationToken: token,
    );
  }
}

/// Tool to smoothly scroll the browser page and see new content.
class ScrollPageTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'scroll_page',
        description:
            'Smoothly scrolls the current open web page in the live browser view in front of the user. Can scroll "down", "up", "top", "bottom", by pixel amount, or scroll a specific element into view. Returns the new scroll position, visible headings, and visible interactive elements.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'direction': {
              'type': 'STRING',
              'description': 'Direction to scroll: "down" (default), "up", "top", or "bottom"',
            },
            'amount': {
              'type': 'INTEGER',
              'description': 'Number of pixels to scroll (default 500), or you can pass "half_page" or "full_page"',
            },
            'selector': {
              'type': 'STRING',
              'description': 'Optional CSS selector of an element to scroll directly into the center of the viewport',
            },
          },
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final direction = arguments['direction']?.toString() ?? 'down';
    final amount = arguments['amount'] ?? 500;
    final selector = arguments['selector']?.toString();

    return await AgentBrowserService.instance.scrollPage(
      direction: direction,
      amount: amount,
      selector: selector,
    );
  }
}

/// Tool to visually inspect page layout, colors, dark/light theme, and visible shapes.
class InspectVisualPageTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'inspect_visual_page',
        description:
            'Visually inspects the current open web page in the agent browser. Reports colors (background, text, accent colors, dark/light mode), viewport dimensions, scroll progress, and visible buttons with their visual shapes (pill, rounded, rectangular) and positions.',
        parameters: {
          'type': 'OBJECT',
          'properties': {},
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    return await AgentBrowserService.instance.inspectVisualPage();
  }
}

/// Tool to fill text into an input field on the current browser page.
/// Enforces the programmatic Payment Security Barrier on sensitive financial fields.
class FillInputTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'fill_input',
        description:
            'Fills text into an input field on the currently open web page using a CSS selector or input name. Highlights the field with a live blue focus glow in the browser. Sensitive card details are intercepted by the security barrier.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'selector': {
              'type': 'STRING',
              'description': 'CSS selector or name of the target input element (e.g., #username, input[name="q"], textarea)',
            },
            'text': {
              'type': 'STRING',
              'description': 'Text content to type into the input field',
            },
            'confirmation_token': {
              'type': 'STRING',
              'description': 'Optional single-use authorization token if user confirmed filling sensitive data',
            },
          },
          'required': ['selector', 'text'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final selector = arguments['selector']?.toString();
    final text = arguments['text']?.toString();
    if (selector == null || selector.trim().isEmpty) {
      return jsonEncode({'error': 'محدد الحقل (selector) مطلوب'});
    }
    if (text == null) {
      return jsonEncode({'error': 'النص المراد إدخاله (text) مطلوب'});
    }
    final token = arguments['confirmation_token']?.toString();
    return await AgentBrowserService.instance.fillInput(
      selector.trim(),
      text,
      confirmationToken: token,
    );
  }
}

/// Tool to download a file from a URL to the dedicated download folder.
class DownloadFileTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'download_file',
        description:
            'Downloads a file from a web URL and saves it strictly inside Khwarizmi\'s dedicated downloads folder (%USERPROFILE%\\Downloads\\Khwarizmi\\). Verifies disk completion before responding.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'url': {
              'type': 'STRING',
              'description': 'Direct URL of the file to download',
            },
          },
          'required': ['url'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final url = arguments['url']?.toString();
    if (url == null || url.trim().isEmpty) {
      return jsonEncode({'error': 'رابط الملف المراد تحميله (url) مطلوب'});
    }
    return await AgentBrowserService.instance.downloadFile(url.trim());
  }
}
