import 'package:flutter/material.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_record.dart';
import 'package:khwarizmi/features/skills/domain/entities/text_skill.dart';
import 'package:khwarizmi/features/skills/presentation/widgets/skill_approval_dialog.dart';
import 'package:khwarizmi/features/skills/services/skill_service.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';

/// شاشة / نافذة حوار مخصصة لإدارة الـ Skills الخارجية (التنفيذية والنصية) بالكامل
class SkillsSettingsDialog extends StatefulWidget {
  const SkillsSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const SkillsSettingsDialog(),
    );
  }

  @override
  State<SkillsSettingsDialog> createState() => _SkillsSettingsDialogState();
}

class _SkillsSettingsDialogState extends State<SkillsSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Executive Skills
  List<SkillRecord> _skills = [];
  bool _isLoadingSkills = true;
  bool _isRescanningSkills = false;

  // Text Skills
  List<TextSkill> _textSkills = [];
  bool _isLoadingTextSkills = true;
  bool _isRescanningTextSkills = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadSkills(), _loadTextSkills()]);
  }

  Future<void> _loadSkills() async {
    setState(() => _isLoadingSkills = true);
    final skills = await SkillService.instance.scanAndDiscoverSkills();
    if (mounted) {
      setState(() {
        _skills = skills;
        _isLoadingSkills = false;
      });
    }
  }

  Future<void> _loadTextSkills() async {
    setState(() => _isLoadingTextSkills = true);
    final textSkills = await TextSkillService.instance.scanAndDiscoverTextSkills();
    if (mounted) {
      setState(() {
        _textSkills = textSkills;
        _isLoadingTextSkills = false;
      });
    }
  }

  Future<void> _rescanSkills() async {
    setState(() => _isRescanningSkills = true);
    final skills = await SkillService.instance.scanAndDiscoverSkills();
    if (mounted) {
      setState(() {
        _skills = skills;
        _isRescanningSkills = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم مسح مجلد الإضافات التنفيذية بنجاح (وُجد ${_skills.length} مهارة).'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _rescanTextSkills() async {
    setState(() => _isRescanningTextSkills = true);
    final textSkills = await TextSkillService.instance.scanAndDiscoverTextSkills();
    if (mounted) {
      setState(() {
        _textSkills = textSkills;
        _isRescanningTextSkills = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم مسح مجلد المهارات النصية بنجاح (وُجد ${_textSkills.length} مهارة).'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleSkill(SkillRecord record, bool enable) async {
    if (enable) {
      if (!record.isApproved) {
        final approved = await SkillApprovalDialog.show(context, record.manifest);
        if (approved) {
          await _loadSkills();
        }
      } else {
        await SkillService.instance.approveAndEnableSkill(record.manifest.name);
        await _loadSkills();
      }
    } else {
      await SkillService.instance.disableSkill(record.manifest.name);
      await _loadSkills();
    }
  }

  Future<void> _toggleTextSkill(TextSkill skill, bool enable) async {
    await TextSkillService.instance.toggleSkill(skill.name, enable);
    await _loadTextSkills();
  }

  Future<void> _confirmDelete(SkillRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف الـ Skill "${record.manifest.displayName}"؟'),
        content: Text(
          'سيتم إيقاف الأداة وإزالتها نهائياً من قائمة الأدوات وحذف مجلدها من القرص:\n${record.manifest.folderPath}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SkillService.instance.deleteSkill(record.manifest.name);
      await _loadSkills();
    }
  }

  Future<void> _confirmDeleteTextSkill(TextSkill skill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف المهارة النصية "${skill.name}"؟'),
        content: Text(
          'سيتم حذف ملف التعليمات وإزالتها من الفهرس الخفيف تماماً:\n${skill.filePath}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await TextSkillService.instance.deleteSkill(skill.name);
      await _loadTextSkills();
    }
  }

  void _showTextSkillContent(TextSkill skill) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('دليل التعليمات: ${skill.name}'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  skill.description,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.teal),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                SelectableText(
                  skill.content,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Container(
        width: 700,
        height: 640,
        padding: const EdgeInsets.all(DesignTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الشريط العلوي
            Row(
              children: [
                Icon(Icons.extension_outlined, size: 22, color: primaryTextColor),
                const SizedBox(width: DesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إدارة الإضافات والـ Skills',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeLg,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'توسيع قدرات خوارزمي: إضافات تنفيذية (Sidecars) ومهارات نصية إرشادية (Text Skills)',
                        style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  icon: Icon(Icons.close_rounded, color: secondaryTextColor, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: DesignTokens.space12),

            // شريط التبويبات (Tabs)
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.code_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text('الإضافات التنفيذية (${_skills.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.description_outlined, size: 16),
                      const SizedBox(width: 8),
                      Text('المهارات النصية (${_textSkills.length})'),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: DesignTokens.space12),

            // محتوى التبويبات
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Executive Skills
                  _buildExecutiveSkillsTab(isDark, primaryTextColor, secondaryTextColor, borderColor),
                  // Tab 2: Text Skills
                  _buildTextSkillsTab(isDark, primaryTextColor, secondaryTextColor, borderColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveSkillsTab(
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderColor,
  ) {
    final surfaceColor = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;

    return Column(
      children: [
        // شريط الأزرار للتبويب الأول
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _isRescanningSkills ? null : _rescanSkills,
              icon: _isRescanningSkills
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('إعادة مسح المجلد', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => SkillService.instance.openSkillsFolder(),
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('فتح مجلد Skills', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _isLoadingSkills
              ? const Center(child: CircularProgressIndicator())
              : _skills.isEmpty
                  ? _buildEmptyState(
                      'لا توجد إضافات تنفيذية مثبتة',
                      'ضع مجلد الإضافة مع manifest.json في %APPDATA%\\Khwarizmi\\Skills',
                      () => SkillService.instance.openSkillsFolder(),
                      secondaryTextColor,
                      primaryTextColor,
                    )
                  : ListView.separated(
                      itemCount: _skills.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: DesignTokens.space12),
                      itemBuilder: (ctx, i) => _buildSkillCard(
                        _skills[i],
                        isDark,
                        primaryTextColor,
                        secondaryTextColor,
                        surfaceColor,
                        borderColor,
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildTextSkillsTab(
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderColor,
  ) {
    final surfaceColor = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;

    return Column(
      children: [
        // شريط الأزرار للتبويب الثاني
        Row(
          children: [
            Expanded(
              child: Text(
                'تُحقن كفهرس خفيف دائم، وتُحمّل التعليمات كاملة فقط عند الحاجة.',
                style: TextStyle(fontSize: 11, color: secondaryTextColor),
              ),
            ),
            TextButton.icon(
              onPressed: _isRescanningTextSkills ? null : _rescanTextSkills,
              icon: _isRescanningTextSkills
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('إعادة مسح', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => TextSkillService.instance.openTextSkillsFolder(),
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('فتح مجلد TextSkills', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _isLoadingTextSkills
              ? const Center(child: CircularProgressIndicator())
              : _textSkills.isEmpty
                  ? _buildEmptyState(
                      'لا توجد مهارات نصية مثبتة',
                      'أنشئ مجلداً مع ملف SKILL.md فيه frontmatter في %APPDATA%\\Khwarizmi\\TextSkills',
                      () => TextSkillService.instance.openTextSkillsFolder(),
                      secondaryTextColor,
                      primaryTextColor,
                    )
                  : ListView.separated(
                      itemCount: _textSkills.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: DesignTokens.space12),
                      itemBuilder: (ctx, i) => _buildTextSkillCard(
                        _textSkills[i],
                        isDark,
                        primaryTextColor,
                        secondaryTextColor,
                        surfaceColor,
                        borderColor,
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    String title,
    String subtitle,
    VoidCallback onOpenFolder,
    Color secondaryTextColor,
    Color primaryTextColor,
  ) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.extension_off_outlined, size: 44, color: secondaryTextColor.withValues(alpha: 0.5)),
            const SizedBox(height: DesignTokens.space12),
            Text(
              title,
              style: TextStyle(fontSize: DesignTokens.fontSizeBase, fontWeight: FontWeight.w600, color: primaryTextColor),
            ),
            const SizedBox(height: DesignTokens.space8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: secondaryTextColor, height: 1.4),
            ),
            const SizedBox(height: DesignTokens.space16),
            ElevatedButton.icon(
              onPressed: onOpenFolder,
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('فتح المجلد في Windows Explorer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillCard(
    SkillRecord record,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color surfaceColor,
    Color borderColor,
  ) {
    final m = record.manifest;
    final isEnabled = record.isEnabled;
    final isApproved = record.isApproved;

    Color statusColor;
    String statusText;
    if (!isApproved) {
      statusColor = Colors.amber;
      statusText = 'بانتظار الموافقة';
    } else if (isEnabled) {
      statusColor = Colors.green;
      statusText = 'مفعّل';
    } else {
      statusColor = Colors.grey;
      statusText = 'معطّل';
    }

    return Container(
      padding: const EdgeInsets.all(DesignTokens.space16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
          color: isEnabled ? Colors.teal.withValues(alpha: 0.4) : borderColor,
          width: isEnabled ? 1.5 : DesignTokens.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                m.displayName,
                style: TextStyle(fontSize: DesignTokens.fontSizeBase, fontWeight: FontWeight.w600, color: primaryTextColor),
              ),
              const SizedBox(width: DesignTokens.space8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  m.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: DesignTokens.fontFamilyMono,
                    fontFamilyFallback: DesignTokens.monoFallbacks,
                    color: secondaryTextColor,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.space8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
                ),
              ),
              const Spacer(),
              Switch(
                value: isEnabled,
                onChanged: (val) => _toggleSkill(record, val),
              ),
              IconButton(
                tooltip: 'إزالة الأداة وحذفها من القرص',
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.shade400),
                onPressed: () => _confirmDelete(record),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.space8),
          Text(
            m.description,
            style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: secondaryTextColor, height: 1.35),
          ),
          const SizedBox(height: DesignTokens.space12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_rounded, size: 12, color: secondaryTextColor),
                    const SizedBox(width: 4),
                    Text(
                      m.endpoint,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: DesignTokens.fontFamilyMono,
                        fontFamilyFallback: DesignTokens.monoFallbacks,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              for (final perm in m.permissions)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '🔒 $perm',
                    style: const TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.w500),
                  ),
                ),
              if (m.startCommand != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '⚡ ${m.startCommand}',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: DesignTokens.fontFamilyMono,
                      fontFamilyFallback: DesignTokens.monoFallbacks,
                      color: isDark ? Colors.purpleAccent.shade100 : Colors.purple.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextSkillCard(
    TextSkill skill,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color surfaceColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.space16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
          color: skill.isEnabled ? Colors.blue.withValues(alpha: 0.4) : borderColor,
          width: skill.isEnabled ? 1.5 : DesignTokens.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  skill.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: DesignTokens.fontFamilyMono,
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: skill.isEnabled ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  skill.isEnabled ? 'مفعّل بالفهرس' : 'معطّل',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: skill.isEnabled ? Colors.green : Colors.grey,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showTextSkillContent(skill),
                icon: const Icon(Icons.visibility_outlined, size: 14),
                label: const Text('عرض الإرشادات', style: TextStyle(fontSize: 11)),
              ),
              Switch(
                value: skill.isEnabled,
                onChanged: (val) => _toggleTextSkill(skill, val),
              ),
              IconButton(
                tooltip: 'حذف المهارة النصية',
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.shade400),
                onPressed: () => _confirmDeleteTextSkill(skill),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            skill.description,
            style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: primaryTextColor, height: 1.35),
          ),
        ],
      ),
    );
  }
}
