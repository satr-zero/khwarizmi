import 'package:flutter/material.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';

/// منظومة الأوضاع الخمسة لخوارزمي (The 5-Mode System)
///
/// 1. manager: [مدير] — تنسيق كامل وإشراف على دورة الحياة (تخطيط -> كود -> إصلاح أخطاء)
/// 2. planner: [تخطيط] — قراءة وبحث وتحليل معماري وتقسيم لخطوات ذرية فقط دون أي كتابة
/// 3. code: [كود] — تنفيذ الخطوات المعتمدة، كتابة وتعديل وتشغيل أوامر
/// 4. debug: [إصلاح أخطاء] — تشخيص دقيق وإصلاح مباشر للأخطاء الناتجة عن وضع الكود
/// 5. inquiry: [استفسار] — وضع استفسار آمن بالكامل وقراءة فقط دون أي تعديل أو تنفيذ إطلاقاً
enum CodingMode {
  manager,
  planner,
  code,
  debug,
  inquiry,
}

/// تكوين كل نمط برمجي
class CodingModeConfig {
  final CodingMode mode;
  final String label;
  final String iconName; // اسم الأيقونة من Material Icons
  final String description;
  final Set<String> allowedToolPrefixes; // بادئات أسماء الأدوات المسموحة
  final String systemPromptAddendum; // توجيه سلوكي للـ system prompt

  /// هل يمكن للمستخدم اختياره يدوياً كبداية مهمة؟
  /// الأوضاع المتاحة للبدء اليدوي: [مدير]، [تخطيط]، [استفسار]
  /// أما [كود] و [إصلاح أخطاء] فيُستدعيان فقط تلقائياً من المدير أو من زر "تنفيذ" في التخطيط.
  final bool isUserSelectableInitial;

  /// قائمة الصلاحيات المعروضة في الواجهة
  final List<CodingModePermission> permissions;

  /// اللون المميز للنمط في الواجهة
  final Color accentColor;

  const CodingModeConfig({
    required this.mode,
    required this.label,
    required this.iconName,
    required this.description,
    required this.allowedToolPrefixes,
    required this.systemPromptAddendum,
    this.isUserSelectableInitial = true,
    this.permissions = const [],
    this.accentColor = const Color(0xFF6366F1),
  });
}

/// صلاحية واحدة تُعرض في الواجهة
class CodingModePermission {
  final String label;
  final bool allowed;
  final IconData icon;

  const CodingModePermission({
    required this.label,
    required this.allowed,
    required this.icon,
  });
}

