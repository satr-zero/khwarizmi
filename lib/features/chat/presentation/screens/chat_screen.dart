import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/core/theme/theme_controller.dart';
import 'package:khwarizmi/features/agent/presentation/controllers/task_provider.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_controller.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/coding_modes.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/layout_controller.dart';
import 'package:khwarizmi/features/chat/presentation/models/chat_turn.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/settings_dialog.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/model_switcher.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/work_panel.dart';
import 'package:khwarizmi/features/memory/presentation/widgets/memory_viewer_dialog.dart';
import 'package:khwarizmi/features/scheduler/presentation/widgets/reminders_viewer_dialog.dart';
import 'package:khwarizmi/features/skills/presentation/screens/skills_settings_dialog.dart';
import 'package:khwarizmi/features/skills/presentation/widgets/skill_approval_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:khwarizmi/features/projects/presentation/controllers/project_provider.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/skills/services/skill_service.dart';
import 'package:khwarizmi/features/agent/presentation/widgets/live_tasks_hud.dart';
import 'package:khwarizmi/features/agent/presentation/widgets/tasks_panel.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String? _editingMessageId;
  String? _editingOriginalText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingSkills();
    });
  }

  Future<void> _checkPendingSkills() async {
    final pending = await SkillService.instance.getPendingApprovalSkills();
    if (!mounted || pending.isEmpty) return;
    for (final record in pending) {
      if (!mounted) break;
      await SkillApprovalDialog.show(context, record.manifest);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _editingOriginalText = null;
    });
    _inputController.clear();
  }

  void _startEditing(ChatMessage message) {
    final chatState = ref.read(chatProvider);
    if (chatState.isStreaming) {
      ref.read(chatProvider.notifier).stopGeneration();
    }
    setState(() {
      _editingMessageId = message.id;
      _editingOriginalText = message.content;
    });
    _inputController.text = message.content;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: message.content.length),
    );
    _focusNode.requestFocus();
    _scrollToBottom();
  }

  void _handleStopGeneration() {
    final lastUserMsg = ref.read(chatProvider.notifier).getLastUserMessage();
    ref.read(chatProvider.notifier).stopGeneration();
    if (lastUserMsg != null) {
      setState(() {
        _editingMessageId = lastUserMsg.id;
        _editingOriginalText = lastUserMsg.content;
      });
      _inputController.text = lastUserMsg.content;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: lastUserMsg.content.length),
      );
      _focusNode.requestFocus();
    }
  }

  void _submitMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    if (_editingMessageId != null) {
      final targetId = _editingMessageId!;
      setState(() {
        _editingMessageId = null;
        _editingOriginalText = null;
      });
      _inputController.clear();
      ref.read(chatProvider.notifier).editAndResendMessage(targetId, text);
    } else {
      _inputController.clear();
      ref.read(chatProvider.notifier).sendMessage(text);
    }

    _scrollToBottom();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Auto scroll down whenever messages change or streaming updates
    ref.listen(chatProvider.select((s) => s.messages.length), (prev, next) {
      _scrollToBottom();
    });

    // التمرير التلقائي عند جهوزية خطة للاعتماد — بطاقة الخطة تُحدَّث في
    // فقاعة قديمة (فوق مستوى العرض غالباً) دون تغيّر عدد الرسائل، فبدون
    // هذا التنبيه لن يرى المستخدم الخطة أبداً ليقرر اعتمادها أو رفضها
    ref.listen(chatProvider.select((s) => s.planApprovalNonce), (prev, next) {
      if (next != prev) _scrollToBottom();
    });



    // مزامنة المهام التلقائية (متصفح الوكيل) مع layoutProvider:
    // إذا بدأت مهمة متصفح → افتح اللوحة تلقائياً.
    // ⚠️ لا نُغلق اللوحة هنا أبداً — الإغلاق حق المستخدم حصراً عبر زر ✕.
    ref.listen(showBrowserPanelProvider, (prev, next) {
      if (next && !ref.read(layoutProvider).workPanelOpen) {
        ref
            .read(layoutProvider.notifier)
            .openWorkPanel(tab: WorkPanelTab.browser);
      }
    });
    ref.listen(showTerminalPanelProvider, (prev, next) {
      if (next && !ref.read(layoutProvider).workPanelOpen) {
        ref
            .read(layoutProvider.notifier)
            .openWorkPanel(tab: WorkPanelTab.terminal);
      }
    });

    final borderColor = isDark
        ? DesignTokens.borderDark
        : DesignTokens.borderLight;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mode = layoutModeFromWidth(constraints.maxWidth);
          return _buildLayout(context, chatState, isDark, borderColor, mode);
        },
      ),
    );
  }

  // ── Main Layout Dispatcher ──────────────────────────────────────────────────
  Widget _buildLayout(
    BuildContext context,
    dynamic chatState,
    bool isDark,
    Color borderColor,
    LayoutMode mode,
  ) {
    final layoutState = ref.watch(layoutProvider);

    // في الوضع المضغوط → الشريط مطوي دائماً تلقائياً
    // (لكن يمكن فتحه يدوياً)

    final sidebarWidget = _buildSidebar(
      context,
      chatState,
      isDark,
      borderColor,
      mode,
    );

    final mainColumn = Column(
      children: [
        _buildTopBar(context, chatState, isDark, borderColor, mode),
        Expanded(
          child: chatState.messages.isEmpty
              ? _buildWelcomeView(context, chatState, isDark, borderColor)
              : _buildMessagesList(chatState),
        ),
        _buildInputArea(chatState, isDark, borderColor),
      ],
    );

    final bool panelOpen = layoutState.workPanelOpen;

    switch (mode) {
      case LayoutMode.compact:
        // شريط جانبي + محادثة. اللوحة كـ Stack overlay
        return Stack(
          children: [
            Row(
              children: [
                sidebarWidget,
                Expanded(child: mainColumn),
              ],
            ),
            if (panelOpen) const WorkPanel(isOverlay: true),
          ],
        );

      case LayoutMode.standard:
        // شريط جانبي + محادثة + لوحة (بدون ثلاثة أعمدة)
        return Row(
          children: [
            sidebarWidget,
            Expanded(child: mainColumn),
            if (panelOpen) const WorkPanel(isOverlay: false),
          ],
        );

      case LayoutMode.wide:
        // ثلاثة أعمدة: شريط + محادثة + لوحة
        return Row(
          children: [
            sidebarWidget,
            Expanded(child: mainColumn),
            if (panelOpen) const WorkPanel(isOverlay: false),
          ],
        );
    }
  }

  // ── Sidebar ─────────────────────────────────────────────────────────────────
  Widget _buildSidebar(
    BuildContext context,
    dynamic chatState,
    bool isDark,
    Color borderColor,
    LayoutMode mode,
  ) {
    final layoutState = ref.watch(layoutProvider);
    // الشريط مطوي: إما بتفضيل المستخدم، أو في وضع compact بشكل افتراضي
    final effectiveCollapsed = layoutState.sidebarCollapsed;

    if (effectiveCollapsed) {
      return _buildCollapsedSidebar(context, isDark, borderColor);
    }
    return _buildExpandedSidebar(context, chatState, isDark, borderColor);
  }

  // ── الشريط المطوي (أيقونات فقط) ────────────────────────────────────────────
  Widget _buildCollapsedSidebar(
    BuildContext context,
    bool isDark,
    Color borderColor,
  ) {
    final surfaceColor = isDark
        ? DesignTokens.surfaceDark
        : DesignTokens.surfaceLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;

    return Container(
      width: DesignTokens.sidebarWidthCollapsed,
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          left: BorderSide(color: borderColor, width: DesignTokens.hairline),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: DesignTokens.space12),
          // شعار
          Tooltip(
            message: 'خوارزمي',
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(
                  color: borderColor,
                  width: DesignTokens.hairline,
                ),
                color: isDark ? DesignTokens.bgDark : DesignTokens.bgLight,
              ),
              child: Center(
                child: Text(
                  'خ',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: DesignTokens.fontSizeLg,
                    fontFamily: DesignTokens.fontFamilyArabic,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.space8),
          // زر فتح الشريط
          Tooltip(
            message: 'فتح الشريط الجانبي',
            child: IconButton(
              icon: Icon(Icons.menu_rounded, size: 18, color: secondary),
              onPressed: () =>
                  ref.read(layoutProvider.notifier).toggleSidebar(),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: DesignTokens.space8),
          // زر محادثة جديدة
          Tooltip(
            message: 'محادثة جديدة',
            child: IconButton(
              icon: Icon(Icons.add_rounded, size: 18, color: secondary),
              onPressed: () {
                _cancelEditing();
                ref.read(chatProvider.notifier).clearConversation();
              },
              visualDensity: VisualDensity.compact,
            ),
          ),
          Container(
            height: DesignTokens.hairline,
            color: borderColor,
            margin: const EdgeInsetsDirectional.symmetric(
              vertical: DesignTokens.space8,
            ),
          ),
          // أيقونات الوحدات
          _collapsedIcon(
            Icons.storage_outlined,
            'الذاكرة الدائمة',
            secondary,
            () {
              showDialog(
                context: context,
                builder: (ctx) => const MemoryViewerDialog(),
              );
            },
          ),
          _collapsedIcon(
            Icons.notifications_none_rounded,
            'الجدولة والتنبيهات',
            secondary,
            () {
              showDialog(
                context: context,
                builder: (ctx) => const RemindersViewerDialog(),
              );
            },
          ),
          _collapsedIcon(Icons.language_rounded, 'المتصفح', secondary, () {
            ref
                .read(layoutProvider.notifier)
                .toggleWorkPanel(tab: WorkPanelTab.browser);
          }),
          _collapsedIcon(
            Icons.electric_bolt_rounded,
            'المهام المستقلة',
            secondary,
            () {
              showDialog(
                context: context,
                barrierDismissible: true,
                builder: (ctx) => const TasksPanelDialog(),
              );
            },
          ),
          const Spacer(),
          Container(height: DesignTokens.hairline, color: borderColor),
          Tooltip(
            message: 'الإعدادات',
            child: IconButton(
              icon: Icon(Icons.tune_outlined, size: 16, color: secondary),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => const SettingsDialog(),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: DesignTokens.space8),
        ],
      ),
    );
  }

  Widget _collapsedIcon(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 16, color: color),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ── الشريط الكامل (ثلاث مناطق) ──────────────────────────────────────────────
  Widget _buildExpandedSidebar(
    BuildContext context,
    dynamic chatState,
    bool isDark,
    Color borderColor,
  ) {
    final surfaceColor = isDark
        ? DesignTokens.surfaceDark
        : DesignTokens.surfaceLight;
    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final currentThemeMode = ref.watch(themeModeProvider);

    return Container(
      width: DesignTokens.sidebarWidthFull,
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          left: BorderSide(color: borderColor, width: DesignTokens.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── منطقة 1: رأس ثابت ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              DesignTokens.space12,
              DesignTokens.space12,
              DesignTokens.space8,
              DesignTokens.space12,
            ),
            child: Row(
              children: [
                // شعار
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    border: Border.all(
                      color: borderColor,
                      width: DesignTokens.hairline,
                    ),
                    color: isDark ? DesignTokens.bgDark : DesignTokens.bgLight,
                  ),
                  child: Center(
                    child: Text(
                      'خ',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w700,
                        fontSize: DesignTokens.fontSizeSm,
                        fontFamily: DesignTokens.fontFamilyArabic,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.space8),
                Expanded(
                  child: Text(
                    'خوارزمي',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
                // زر طي الشريط
                Tooltip(
                  message: 'طي الشريط الجانبي',
                  child: IconButton(
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: secondary,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: () =>
                        ref.read(layoutProvider.notifier).toggleSidebar(),
                  ),
                ),
              ],
            ),
          ),

          // زر محادثة جديدة
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              DesignTokens.space12,
              0,
              DesignTokens.space12,
              DesignTokens.space12,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('محادثة جديدة'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: DesignTokens.space8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  _cancelEditing();
                  ref.read(chatProvider.notifier).clearConversation();
                },
              ),
            ),
          ),

          Divider(
            height: DesignTokens.hairline,
            thickness: DesignTokens.hairline,
            color: borderColor,
          ),

          // ── منطقة 2: سجل المحادثات (قابل للتمرير — معظم المساحة) ──────
          Expanded(
            child: _buildConversationHistorySection(
              context,
              chatState,
              isDark,
              borderColor,
              primary,
              secondary,
            ),
          ),

          Divider(
            height: DesignTokens.hairline,
            thickness: DesignTokens.hairline,
            color: borderColor,
          ),

          // ── منطقة 3: الوحدات والإعدادات (أسفل ثابت — مضغوط) ──────────
          _buildBottomModulesSection(
            context,
            chatState,
            isDark,
            borderColor,
            primary,
            secondary,
            currentThemeMode,
          ),
        ],
      ),
    );
  }

  // ── سجل المحادثات مع تجميع زمني ──────────────────────────────────────────────
  Widget _buildConversationHistorySection(
    BuildContext context,
    dynamic chatState,
    bool isDark,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    final conversations = (chatState.conversations as List?) ?? [];
    final activeId = chatState.activeConversation?.id as String?;
    final activeBg = isDark ? DesignTokens.hoverDark : DesignTokens.hoverLight;

    if (chatState.isLoadingHistory == true) {
      return Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: secondaryTextColor,
          ),
        ),
      );
    }

    if (conversations.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          DesignTokens.space16,
          DesignTokens.space12,
          DesignTokens.space16,
          0,
        ),
        child: Text(
          'لا توجد محادثات سابقة',
          style: TextStyle(
            fontSize: DesignTokens.fontSizeXs,
            color: secondaryTextColor,
          ),
        ),
      );
    }

    // تجميع زمني
    final now = DateTime.now();
    final todayConvs = <dynamic>[];
    final weekConvs = <dynamic>[];
    final olderConvs = <dynamic>[];

    for (final conv in conversations) {
      final ts = conv.updatedAt as DateTime?;
      if (ts == null) {
        olderConvs.add(conv);
        continue;
      }
      final diff = now.difference(ts).inDays;
      if (diff == 0) {
        todayConvs.add(conv);
      } else if (diff <= 7) {
        weekConvs.add(conv);
      } else {
        olderConvs.add(conv);
      }
    }

    return ListView(
      padding: const EdgeInsets.only(
        top: DesignTokens.space8,
        bottom: DesignTokens.space8,
      ),
      children: [
        if (todayConvs.isNotEmpty) ...[
          _convGroupLabel('اليوم', secondaryTextColor),
          ..._convItems(
            todayConvs,
            activeId,
            activeBg,
            primaryTextColor,
            secondaryTextColor,
            borderColor,
            isDark,
          ),
        ],
        if (weekConvs.isNotEmpty) ...[
          _convGroupLabel('هذا الأسبوع', secondaryTextColor),
          ..._convItems(
            weekConvs,
            activeId,
            activeBg,
            primaryTextColor,
            secondaryTextColor,
            borderColor,
            isDark,
          ),
        ],
        if (olderConvs.isNotEmpty) ...[
          _convGroupLabel('أقدم', secondaryTextColor),
          ..._convItems(
            olderConvs,
            activeId,
            activeBg,
            primaryTextColor,
            secondaryTextColor,
            borderColor,
            isDark,
          ),
        ],
      ],
    );
  }

  Widget _convGroupLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DesignTokens.space12,
        DesignTokens.space8,
        DesignTokens.space12,
        DesignTokens.space4,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          fontWeight: FontWeight.w500,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  List<Widget> _convItems(
    List<dynamic> convs,
    String? activeId,
    Color activeBg,
    Color primary,
    Color secondary,
    Color borderColor,
    bool isDark,
  ) {
    return convs.map((conv) {
      final isActive = conv.id == activeId;
      return InkWell(
        onTap: () {
          _cancelEditing();
          ref.read(chatProvider.notifier).openConversation(conv.id as String);
        },
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Container(
          margin: const EdgeInsetsDirectional.fromSTEB(
            DesignTokens.space8,
            1,
            DesignTokens.space8,
            1,
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(
            DesignTokens.space8,
            6,
            DesignTokens.space8,
            6,
          ),
          decoration: BoxDecoration(
            color: isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  conv.title as String? ?? 'محادثة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: isActive ? primary : secondary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                iconSize: 14,
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 14,
                  color: secondary,
                ),
                onSelected: (action) async {
                  final convId = conv.id as String;
                  if (action == 'rename') {
                    final ctrl = TextEditingController(
                      text: conv.title as String? ?? '',
                    );
                    final result = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('إعادة تسمية المحادثة'),
                        content: TextField(
                          controller: ctrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'الاسم الجديد',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () =>
                                Navigator.pop(ctx, ctrl.text.trim()),
                            child: const Text('حفظ'),
                          ),
                        ],
                      ),
                    );
                    if (result != null && result.isNotEmpty) {
                      ref
                          .read(chatProvider.notifier)
                          .renameConversation(convId, result);
                    }
                  } else if (action == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('حذف المحادثة'),
                        content: const Text(
                          'هل تريد حذف هذه المحادثة نهائياً؟ لا يمكن التراجع.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      ref
                          .read(chatProvider.notifier)
                          .deleteConversation(convId);
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 14),
                        SizedBox(width: 8),
                        Text('إعادة تسمية'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 14),
                        SizedBox(width: 8),
                        Text('حذف'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // ── الوحدات والإعدادات (أسفل الشريط) ─────────────────────────────────────────
  Widget _buildBottomModulesSection(
    BuildContext context,
    dynamic chatState,
    bool isDark,
    Color borderColor,
    Color primary,
    Color secondary,
    ThemeMode currentThemeMode,
  ) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DesignTokens.space8,
        DesignTokens.space8,
        DesignTokens.space8,
        DesignTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // أيقونات الوحدات في صف أفقي مضغوط
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _moduleIcon(Icons.storage_outlined, 'الذاكرة', secondary, () {
                showDialog(
                  context: context,
                  builder: (ctx) => const MemoryViewerDialog(),
                );
              }),
              _moduleIcon(
                Icons.notifications_none_rounded,
                'التنبيهات',
                secondary,
                () {
                  showDialog(
                    context: context,
                    builder: (ctx) => const RemindersViewerDialog(),
                  );
                },
              ),
              _moduleIcon(Icons.language_rounded, 'المتصفح', secondary, () {
                ref
                    .read(layoutProvider.notifier)
                    .toggleWorkPanel(tab: WorkPanelTab.browser);
              }),
              _moduleIcon(Icons.electric_bolt_rounded, 'المهام', secondary, () {
                showDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) => const TasksPanelDialog(),
                );
              }),
              _moduleIcon(Icons.extension_outlined, 'الإضافات', secondary, () {
                SkillsSettingsDialog.show(context);
              }),
            ],
          ),
          const SizedBox(height: DesignTokens.space4),
          Divider(
            height: DesignTokens.hairline,
            thickness: DesignTokens.hairline,
            color: borderColor,
          ),
          const SizedBox(height: DesignTokens.space4),
          // المظهر
          InkWell(
            onTap: () => ref.read(themeModeProvider.notifier).toggleNext(),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DesignTokens.space8,
                vertical: DesignTokens.space4,
              ),
              child: Row(
                children: [
                  Icon(
                    switch (currentThemeMode) {
                      ThemeMode.light => Icons.light_mode_outlined,
                      ThemeMode.dark => Icons.dark_mode_outlined,
                      ThemeMode.system => Icons.brightness_auto_outlined,
                    },
                    size: 14,
                    color: secondary,
                  ),
                  const SizedBox(width: DesignTokens.space8),
                  Expanded(
                    child: Text(
                      'المظهر: ${switch (currentThemeMode) {
                        ThemeMode.light => 'نهاري',
                        ThemeMode.dark => 'ليلي',
                        ThemeMode.system => 'نظام Windows',
                      }}',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        color: secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // الإعدادات
          InkWell(
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => const SettingsDialog(),
            ),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DesignTokens.space8,
                vertical: DesignTokens.space4,
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_outlined, size: 14, color: secondary),
                  const SizedBox(width: DesignTokens.space8),
                  Expanded(
                    child: Text(
                      'الإعدادات والمفاتيح',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        color: primary,
                      ),
                    ),
                  ),
                  if (chatState.apiKey == null || chatState.apiKey.isEmpty)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleIcon(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.space8),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar(
    BuildContext context,
    dynamic chatState,
    bool isDark,
    Color borderColor,
    LayoutMode mode,
  ) {
    final surfaceColor = isDark ? DesignTokens.bgDark : DesignTokens.bgLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;

    final layoutState = ref.watch(layoutProvider);
    final activeProject = ref.watch(activeProjectProvider);
    final pendingChanges = ref.watch(pendingChangesProvider);

    return Container(
      height: DesignTokens.topBarHeight,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DesignTokens.space12,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          bottom: BorderSide(color: borderColor, width: DesignTokens.hairline),
        ),
      ),
      child: Row(
        children: [
          // زر فتح الشريط (يظهر فقط في الوضع المضغوط compact حيث لا يوجد شريط ظاهر على الشاشة)
          if (mode == LayoutMode.compact)
            IconButton(
              icon: Icon(Icons.menu_rounded, size: 16, color: secondary),
              tooltip: 'فتح الشريط الجانبي',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  ref.read(layoutProvider.notifier).toggleSidebar(),
            ),

          // منتقي الموديل — **مكان واحد فقط**
          Flexible(
            child: ModelSwitcherBadge(compact: mode == LayoutMode.compact),
          ),

          // شارة المشروع النشط
          if (activeProject != null) ...[
            const SizedBox(width: DesignTokens.space8),
            Flexible(
              child: Tooltip(
                message: 'المشروع النشط: ${activeProject.rootPath}',
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DesignTokens.space8,
                    vertical: DesignTokens.space4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? DesignTokens.surfaceDark
                        : DesignTokens.surfaceLight,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    border: Border.all(
                      color: borderColor,
                      width: DesignTokens.hairline,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_rounded,
                        size: 13,
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade700,
                      ),
                      const SizedBox(width: DesignTokens.space4),
                      Flexible(
                        child: Text(
                          activeProject.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // تعديلات معلقة (التمرير مباشرة للـ Diff في الشات)
          if (pendingChanges.isNotEmpty) ...[
            const SizedBox(width: DesignTokens.space8),
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.difference_outlined, size: 13),
              label: Text(
                'تعديلات (${pendingChanges.length})',
                style: const TextStyle(fontSize: DesignTokens.fontSizeXs),
              ),
              onPressed: () => _scrollToBottom(),
            ),
          ],

          const Spacer(),

          // زر الترمينال (إذا وُجد مشروع نشط فقط)
          if (activeProject != null)
            IconButton(
              icon: Icon(
                Icons.terminal_rounded,
                size: 15,
                color:
                    layoutState.workPanelOpen &&
                        layoutState.activeWorkTab == WorkPanelTab.terminal
                    ? primary
                    : secondary,
              ),
              tooltip: 'الترمينال الحي',
              visualDensity: VisualDensity.compact,
              onPressed: () => ref
                  .read(layoutProvider.notifier)
                  .toggleWorkPanel(tab: WorkPanelTab.terminal),
            ),
        ],
      ),
    );
  }

  // ── Welcome View — كتلة متماسكة قريبة من صندوق الإدخال ────────────────────
  Widget _buildWelcomeView(
    BuildContext context,
    dynamic chatState,
    bool isDark,
    Color borderColor,
  ) {
    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        reverse: true,
        padding: const EdgeInsetsDirectional.fromSTEB(
          DesignTokens.space24,
          DesignTokens.space32,
          DesignTokens.space24,
          DesignTokens.space24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.chatMaxWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // شعار + تحية
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? DesignTokens.surfaceDark
                            : DesignTokens.surfaceLight,
                        border: Border.all(
                          color: borderColor,
                          width: DesignTokens.hairline,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'خ',
                          style: TextStyle(
                            color: primary,
                            fontSize: DesignTokens.fontSizeLg,
                            fontWeight: FontWeight.w700,
                            fontFamily: DesignTokens.fontFamilyArabic,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.space12),
                    Text(
                      'كيف أساعدك اليوم؟',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXl,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: DesignTokens.space20),

                // تنبيه مفتاح API
                if (chatState.apiKey == null || chatState.apiKey.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(DesignTokens.space16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DesignTokens.surfaceDark
                          : DesignTokens.surfaceLight,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusMd,
                      ),
                      border: Border.all(
                        color: borderColor,
                        width: DesignTokens.hairline,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.key_outlined, size: 16, color: primary),
                        const SizedBox(width: DesignTokens.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مفتاح API مطلوب',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: DesignTokens.fontSizeSm,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.space4),
                              Text(
                                'أضف مفتاحك من Google AI Studio ليُحفظ مشفراً على جهازك.',
                                style: TextStyle(
                                  fontSize: DesignTokens.fontSizeXs,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: DesignTokens.space12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (ctx) => const SettingsDialog(),
                          ),
                          child: const Text('إضافة المفتاح'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // شرائح الاقتراح — فئات فعلية تعكس قدرات خوارزمي
                  Text(
                    'جرّب أن تقول:',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeXs,
                      color: secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space12),
                  Wrap(
                    spacing: DesignTokens.space8,
                    runSpacing: DesignTokens.space8,
                    children: [
                      _buildSuggestionChip(
                        icon: Icons.search_rounded,
                        label: 'ابحث وقارن',
                        prompt: 'ابحث عن أفضل أدوات إدارة المهام ووازن بينها',
                        isDark: isDark,
                        borderColor: borderColor,
                        primary: primary,
                        secondary: secondary,
                      ),
                      _buildSuggestionChip(
                        icon: Icons.notifications_none_rounded,
                        label: 'ذكّرني بموعد',
                        prompt:
                            'ذكّرني بالاجتماع الأسبوعي كل أحد الساعة 10 صباحاً',
                        isDark: isDark,
                        borderColor: borderColor,
                        primary: primary,
                        secondary: secondary,
                      ),
                      _buildSuggestionChip(
                        icon: Icons.terminal_rounded,
                        label: 'اشتغل على مشروع',
                        prompt: 'افتح مشروع Flutter وأضف ميزة تسجيل الدخول',
                        isDark: isDark,
                        borderColor: borderColor,
                        primary: primary,
                        secondary: secondary,
                      ),
                      _buildSuggestionChip(
                        icon: Icons.language_rounded,
                        label: 'افتح صفحة وحلّلها',
                        prompt: 'افتح موقع github.com واشرح لي أهم المستودعات الشائعة اليوم',
                        isDark: isDark,
                        borderColor: borderColor,
                        primary: primary,
                        secondary: secondary,
                      ),
                      _buildSuggestionChip(
                        icon: Icons.electric_bolt_rounded,
                        label: 'شغّل مهمة مستقلة',
                        prompt: 'ابحث عن آخر أخبار الذكاء الاصطناعي واحفظ ملخصاً في ذاكرتك',
                        isDark: isDark,
                        borderColor: borderColor,
                        primary: primary,
                        secondary: secondary,
                      ),
                      _buildSuggestionChip(
                        icon: Icons.folder_outlined,
                        label: 'اقرأ ملفاتي',
                        prompt:
                            'اقرأ محتويات مجلد المشروع واشرح لي الهيكل العام',
                        isDark: isDark,
                        borderColor: borderColor,
                        primary: primary,
                        secondary: secondary,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChip({
    required IconData icon,
    required String label,
    required String prompt,
    required bool isDark,
    required Color borderColor,
    required Color primary,
    required Color secondary,
  }) {
    final surfaceColor = isDark
        ? DesignTokens.surfaceDark
        : DesignTokens.surfaceLight;
    final hoverColor = isDark
        ? DesignTokens.hoverDark
        : DesignTokens.hoverLight;

    return InkWell(
      onTap: () {
        _inputController.text = prompt;
        _submitMessage();
      },
      hoverColor: hoverColor,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
          DesignTokens.space12,
          DesignTokens.space8,
          DesignTokens.space12,
          DesignTokens.space8,
        ),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          border: Border.all(color: borderColor, width: DesignTokens.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: DesignTokens.space8),
            Text(
              label,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeSm,
                color: primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Messages List ────────────────────────────────────────────────────────────
  Widget _buildMessagesList(dynamic chatState) {
    final turns = ChatTurn.groupMessages(
      chatState.messages,
      isStreaming: chatState.isStreaming,
      activeStatus: chatState.activeStatus,
    );

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.space16),
      itemCount: turns.length,
      itemBuilder: (context, index) {
        return ChatBubble.fromTurn(
          turn: turns[index],
          onEdit: (message) => _startEditing(message),
        );
      },
    );
  }

  // ── Input Area ───────────────────────────────────────────────────────────────
  Widget _buildInputArea(dynamic chatState, bool isDark, Color borderColor) {
    final surfaceColor = isDark ? DesignTokens.bgDark : DesignTokens.bgLight;
    final inputBg = isDark
        ? DesignTokens.surfaceInputDark
        : DesignTokens.surfaceInputLight;
    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final activeProject = ref.watch(activeProjectProvider);
    final providerConfig = ProviderRegistry.getConfig(
      chatState.selectedProviderId,
    );
    final doesSupportThinking =
        providerConfig?.doesModelSupportThinking(chatState.selectedModel) ??
        false;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          top: BorderSide(color: borderColor, width: DesignTokens.hairline),
        ),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        DesignTokens.space16,
        DesignTokens.space12,
        DesignTokens.space16,
        DesignTokens.space16,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesignTokens.chatMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LiveTasksHud(),
              // تنبيه غياب التفكير في وضع الكود (يظهر مرة واحدة فقط ثم يُخفى)
              if (chatState.isCodingAgentMode &&
                  !doesSupportThinking &&
                  !chatState.codingModeThinkingBannerShown) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: DesignTokens.space8),
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DesignTokens.space12,
                    vertical: DesignTokens.space8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2E2412)
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      width: DesignTokens.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: DesignTokens.space8),
                      Expanded(
                        child: Text(
                          'النموذج المحدد لا يدعم التفكير الموسَّع — سيتم تنفيذ المهام بدون مسودة تفكير مطولة.',
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF92400E),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        onPressed: () {
                          ref
                              .read(chatProvider.notifier)
                              .markCodingBannerShown();
                        },
                      ),
                    ],
                  ),
                ),
              ],

              // مؤشر قفل المشروع أثناء عمل خوارزمي في السلسلة التلقائية
              if (chatState.isProjectLocked ||
                  (chatState.isStreaming &&
                      (chatState.activeCodingMode == CodingMode.code ||
                          chatState.activeCodingMode == CodingMode.debug))) ...[
                _buildProjectLockedBanner(chatState, isDark, borderColor),
                const SizedBox(height: DesignTokens.space8),
              ],

              // شريط الوكيل البرمجي (إذا كان نشطاً أو هناك مشروع مفتوح)
              if (chatState.isCodingAgentMode || ref.watch(activeProjectProvider) != null) ...[
                _buildCodingAgentProjectBar(context, isDark, borderColor),
                const SizedBox(height: DesignTokens.space8),
              ],

              // شريط التعديل (إذا كان المستخدم يعدّل رسالة)
              if (_editingMessageId != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: DesignTokens.space8),
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DesignTokens.space12,
                    vertical: DesignTokens.space4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? DesignTokens.surfaceDark
                        : DesignTokens.surfaceLight,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    border: Border.all(
                      color: borderColor,
                      width: DesignTokens.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade700,
                      ),
                      const SizedBox(width: DesignTokens.space8),
                      Text(
                        'تعديل الرسالة',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.blue.shade300
                              : Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.space8),
                      Expanded(
                        child: Text(
                          _editingOriginalText ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: secondary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 13),
                        tooltip: 'إلغاء التعديل',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        onPressed: _cancelEditing,
                      ),
                    ],
                  ),
                ),
              ],

              // ── حقل الإدخال مع زر الإرسال داخله ─────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  border: Border.all(
                    color: borderColor,
                    width: DesignTokens.hairline,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _submitMessage();
                        }
                      },
                      child: TextField(
                        controller: _inputController,
                        focusNode: _focusNode,
                        maxLines: 6,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) => _submitMessage(),
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeBase,
                          color: primary,
                          height: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: _editingMessageId != null
                              ? 'عدّل رسالتك واضغط Enter...'
                              : (chatState.isCodingAgentMode
                                    ? (activeProject != null
                                          ? 'اكتب طلبك البرمجي لمشروع "${activeProject.name}"...'
                                          : 'حدد مسار المشروع أعلاه للبدء...')
                                    : 'اكتب رسالتك... (Enter للإرسال، Shift+Enter لسطر جديد)'),
                          hintStyle: TextStyle(
                            color: secondary,
                            fontSize: DesignTokens.fontSizeSm,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsetsDirectional.fromSTEB(
                            DesignTokens.space16,
                            DesignTokens.space12,
                            DesignTokens.space16,
                            DesignTokens.space12,
                          ),
                        ),
                      ),
                    ),

                    // ── صف الأدوات السفلي ─────────────────────────────────
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        DesignTokens.space8,
                        0,
                        DesignTokens.space8,
                        DesignTokens.space8,
                      ),
                      child: Row(
                        children: [
                          // مجموعة المبدّلات — قابلة للتمرير الأفقي عند ضيق
                          // المساحة حتى لا يفيض الشريط أبداً (صف صلب + زر
                          // إضافي = فيض 39px في النوافذ الضيقة). زر الإرسال
                          // يبقى مثبّتاً على الطرف دائماً.
                          Flexible(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // تبديل الوضع (محادثة عامة / وكيل برمجي)
                                  _buildModeToggle(
                                    chatState,
                                    isDark,
                                    borderColor,
                                  ),
                                  const SizedBox(width: 6),
                                  // تبديل العرض مبسط ↔ تفصيلي — أُعيد هنا بعد
                                  // إزالته من الشريط العلوي، لأن الوضع محفوظ
                                  // في الإعدادات وبدون زر يبقى المستخدم عالقاً
                                  // في آخر وضع حُفظ (التفصيلي المزدحم)
                                  Consumer(
                                    builder: (ctx, ref, _) {
                                      final simplified = ref
                                          .watch(layoutProvider)
                                          .isSimplifiedView;
                                      return Tooltip(
                                        message: simplified
                                            ? 'عرض تفصيلي (أدوات + تفكير)'
                                            : 'عرض مبسط (نظيف)',
                                        child: IconButton(
                                          icon: Icon(
                                            simplified
                                                ? Icons.view_stream_outlined
                                                : Icons.article_outlined,
                                            size: 15,
                                          ),
                                          color: simplified
                                              ? secondary
                                              : primary,
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => ref
                                              .read(layoutProvider.notifier)
                                              .toggleSimplifiedView(),
                                        ),
                                      );
                                    },
                                  ),
                                  // مفتاح التفكير الموسَّع (يظهر فقط إن كان النموذج داعماً وخارج وضع الكود)
                                  if (!chatState.isCodingAgentMode &&
                                      doesSupportThinking)
                                    _buildThinkingToggle(
                                      chatState,
                                      isDark,
                                      borderColor,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // زر الإرسال / الإيقاف — داخل الكتلة
                          _buildSendButton(chatState, isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingToggle(
    dynamic chatState,
    bool isDark,
    Color borderColor,
  ) {
    final isEnabled = chatState.thinkingEnabled == true;
    final activeColor = isDark ? Colors.amber.shade400 : Colors.amber.shade700;
    final inactiveColor = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: DesignTokens.space8),
      child: Tooltip(
        message: isEnabled
            ? 'التفكير الموسَّع: مفعَّل'
            : 'التفكير الموسَّع: معطَّل',
        child: InkWell(
          onTap: () {
            ref.read(chatProvider.notifier).toggleThinking();
          },
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.space8,
              vertical: DesignTokens.space4,
            ),
            decoration: BoxDecoration(
              color: isEnabled
                  ? (isDark
                        ? Colors.amber.withValues(alpha: 0.15)
                        : Colors.amber.withValues(alpha: 0.12))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: Border.all(
                color: isEnabled
                    ? activeColor.withValues(alpha: 0.5)
                    : borderColor,
                width: DesignTokens.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isEnabled
                      ? Icons.lightbulb_rounded
                      : Icons.lightbulb_outline_rounded,
                  size: 14,
                  color: isEnabled ? activeColor : inactiveColor,
                ),
                const SizedBox(width: DesignTokens.space4),
                Text(
                  'تفكير',
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    fontWeight: isEnabled ? FontWeight.w600 : FontWeight.w400,
                    color: isEnabled ? activeColor : inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(dynamic chatState, bool isDark) {
    final isStreaming = chatState.isStreaming == true;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          onTap: isStreaming ? _handleStopGeneration : _submitMessage,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isStreaming
                  ? (isDark ? Colors.red.shade900 : Colors.red.shade600)
                  : (isDark
                        ? DesignTokens.textPrimaryDark
                        : DesignTokens.textPrimaryLight),
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: Icon(
              isStreaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
              size: 15,
              color: isStreaming
                  ? Colors.white
                  : (isDark ? DesignTokens.bgDark : DesignTokens.bgLight),
            ),
          ),
        ),
      ),
    );
  }

  // ── Mode Toggle (5-Mode System) ──────────────────────────────────────────────
  Widget _buildModeToggle(dynamic chatState, bool isDark, Color borderColor) {
    final activeMode = chatState.activeCodingMode as CodingMode;
    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    // قفل المبدّل أثناء التوليد
    final isLocked = chatState.isStreaming == true;
    final selectableModes = userSelectableInitialModes;

    return Tooltip(
      message: isLocked ? 'الوكيل يعمل — أوقف التوليد أولاً لتغيير الوضع' : '',
      child: Opacity(
        opacity: isLocked ? 0.45 : 1.0,
        child: IgnorePointer(
          ignoring: isLocked,
          child: Container(
            height: 26,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: Border.all(color: borderColor, width: DesignTokens.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < selectableModes.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: DesignTokens.hairline,
                      height: 14,
                      color: borderColor,
                    ),
                  () {
                    final mode = selectableModes[i];
                    final config = codingModeConfigs[mode]!;
                    final isSelected = activeMode == mode;
                    return _modeToggleBtn(
                      icon: _getIconData(config.iconName),
                      label: config.label,
                      isActive: isSelected,
                      isDark: isDark,
                      primary: primary,
                      secondary: secondary,
                      isFirst: i == 0,
                      isLast: i == selectableModes.length - 1,
                      borderColor: borderColor,
                      onTap: () {
                        ref.read(chatProvider.notifier).setActiveCodingMode(mode);
                        ref.read(chatProvider.notifier).setCodingAgentMode(true);
                      },
                    );
                  }(),
                ],
                // مؤشر وضع إصلاح الأخطاء (يظهر فقط عند التنفيذ التلقائي لوضع debug)
                if (activeMode == CodingMode.debug) ...[
                  Container(width: DesignTokens.hairline, height: 14, color: borderColor),
                  () {
                    final config = codingModeConfigs[CodingMode.debug]!;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.space8,
                        vertical: DesignTokens.space4,
                      ),
                      decoration: BoxDecoration(
                        color: config.accentColor.withValues(alpha: isDark ? 0.25 : 0.15),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(DesignTokens.radiusSm),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(color: config.accentColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            config.label,
                            style: TextStyle(
                              fontSize: DesignTokens.fontSizeXs,
                              fontWeight: FontWeight.w700,
                              color: config.accentColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeToggleBtn({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isDark,
    required Color primary,
    required Color secondary,
    required bool isFirst,
    bool isLast = false,
    required Color borderColor,
    required VoidCallback onTap,
    Widget? suffix,
  }) {
    final hoverBg = isDark ? DesignTokens.hoverDark : DesignTokens.hoverLight;
    final BorderRadius radius;
    if (isFirst && isLast) {
      radius = BorderRadius.circular(DesignTokens.radiusSm);
    } else if (isFirst) {
      radius = const BorderRadius.horizontal(
        right: Radius.circular(DesignTokens.radiusSm),
      );
    } else if (isLast) {
      radius = const BorderRadius.horizontal(
        left: Radius.circular(DesignTokens.radiusSm),
      );
    } else {
      radius = BorderRadius.zero;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space8,
          vertical: DesignTokens.space4,
        ),
        decoration: BoxDecoration(
          color: isActive ? hoverBg : Colors.transparent,
          borderRadius: radius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? primary : secondary),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? primary : secondary,
              ),
            ),
            ?suffix,
          ],
        ),
      ),
    );
  }

  // ── Project Locked Banner ─────────────────────────────────────────────────────
  Widget _buildProjectLockedBanner(
    dynamic chatState,
    bool isDark,
    Color borderColor,
  ) {
    final activeMode = chatState.activeCodingMode as CodingMode;
    final config = codingModeConfigs[activeMode] ?? codingModeConfigs[CodingMode.manager]!;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space12,
        vertical: DesignTokens.space4,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2332) : const Color(0xFFEBF3FB),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
          color: isDark ? Colors.blue.shade700 : Colors.blue.shade300,
          width: DesignTokens.hairline,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_clock_rounded,
            size: 14,
            color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
          ),
          const SizedBox(width: DesignTokens.space8),
          Expanded(
            child: Text(
              'خوارزمي يعمل — الوضع الحالي: [${config.label}] — التعديل اليدوي معطّل مؤقتاً',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.blue.shade200 : Colors.blue.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Coding Mode Selector ───────────────────────────────────────────────────────
  // _buildCodingModeSelector removed — mode selection is now in _buildModeToggle (input toolbar).
  // _buildModeDetailCard removed — permissions card is no longer displayed inline.



  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'code':
        return Icons.code_rounded;
      case 'architecture':
        return Icons.architecture_rounded;
      case 'help_outline':
        return Icons.help_outline_rounded;
      case 'bug_report':
        return Icons.bug_report_rounded;
      case 'hub':
        return Icons.hub_rounded;
      default:
        return Icons.code_rounded;
    }
  }

  // ── Coding Agent Project Bar ─────────────────────────────────────────────────
  Widget _buildCodingAgentProjectBar(
    BuildContext context,
    bool isDark,
    Color borderColor,
  ) {
    final activeProject = ref.watch(activeProjectProvider);
    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    if (activeProject == null) {
      return Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DesignTokens.space12,
          vertical: DesignTokens.space8,
        ),
        decoration: BoxDecoration(
          color: isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(color: borderColor, width: DesignTokens.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.code_rounded, size: 16, color: secondary),
            const SizedBox(width: DesignTokens.space8),
            Expanded(
              child: Text(
                'لم تحدد مسار المشروع — اضغط لاختياره',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: secondary,
                ),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
              ),
              icon: const Icon(Icons.folder_open_rounded, size: 13),
              label: const Text('اختر المشروع', style: TextStyle(fontSize: 11)),
              onPressed: _pickProjectDirectory,
            ),
            const SizedBox(width: DesignTokens.space4),
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, size: 15),
              tooltip: 'كتابة المسار يدوياً',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showManualPathDialog(context),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DesignTokens.space12,
        DesignTokens.space4,
        DesignTokens.space4,
        DesignTokens.space4,
      ),
      decoration: BoxDecoration(
        color: isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: borderColor, width: DesignTokens.hairline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_rounded,
            size: 14,
            color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
          ),
          const SizedBox(width: DesignTokens.space8),
          Text(
            activeProject.name,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          const SizedBox(width: DesignTokens.space8),
          Expanded(
            child: Text(
              activeProject.rootPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: secondary,
              ),
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            ),
            icon: const Icon(Icons.sync_alt_rounded, size: 11),
            label: const Text('تغيير', style: TextStyle(fontSize: 10)),
            onPressed: _pickProjectDirectory,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 13),
            tooltip: 'إغلاق المشروع',
            visualDensity: VisualDensity.compact,
            onPressed: () => ref.read(projectProvider.notifier).closeProject(),
          ),
        ],
      ),
    );
  }

  // ── File / Path Pickers ──────────────────────────────────────────────────────
  Future<void> _pickProjectDirectory() async {
    try {
      final String? selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'اختر مجلد المشروع الذي سيعمل عليه خوارزمي',
      );
      if (selectedDirectory != null && selectedDirectory.trim().isNotEmpty) {
        final path = selectedDirectory.trim();
        await ref.read(projectProvider.notifier).openProject(path);
        ref.read(chatProvider.notifier).setCodingAgentMode(true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تعيين مشروع العمل: $path'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر فتح المجلد: $e')));
    }
  }

  void _showManualPathDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder_open_rounded, size: 18),
            SizedBox(width: 8),
            Text('إدخال مسار المشروع يدوياً'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'أدخل المسار الكامل لمجلد المشروع:',
              style: TextStyle(fontSize: DesignTokens.fontSizeXs),
            ),
            const SizedBox(height: DesignTokens.space12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: r'C:\Users\...\my_project',
                prefixIcon: Icon(Icons.link_rounded, size: 15),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                Navigator.of(ctx).pop();
                await ref.read(projectProvider.notifier).openProject(path);
                ref.read(chatProvider.notifier).setCodingAgentMode(true);
              }
            },
            child: const Text('تعيين المشروع'),
          ),
        ],
      ),
    );
  }
}
