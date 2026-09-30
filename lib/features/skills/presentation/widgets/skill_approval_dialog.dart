import 'package:flutter/material.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';
import 'package:khwarizmi/features/skills/services/skill_service.dart';

/// نافذة حوار للموافقة الصريحة والإلزامية عند اكتشاف Skill خارجي جديد لأول مرة.
class SkillApprovalDialog extends StatelessWidget {
  final SkillManifest manifest;

  const SkillApprovalDialog({super.key, required this.manifest});

  /// عرض النافذة كـ Modal Dialog
  static Future<bool> show(BuildContext context, SkillManifest manifest) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SkillApprovalDialog(manifest: manifest),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final surfaceColor = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(DesignTokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان والأيقونة
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(DesignTokens.space8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: const Icon(Icons.extension_rounded, color: Colors.amber, size: 24),
                ),
                const SizedBox(width: DesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إضافة مهارة خارجية جديدة (Skill)',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeBase,
                          fontWeight: FontWeight.w700,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'تم اكتشاف أداة غير مدمجة تتطلب موافقتك الصريحة قبل التفعيل',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: DesignTokens.space16),
            Divider(color: borderColor, height: DesignTokens.hairline),
            const SizedBox(height: DesignTokens.space16),

            // تفاصيل الأداة
            Container(
              padding: const EdgeInsets.all(DesignTokens.space12),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: borderColor, width: DesignTokens.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        manifest.displayName,
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeBase,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.space8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          manifest.name,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: DesignTokens.fontFamilyMono,
                            fontFamilyFallback: DesignTokens.monoFallbacks,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'v${manifest.version}',
                        style: TextStyle(
                          fontSize: 11,
                          color: secondaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.space8),
                  Text(
                    manifest.description,
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      color: primaryTextColor,
                      height: 1.4,
                    ),
                  ),
                  if (manifest.startCommand != null) ...[
                    const SizedBox(height: DesignTokens.space8),
                    Row(
                      children: [
                        Icon(Icons.terminal_rounded, size: 14, color: secondaryTextColor),
                        const SizedBox(width: 4),
                        Text(
                          'أمر التشغيل التلقائي: ',
                          style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                        ),
                        Expanded(
                          child: Text(
                            manifest.startCommand!,
                            style: TextStyle(
                              fontSize: DesignTokens.fontSizeXs,
                              fontFamily: DesignTokens.fontFamilyMono,
                              fontFamilyFallback: DesignTokens.monoFallbacks,
                              color: isDark ? Colors.cyanAccent : Colors.blue.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: DesignTokens.space16),

            // الصلاحيات المطلوبة بتوضيح بالعربية
            Text(
              'الصلاحيات المطلوبة (Permissions):',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeSm,
                fontWeight: FontWeight.w600,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: DesignTokens.space8),
            _buildPermissionsList(context, manifest.permissions, isDark),

            const SizedBox(height: DesignTokens.space16),

            // تنبيه أمني
            Container(
              padding: const EdgeInsets.all(DesignTokens.space12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.amber, size: 18),
                  const SizedBox(width: DesignTokens.space8),
                  Expanded(
                    child: Text(
                      'تنبيه أمني: يتم تشغيل الـ Skills كعملية خارجية مستقلة (Sidecar). لا توافق على تفعيل أي أداة إلا إذا كنت تثق بمصدر الكود وملفاته.',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: DesignTokens.space20),

            // الأزرار
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'تجاهل (إبقاء معطّل)',
                    style: TextStyle(color: secondaryTextColor, fontSize: DesignTokens.fontSizeSm),
                  ),
                ),
                const SizedBox(width: DesignTokens.space12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final approved = await SkillService.instance.approveAndEnableSkill(manifest.name);
                    if (context.mounted) {
                      Navigator.of(context).pop(approved);
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text('تفعيل الأداة الآن'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.space16,
                      vertical: DesignTokens.space12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsList(BuildContext context, List<String> permissions, bool isDark) {
    if (permissions.isEmpty) {
      return Row(
        children: [
          Icon(Icons.check_rounded, size: 14, color: Colors.green.shade400),
          const SizedBox(width: 6),
          Text(
            'لا تتطلب الأداة صلاحيات نظام خاصة.',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight,
            ),
          ),
        ],
      );
    }

    return Column(
      children: permissions.map((perm) {
        final info = _getPermissionInfo(perm);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(info.icon, size: 15, color: info.color),
              const SizedBox(width: 8),
              Text(
                info.title,
                style: const TextStyle(fontSize: DesignTokens.fontSizeXs, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Text(
                '— ${info.description}',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static _PermissionInfo _getPermissionInfo(String rawPerm) {
    switch (rawPerm.toLowerCase()) {
      case 'network':
      case 'internet':
        return _PermissionInfo(
          title: 'الشبكة والإنترنت',
          description: 'إجراء اتصالات خارجية عبر الشبكة والإنترنت',
          icon: Icons.language_rounded,
          color: Colors.blueAccent,
        );
      case 'filesystem':
      case 'files':
        return _PermissionInfo(
          title: 'نظام الملفات',
          description: 'قراءة أو كتابة وتعديل الملفات على جهازك',
          icon: Icons.folder_open_rounded,
          color: Colors.amberAccent.shade700,
        );
      case 'browser':
        return _PermissionInfo(
          title: 'التحكم بالمتصفح',
          description: 'التنقل في صفحات الويب والتفاعل مع عناصرها',
          icon: Icons.open_in_browser_rounded,
          color: Colors.purpleAccent,
        );
      default:
        return _PermissionInfo(
          title: rawPerm,
          description: 'صلاحية إضافية خاصة بالأداة',
          icon: Icons.security_rounded,
          color: Colors.teal,
        );
    }
  }
}

class _PermissionInfo {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  _PermissionInfo({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