/// خريطة التكوينات لجميع الأنماط الخمسة
final Map<CodingMode, CodingModeConfig> codingModeConfigs = {
  // ── 1. وضع [مدير] — Manager Mode ──────────────────────────────────────────
  CodingMode.manager: CodingModeConfig(
    mode: CodingMode.manager,
    label: 'مدير',
    iconName: 'hub',
    description: 'تنسيق وإدارة المهام — التخطيط والتنفيذ وإصلاح الأخطاء التلقائي',
    isUserSelectableInitial: true,
    accentColor: const Color(0xFF6366F1),
    allowedToolPrefixes: {
      'read_', 'list_', 'refresh_', 'search_', 'store_', 'load_',
      'web_', 'fetch_', 'start_autonomous_task', 'resume_task',
      'ask_user', 'report_progress', 'complete_task',
    },
    permissions: [
      CodingModePermission(label: 'تنسيق وإدارة المهام', allowed: true, icon: Icons.hub_rounded),
      CodingModePermission(label: 'التحويل التلقائي للأوضاع', allowed: true, icon: Icons.auto_awesome_rounded),
      CodingModePermission(label: 'قراءة واستكشاف المشروع', allowed: true, icon: Icons.folder_open_rounded),
      CodingModePermission(label: 'كتابة وتعديل الكود مباشرة', allowed: false, icon: Icons.edit_off_rounded),
      CodingModePermission(label: 'تشغيل أوامر الطرفية', allowed: false, icon: Icons.terminal_rounded),
    ],
    systemPromptAddendum: '''
أنت الآن في وضع "المدير" داخل خوارزمي. مهمتك الوحيدة هي التنسيق، لا التنفيذ المباشر.

صلاحياتك:
- تحليل طلب المستخدم وتحديد ما إذا كان يحتاج تخطيطاً (أكثر من خطوة، أو تعديل/إنشاء أكثر من ملف، أو قرار معماري) أو تنفيذاً مباشراً بسيطاً.
- عند الحاجة للتقسيم: استدعِ أداة start_autonomous_task(goal=...) فوراً بالهدف كاملاً — النظام يتولى بناء الخطة وعرضها على المستخدم للاعتماد.
- التنقل بين الأوضاع يديره النظام تلقائياً: عند اعتماد المستخدم للخطة ينتقل النظام لوضع [كود] ويبدأ التنفيذ، وعند الاكتمال يعود لوضع [مدير]. لا تعلن أنت انتقالات من عندك — سردك لجمل مثل "جارٍ التحويل لوضع كود" غير حقيقي وممنوع.
- إذا فشلت خطوة أثناء التنفيذ المستقل: النظام يعرض الخطأ على المستخدم ويسأله تلقائياً عن قرار المتابعة — لا تسأله بنفسك ولا تعلن دخولاً لوضع [إصلاح أخطاء].
- بعد إتمام كل خطوات الخطة، يعرض النظام الملخص النهائي تلقائياً — علّق على النتيجة بلغة المستخدم إن سُئلت.

ممنوع عليك:
- تنفيذ كود أو تعديل ملفات مباشرة من هذا الوضع — هذا حصراً عمل وضع [كود] ومحرك التنفيذ المستقل.
- سؤال المستخدم "أي وضع تريد؟" أو "هل أخطط؟" — أنت من يقرر عبر استدعاء الأداة مباشرة.
- الوعود بتنفيذ أو سرد انتقالات أو إعلان خطوات قادمة كنص — استدعِ الأداة فقط.
''',
  ),

  // ── 2. وضع [تخطيط] — Planning Mode ────────────────────────────────────────
  CodingMode.planner: CodingModeConfig(
    mode: CodingMode.planner,
    label: 'تخطيط',
    iconName: 'architecture',
    description: 'تحليل المتطلبات وهندسة الخطط الذرية — قراءة وبحث فقط دون تعديل',
    isUserSelectableInitial: true,
    accentColor: const Color(0xFF0EA5E9),
    allowedToolPrefixes: {
      'read_', 'list_', 'refresh_', 'search_', 'store_', 'load_',
      'web_', 'fetch_',
    },
    permissions: [
      CodingModePermission(label: 'قراءة ملفات وبنية المشروع', allowed: true, icon: Icons.folder_open_rounded),
      CodingModePermission(label: 'البحث والتوثيق', allowed: true, icon: Icons.search_rounded),
      CodingModePermission(label: 'تقسيم الخطوات الذرية وإبراز القرارات', allowed: true, icon: Icons.schema_rounded),
      CodingModePermission(label: 'تعديل أو إنشاء ملفات', allowed: false, icon: Icons.edit_off_rounded),
      CodingModePermission(label: 'تشغيل أوامر الطرفية', allowed: false, icon: Icons.terminal_rounded),
    ],
    systemPromptAddendum: '''
أنت الآن في وضع "التخطيط" داخل خوارزمي. مهمتك تحليل الطلب وإنتاج خطة تنفيذ واضحة فقط — دون أي تنفيذ أو تعديل أو إنشاء ملفات إطلاقاً.

صلاحياتك:
- قراءة الملفات والبحث في بنية وكود المشروع (أدوات القراءة والبحث: search_project_code, read_project_file, list_project_files, refresh_project_map).
- البحث على الإنترنت عند الحاجة لمعرفة تقنية (توثيق مكتبة، إلخ).
- تقسيم الطلب إلى خطوات ذرية مرقّمة بلغة المستخدم، كل خطوة بجملة واحدة واضحة.
- إبراز أي قرار معماري مفصلي كسطر صريح منفصل ضمن الخطة (وليس مدفوناً بالتفكير الداخلي) — مثال: "قرار: سيُنشأ مجلد/حزمة منفصلة بدل التعديل داخل الحزمة الأصلية، للأسباب التالية: ...".

ممنوع عليك تماماً:
- استدعاء أي أداة من فئة الكتابة أو التنفيذ (propose_file_change, propose_file_patch, run_terminal_command, write_file).
- الانتقال لأي وضع آخر تلقائياً. أنت وضع نهائي بذاته عند الاستدعاء المباشر من المستخدم.

عند إنتاج الخطة، اعرضها مرتبة وواضحة فقط. لا تكتب أزراراً أو أوامر نصية وهمية مثل "[تنفيذ بوضع الكود]" — الواجهة لا تحوّل النص إلى زر.

إن كانت الخطة معروضة عبر بطاقة خطة العمل الرسمية، فزر «تنفيذ بوضع الكود» يظهر تلقائياً في البطاقة نفسها، وعند اعتماده ينفّذ النظام الخطة ذاتها دون إعادة تخطيط.

إن طلب المستخدم تنفيذ الخطة وأنت في وضع [تخطيط]، أخبره أن التنفيذ يجري عبر وضع [مدير] — لا تنفذ من هذا الوضع.
''',
  ),

  // ── 3. وضع [كود] — Code Mode ──────────────────────────────────────────────
  CodingMode.code: CodingModeConfig(
    mode: CodingMode.code,
    label: 'كود',
    iconName: 'code',
    description: 'تنفيذ الخطوات المعتمدة — كتابة وتعديل وتشغيل أوامر',
    isUserSelectableInitial: true, // متاح للاختيار المباشر من المستخدم
    accentColor: const Color(0xFF10B981),
    allowedToolPrefixes: {
      'read_', 'write_', 'list_', 'run_', 'propose_', 'refresh_',
      'search_', 'browse_', 'click_', 'scroll_', 'inspect_',
      'fill_', 'download_', 'store_', 'load_', 'web_', 'fetch_',
      'deliver_', 'report_progress', 'ask_user', 'complete_task',
    },
    permissions: [
      CodingModePermission(label: 'قراءة وكتابة وتعديل الملفات', allowed: true, icon: Icons.edit_rounded),
      CodingModePermission(label: 'تشغيل أوامر الطرفية', allowed: true, icon: Icons.terminal_rounded),
      CodingModePermission(label: 'اقتراح التعديلات (Diff)', allowed: true, icon: Icons.rate_review_rounded),
      CodingModePermission(label: 'قفل واجهة المشروع أثناء التنفيذ', allowed: true, icon: Icons.lock_clock_rounded),
      CodingModePermission(label: 'تسليم وضع إصلاح الأخطاء عند العطل', allowed: true, icon: Icons.bug_report_rounded),
    ],
    systemPromptAddendum: '''
أنت الآن في وضع "الكود" داخل خوارزمي. مهمتك تنفيذ خطوة أو خطوات محددة من خطة معتمدة مسبقاً (من وضع تخطيط أو مدير).

صلاحياتك:
- أدوات البحث والكتابة والتعديل: search_project_code (لإيجاد مواقع الرموز قبل التعديل)، propose_file_change, propose_file_patch, run_terminal_command, write_file, read_project_file, list_project_files.
- تنفيذ الخطوة الحالية من الخطة فقط. لا تُعِد التخطيط ولا تُغيّر ترتيب الخطوات من هذا الوضع.

قواعد صارمة:
- المشروع مقفل منطقياً من واجهة خوارزمي طوال عملك في هذا الوضع — لا تسمح بأي طلب تعديل يدوي من المستخدم عبر الواجهة حتى تنتهي الخطوة الحالية أو تُسلّم التحكم لوضع آخر.
- عند أي خطأ تنفيذ (فشل ترجمة، استثناء، نتيجة أمر غير متوقعة)، لا تحاول إصلاحه بنفسك أكثر من محاولة واحدة سريعة — سلّم فوراً لوضع [إصلاح أخطاء] مع وصف دقيق للخطأ والسياق.
- عند نجاح تنفيذ الخطوة، ارجع الضبط لوضع [مدير] ليقرر الخطوة التالية — لا تُكمل الخطوة التالية من الخطة بنفسك.
- استخدم قوالب الملخص العربية لكل استدعاء أداة — لا تعرض JSON خام للمستخدم.
- عند اقتراح تعديل ملف (diff)، مرّر عدد الأسطر المضافة والمحذوفة بشكل منفصل ليُعرض بواجهة الـ Diff الجديدة.

ممنوع عليك:
- تعديل خطوات الخطة أو حذف/إضافة خطوات جديدة دون العودة لوضع [مدير]/[تخطيط] أولاً.
- الاستمرار بمحاولات إصلاح متكررة لنفس الخطأ (أكثر من محاولة واحدة) دون تسليم لوضع [إصلاح أخطاء].
''',
  ),

  // ── 4. وضع [إصلاح أخطاء] — Debug Mode ─────────────────────────────────────
  CodingMode.debug: CodingModeConfig(
    mode: CodingMode.debug,
    label: 'إصلاح أخطاء',
    iconName: 'bug_report',
    description: 'تشخيص دقيق وحل الأخطاء البرمجية بعد فشل التنفيذ',
    isUserSelectableInitial: false, // يُستدعى تلقائياً عند فشل خطوة في وضع كود
    accentColor: const Color(0xFFF59E0B),
    allowedToolPrefixes: {
      'read_', 'list_', 'run_', 'propose_', 'refresh_',
      'search_', 'store_', 'load_', 'web_', 'fetch_',
      'report_progress', 'ask_user',
    },
    permissions: [
      CodingModePermission(label: 'قراءة وفحص اللوغات والاختبارات', allowed: true, icon: Icons.troubleshoot_rounded),
      CodingModePermission(label: 'تشغيل أوامر الفحص والتحقق', allowed: true, icon: Icons.terminal_rounded),
      CodingModePermission(label: 'تعديل تصحيحي مباشر (Patch)', allowed: true, icon: Icons.healing_rounded),
      CodingModePermission(label: 'التركيز الحصري على الخطأ المُبلّغ', allowed: true, icon: Icons.filter_center_focus_rounded),
      CodingModePermission(label: 'تسليم التحكم للمدير بعد الإصلاح', allowed: true, icon: Icons.keyboard_return_rounded),
    ],
    systemPromptAddendum: '''
أنت الآن في وضع "إصلاح الأخطاء" داخل خوارزمي. استُدعيت لأن وضع [كود] واجه فشلاً أثناء تنفيذ خطوة محددة.

صلاحياتك:
- كل أدوات القراءة والتشخيص والبحث: search_project_code (للبحث عن الرموز واستدعاءات الدوال المتعلقة بالخطأ)، read_project_file, list_project_files, run_terminal_command (للفحص: تشغيل اختبار، فحص لوغ).
- كتابة تعديل تصحيحي مباشر (propose_file_change / propose_file_patch) خاص فقط بإصلاح الخطأ المُبلَّغ عنه.

قواعد صارمة:
- ركّز حصراً على الخطأ المُبلَّغ من وضع [كود]. لا توسّع نطاق العمل لتحسينات أو تعديلات غير متعلقة بالخطأ نفسه.
- بعد الإصلاح، لخّص للمستخدم بجملة واحدة: ما كان الخطأ، وما الذي أُصلح.
- عند نجاح الإصلاح، سلّم الضبط لوضع [مدير] — لا تعد مباشرة لوضع [كود] بنفسك؛ المدير هو من يقرر إكمال الخطوات المتبقية من [كود].
- إذا تكرر نفس الخطأ بعد محاولة الإصلاح، لا تكرر نفس الحل — أبلغ [مدير] بوضوح أن الإصلاح التلقائي غير كافٍ ويحتاج تدخل المستخدم.
''',
  ),

  // ── 5. وضع [استفسار] — Inquiry Mode ───────────────────────────────────────
  CodingMode.inquiry: CodingModeConfig(
    mode: CodingMode.inquiry,
    label: 'استفسار',
    iconName: 'help_outline',
    description: 'استفسار وشرح — قراءة وبحث فقط بأمان تام ودون أي تعديل',
    isUserSelectableInitial: true,
    accentColor: const Color(0xFF8B5CF6),
    allowedToolPrefixes: {
      'read_', 'list_', 'refresh_', 'search_', 'web_', 'fetch_',
      'store_', 'load_',
    },
    permissions: [
      CodingModePermission(label: 'قراءة الملفات والبحث في الكود', allowed: true, icon: Icons.folder_open_rounded),
      CodingModePermission(label: 'البحث على الإنترنت والتصفح', allowed: true, icon: Icons.search_rounded),
      CodingModePermission(label: 'شرح المنطق وتحليل المعمارية', allowed: true, icon: Icons.psychology_rounded),
      CodingModePermission(label: 'كتابة أو تعديل أي ملفات', allowed: false, icon: Icons.edit_off_rounded),
      CodingModePermission(label: 'تشغيل أوامر الطرفية', allowed: false, icon: Icons.terminal_rounded),
    ],
    systemPromptAddendum: '''
أنت الآن في وضع "الاستفسار" داخل خوارزمي. هذا وضع محادثة عادية آمن بالكامل — لا صلاحية تعديل أو تنفيذ إطلاقاً.

صلاحياتك:
- قراءة أي ملف بالمشروع، البحث بالكود (search_project_code, list_project_files, read_project_file, refresh_project_map).
- البحث على الإنترنت (web_search, fetch_url).
- الإجابة على أسئلة تحليلية: شرح كود، مقارنة، اقتراح (كنص فقط دون تنفيذ).

ممنوع عليك تماماً ودون استثناء:
- أي أداة من فئة الكتابة: propose_file_change, propose_file_patch, write_file, run_terminal_command.
- الانتقال لأي وضع آخر تلقائياً تحت أي ظرف.

إذا طلب المستخدم تنفيذاً فعلياً وأنت بهذا الوضع، لا تنفذ ولا تقترح تجاوز القيد — أخبره بوضوح أن هذا يتطلب التحويل لوضع [مدير] أو [تخطيط]، واعرض عليه ذلك كخيار صريح، ولا تفعله نيابة عنه.
''',
  ),
};

/// الأنماط التي يمكن للمستخدم اختيارها يدوياً للبدء
final List<CodingMode> userSelectableInitialModes = CodingMode.values
    .where((m) => codingModeConfigs[m]!.isUserSelectableInitial)
    .toList();

/// خدمة تصفية الأدوات حسب النمط النشط
class ToolFilter {
  /// تصفية قائمة الأدوات للسماح فقط بتلك التي بادئات أسمائها مطابقة للنمط
  static List<ToolDefinition> filterForMode(
    List<ToolDefinition> allTools,
    CodingMode mode,
  ) {
    final config = codingModeConfigs[mode] ?? codingModeConfigs[CodingMode.manager]!;
    final allowedPrefixes = config.allowedToolPrefixes;

    return allTools.where((tool) {
      if (tool.isControlTool) {
        return allowedPrefixes.any((p) => tool.name.startsWith(p));
      }
      return allowedPrefixes.any((prefix) => tool.name.startsWith(prefix));
    }).toList();
  }

  /// التحقق مما إذا كانت أداة محددة مسموحة في النمط الحالي
  static bool isToolAllowed(ToolDefinition tool, CodingMode mode) {
    final config = codingModeConfigs[mode] ?? codingModeConfigs[CodingMode.manager]!;
    final allowedPrefixes = config.allowedToolPrefixes;

    if (tool.isControlTool) {
      return allowedPrefixes.any((p) => tool.name.startsWith(p));
    }
    return allowedPrefixes.any((prefix) => tool.name.startsWith(prefix));
  }
}
