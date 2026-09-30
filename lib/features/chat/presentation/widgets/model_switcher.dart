import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_controller.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/providers/domain/provider_config.dart';

/// شارة النموذج القابلة للنقر — تفتح منتقي النموذج/المزوّد
/// متجاوبة مع كافة أحجام الشاشات وتدعم العرض المدمج والكامل
class ModelSwitcherBadge extends ConsumerWidget {
  final bool compact;
  final bool showBorder;
  final EdgeInsets? padding;

  const ModelSwitcherBadge({
    super.key,
    this.compact = false,
    this.showBorder = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final surfaceColor =
        isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final primaryTextColor =
        isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    // اسم المزوّد المختصر
    final providerConfig =
        ProviderRegistry.getConfig(chatState.selectedProviderId);
    final providerName =
        providerConfig?.displayName ?? chatState.selectedProviderId;
    final providerLabel = _shortProviderName(providerName);

    final isLocked = chatState.isStreaming;
    final tooltipMsg = isLocked
        ? 'الوكيل يعمل — أوقف التوليد أولاً لتغيير النموذج'
        : 'تغيير النموذج أو المزوّد ($providerName / ${chatState.selectedModel})';

    return Tooltip(
      message: tooltipMsg,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          onTap: isLocked ? null : () => _openSwitcher(context, ref),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: padding ??
                EdgeInsets.symmetric(
                  horizontal: compact ? DesignTokens.space8 : DesignTokens.space12,
                  vertical: compact ? DesignTokens.space4 : 6,
                ),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: showBorder
                  ? Border.all(
                      color: isLocked
                          ? borderColor.withValues(alpha: 0.4)
                          : borderColor,
                      width: DesignTokens.hairline,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLocked ? Icons.lock_outline_rounded : Icons.memory_rounded,
                  size: compact ? 13 : 15,
                  color: isLocked
                      ? secondaryTextColor.withValues(alpha: 0.5)
                      : secondaryTextColor,
                ),
                const SizedBox(width: DesignTokens.space4),
                Flexible(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$providerLabel ',
                          style: TextStyle(
                            fontSize: compact
                                ? DesignTokens.fontSizeXs
                                : DesignTokens.fontSizeSm,
                            color: isLocked
                                ? secondaryTextColor.withValues(alpha: 0.5)
                                : secondaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: '/ ${chatState.selectedModel}',
                          style: TextStyle(
                            fontSize: compact
                                ? DesignTokens.fontSizeXs
                                : DesignTokens.fontSizeSm,
                            color: isLocked
                                ? primaryTextColor.withValues(alpha: 0.5)
                                : primaryTextColor,
                            fontWeight: FontWeight.w600,
                            fontFamily: DesignTokens.fontFamilyMono,
                            fontFamilyFallback: DesignTokens.monoFallbacks,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.space4),
                Icon(
                  Icons.expand_more_rounded,
                  size: compact ? 14 : 16,
                  color: isLocked
                      ? secondaryTextColor.withValues(alpha: 0.4)
                      : secondaryTextColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _shortProviderName(String displayName) {
    const map = {
      'Google Gemini': 'Gemini',
      'Anthropic Claude': 'Claude',
      'OpenAI GPT': 'OpenAI',
      'Groq': 'Groq',
      'DeepSeek': 'DeepSeek',
      'OpenRouter': 'OpenRouter',
      'NVIDIA Build': 'NVIDIA',
      'NVIDIA Build (نماذج مجانية)': 'NVIDIA',
    };
    return map[displayName] ??
        (displayName.length > 12 ? '${displayName.substring(0, 11)}…' : displayName);
  }

  static Future<void> _openSwitcher(BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _ModelSwitcherDialog(ref: ref),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// نافذة اختيار النموذج — مقسمة إلى قسمين بأسلوب وكلاء الأكواد الحديثة (OpenCode)
// ─────────────────────────────────────────────────────────────────────────────

class _ModelSwitcherDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _ModelSwitcherDialog({required this.ref});

  @override
  ConsumerState<_ModelSwitcherDialog> createState() =>
      _ModelSwitcherDialogState();
}

class _ModelSwitcherDialogState extends ConsumerState<_ModelSwitcherDialog> {
  late String _selectedProvider;
  late String _selectedModel;
  late String _apiKey;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<String> _allModels = [];
  List<String> _filteredModels = [];
  bool _isFetching = false;
  bool _obscureKey = true;
  bool _isSaving = false;
  String? _fetchError;
  Timer? _debounce;
  String _selectedCategory = 'all'; // all, reasoning, code, vision, fast

  @override
  void initState() {
    super.initState();
    final state = widget.ref.read(chatProvider);
    _selectedProvider = state.selectedProviderId;
    _selectedModel = state.selectedModel;
    _apiKey = state.apiKey ?? '';
    _apiKeyCtrl.text = _apiKey;

    _searchCtrl.addListener(_onSearchChanged);
    _buildModelList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _apiKeyCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _buildModelList() {
    final config = ProviderRegistry.getConfig(_selectedProvider);
    _allModels = (config?.availableModels.isNotEmpty == true)
        ? List.from(config!.availableModels)
        : (_selectedModel.isNotEmpty ? [_selectedModel] : []);
    _applyFilter();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filteredModels = _allModels.where((m) {
        final matchesQuery = q.isEmpty || m.toLowerCase().contains(q);
        if (!matchesQuery) return false;

        switch (_selectedCategory) {
          case 'reasoning':
            return _isReasoningModel(m);
          case 'code':
            return _isCodeModel(m);
          case 'vision':
            return _isVisionModel(m);
          case 'fast':
            return _isFastModel(m);
          default:
            return true;
        }
      }).toList();
    });
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _applyFilter);
  }

  Future<void> _fetchModels() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) return;

    setState(() {
      _isFetching = true;
      _fetchError = null;
    });

    try {
      final provider = ProviderRegistry.getProvider(_selectedProvider);
      final models = await provider.fetchModels(key);
      if (!mounted) return;
      setState(() {
        _allModels = models;
        _isFetching = false;
        _applyFilter();
        if (!_filteredModels.contains(_selectedModel) &&
            _filteredModels.isNotEmpty) {
          _selectedModel = _filteredModels.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetching = false;
        _fetchError = 'تعذر جلب النماذج: ${e.toString().split('\n').first}';
      });
    }
  }

  Future<void> _switchProvider(String newId) async {
    final savedKey = await SecureStorageService.getApiKey(newId) ?? '';
    final config = ProviderRegistry.getConfig(newId);
    final savedModel = await SecureStorageService.getProviderModel(newId) ??
        config?.defaultModel ??
        '';

    if (!mounted) return;
    setState(() {
      _selectedProvider = newId;
      _selectedModel = savedModel;
      _apiKey = savedKey;
      _apiKeyCtrl.text = savedKey;
      _fetchError = null;
      _searchCtrl.clear();
      _selectedCategory = 'all';
    });
    _buildModelList();

    if (savedKey.isNotEmpty) _fetchModels();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final key = _apiKeyCtrl.text.trim();

    await widget.ref
        .read(chatProvider.notifier)
        .updateApiKey(_selectedProvider, key);
    await widget.ref
        .read(chatProvider.notifier)
        .updateProvider(_selectedProvider);
    await widget.ref
        .read(chatProvider.notifier)
        .updateModel(_selectedModel);

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.of(context).pop();
    }
  }

  Future<void> _showAddCustomProvider() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://');
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    String? formError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('إضافة مزوّد مخصص'),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (formError != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            formError!,
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                      const Text('اسم المزوّد:'),
                      const SizedBox(height: 4),
                      TextField(controller: nameCtrl),
                      const SizedBox(height: 12),
                      const Text('رابط الـ API الأساسي (Base URL):'),
                      const SizedBox(height: 4),
                      TextField(controller: urlCtrl),
                      const SizedBox(height: 12),
                      const Text('مفتاح API (اختياري):'),
                      const SizedBox(height: 4),
                      TextField(controller: keyCtrl, obscureText: true),
                      const SizedBox(height: 12),
                      const Text('اسم النموذج الافتراضي:'),
                      const SizedBox(height: 4),
                      TextField(controller: modelCtrl),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final url = urlCtrl.text.trim();
                    final model = modelCtrl.text.trim();
                    final key = keyCtrl.text.trim();

                    if (name.isEmpty || url.isEmpty || model.isEmpty) {
                      setDialogState(() {
                        formError = 'يرجى ملء الاسم والرابط واسم النموذج';
                      });
                      return;
                    }

                    final customId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                    final config = ProviderConfig(
                      id: customId,
                      displayName: name,
                      type: 'openai_compatible',
                      baseUrl: url,
                      defaultModel: model,
                      availableModels: [model],
                      isCustom: true,
                    );

                    await ProviderRegistry.addCustomProvider(config);
                    if (key.isNotEmpty) {
                      await SecureStorageService.saveApiKey(customId, key);
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                    await _switchProvider(customId);
                  },
                  child: const Text('إضافة'),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted) setState(() {});
  }

  Future<void> _deleteCustomProvider(String id) async {
    final config = ProviderRegistry.getConfig(id);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المزوّد المخصص'),
        content: Text('هل تريد حذف "${config?.displayName ?? id}" نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ProviderRegistry.deleteCustomProvider(id);
      if (_selectedProvider == id) {
        await _switchProvider('gemini');
      } else {
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final isCompact = screenWidth < 700;

    final dialogWidth = math.min(840.0, screenWidth - 24.0);
    final dialogHeight = math.min(620.0, screenHeight - 32.0);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final bgColor = isDark ? DesignTokens.bgDark : DesignTokens.bgLight;
    final surfaceColor = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    final allConfigs = ProviderRegistry.getAllConfigs();
    final activeConfig = ProviderRegistry.getConfig(_selectedProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      // إصلاح جذري لتأكيد ListTile: الحوار نفسه Material ملوّن (بدل
      // Container ملوّن فوق Material شفاف) فيكون أقرب Material لأي
      // ListTile داخله حاملاً اللون — فتظهر الـ ripple بشكل سليم ولا
      // يرمي الإطار أي تأكيد. الحدود والظل عبر shape/elevation.
      child: Material(
        color: bgColor,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          side: BorderSide(color: borderColor, width: DesignTokens.hairline),
        ),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            child: Column(
              children: [
            // ── Top Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.memory_rounded, size: 20, color: primaryTextColor),
                  const SizedBox(width: 8),
                  // إصلاح فيض: العنوان يتمدد ويُقصّ بدل أن يأخذ عرضه
                  // الطبيعي فيفيض الصف على النوافذ الضيقة
                  Expanded(
                    child: Text(
                      'اختيار مزوّد ونموذج الذكاء الاصطناعي',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeBase,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: secondaryTextColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: DesignTokens.hairline, color: borderColor),

            // ── Split View: Providers Sidebar + Models Browser ────────
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Sidebar: Providers List ──────────────────────
                  Container(
                    width: isCompact ? 72 : 220,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141418) : const Color(0xFFF3F3F7),
                      border: BorderDirectional(
                        end: BorderSide(color: borderColor, width: DesignTokens.hairline),
                      ),
                    ),
                    child: Column(
                      children: [
                        if (!isCompact)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                            child: Row(
                              children: [
                                Text(
                                  'المزوّدات',
                                  style: TextStyle(
                                    fontSize: DesignTokens.fontSizeXs,
                                    fontWeight: FontWeight.w600,
                                    color: secondaryTextColor,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${allConfigs.length}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            itemCount: allConfigs.length,
                            itemBuilder: (ctx, i) {
                              final config = allConfigs[i];
                              final isSelected = config.id == _selectedProvider;
                              return _buildProviderTile(
                                config: config,
                                isSelected: isSelected,
                                isCompact: isCompact,
                                isDark: isDark,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                              );
                            },
                          ),
                        ),
                        Divider(height: 1, color: borderColor),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: isCompact
                              ? IconButton(
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  tooltip: 'إضافة مزوّد مخصص',
                                  onPressed: _showAddCustomProvider,
                                )
                              : OutlinedButton.icon(
                                  onPressed: _showAddCustomProvider,
                                  icon: const Icon(Icons.add_rounded, size: 15),
                                  label: const Text(
                                    'إضافة مزوّد مخصص',
                                    style: TextStyle(fontSize: DesignTokens.fontSizeXs),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(34),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                  // ── Main Content: Models Browser ─────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Search bar & Filter Chips
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: borderColor,
                                width: DesignTokens.hairline,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.search_rounded, size: 17, color: secondaryTextColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchCtrl,
                                      focusNode: _searchFocus,
                                      style: const TextStyle(fontSize: DesignTokens.fontSizeSm),
                                      decoration: InputDecoration(
                                        hintText: 'ابحث في نماذج ${activeConfig?.displayName ?? ''}...',
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                  if (_searchCtrl.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _searchCtrl.clear();
                                        _searchFocus.requestFocus();
                                      },
                                      child: Icon(Icons.close_rounded, size: 16, color: secondaryTextColor),
                                    ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF222228) : const Color(0xFFEAEAEE),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${_filteredModels.length} نموذج',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Filter Chips
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildFilterChip('all', 'الكل', isDark, primaryTextColor, secondaryTextColor),
                                    const SizedBox(width: 4),
                                    _buildFilterChip('reasoning', '🧠 تفكير', isDark, primaryTextColor, secondaryTextColor),
                                    const SizedBox(width: 4),
                                    _buildFilterChip('code', '💻 كود', isDark, primaryTextColor, secondaryTextColor),
                                    const SizedBox(width: 4),
                                    _buildFilterChip('vision', '👁️ رؤية', isDark, primaryTextColor, secondaryTextColor),
                                    const SizedBox(width: 4),
                                    _buildFilterChip('fast', '⚡ سريع', isDark, primaryTextColor, secondaryTextColor),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // API Key row for current provider
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          color: isDark ? const Color(0xFF16161B) : const Color(0xFFF9F9FC),
                          child: Row(
                            children: [
                              Icon(Icons.key_outlined, size: 14, color: secondaryTextColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: _apiKeyCtrl,
                                  obscureText: _obscureKey,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: DesignTokens.fontFamilyMono,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _keyHint(_selectedProvider),
                                    hintStyle: TextStyle(fontSize: 11, color: secondaryTextColor),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onSubmitted: (_) => _fetchModels(),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  size: 14,
                                  color: secondaryTextColor,
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => setState(() => _obscureKey = !_obscureKey),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _isFetching ? null : _fetchModels,
                                icon: _isFetching
                                    ? const SizedBox(
                                        width: 10,
                                        height: 10,
                                        child: CircularProgressIndicator(strokeWidth: 1.2),
                                      )
                                    : const Icon(Icons.sync_rounded, size: 12),
                                label: const Text('تحديث النماذج', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (_fetchError != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            color: Colors.red.withValues(alpha: 0.1),
                            child: Text(
                              _fetchError!,
                              style: const TextStyle(fontSize: 11, color: Colors.red),
                            ),
                          ),

                        // Models List
                        Expanded(
                          child: _filteredModels.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off_rounded, size: 36, color: secondaryTextColor),
                                      const SizedBox(height: 8),
                                      Text(
                                        'لم يتم العثور على نماذج مطابقة',
                                        style: TextStyle(color: secondaryTextColor, fontSize: DesignTokens.fontSizeSm),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  itemCount: _filteredModels.length,
                                  itemBuilder: (ctx, i) {
                                    final model = _filteredModels[i];
                                    final isSelected = model == _selectedModel;
                                    final isCurrent = model == widget.ref.read(chatProvider).selectedModel &&
                                        _selectedProvider == widget.ref.read(chatProvider).selectedProviderId;

                                    return _buildModelItem(
                                      model: model,
                                      isSelected: isSelected,
                                      isCurrent: isCurrent,
                                      isDark: isDark,
                                      primaryTextColor: primaryTextColor,
                                      secondaryTextColor: secondaryTextColor,
                                      surfaceColor: surfaceColor,
                                      borderColor: borderColor,
                                    );
                                  },
                                ),
                        ),

                        // Bottom action bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF141418) : const Color(0xFFF7F7FA),
                            border: Border(
                              top: BorderSide(
                                color: borderColor,
                                width: DesignTokens.hairline,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // إصلاح فيض: اسم النموذج قد يكون طويلاً جداً
                              // (مثل nvidia/nemotron-3-ultra-550b-a55b) —
                              // Flexible مع قصّ يحفظ أزرار التأكيد ظاهرة دائماً
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'النموذج المحدد:',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10, color: secondaryTextColor),
                                    ),
                                    Text(
                                      _selectedModel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: DesignTokens.fontSizeXs,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: DesignTokens.fontFamilyMono,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('إلغاء'),
                              ),
                              const SizedBox(width: 8),
                              // النوافذ الضيقة: تسمية مختصرة حتى لا تفيض
                              // الأزرار ذاتها خارج الشريط (ثغرة حقيقية بخط
                              // الاختبار Ahem وعلى العربية الطويلة)
                              FilledButton(
                                onPressed: _isSaving ? null : _save,
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        isCompact
                                            ? 'تأكيد'
                                            : 'تأكيد واختيار النموذج',
                                      ),
                              ),
                            ],
                          ),
                        ),
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
      ),
    );
  }

  Widget _buildProviderTile({
    required ProviderConfig config,
    required bool isSelected,
    required bool isCompact,
    required bool isDark,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    final activeBg = isDark
        ? Colors.blue.withValues(alpha: 0.18)
        : Colors.blue.withValues(alpha: 0.12);
    final activeFg = isDark ? Colors.blue.shade300 : Colors.blue.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => _switchProvider(config.id),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 10,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Row(
            children: [
              _buildProviderIcon(config.id),
              if (!isCompact) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? activeFg : primaryTextColor,
                    ),
                  ),
                ),
                if (config.isCustom)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _deleteCustomProvider(config.id),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderIcon(String id) {
    IconData icon;
    Color color;
    switch (id) {
      case 'gemini':
        icon = Icons.auto_awesome_rounded;
        color = Colors.blue;
        break;
      case 'anthropic':
        icon = Icons.psychology_rounded;
        color = Colors.amber.shade700;
        break;
      case 'openai':
        icon = Icons.hub_rounded;
        color = Colors.teal;
        break;
      case 'groq':
        icon = Icons.bolt_rounded;
        color = Colors.orange;
        break;
      case 'deepseek':
        icon = Icons.explore_rounded;
        color = Colors.indigo;
        break;
      case 'openrouter':
        icon = Icons.alt_route_rounded;
        color = Colors.purple;
        break;
      case 'nvidia':
        icon = Icons.developer_board_rounded;
        color = Colors.green;
        break;
      default:
        icon = Icons.computer_rounded;
        color = Colors.grey;
    }
    return Icon(icon, size: 18, color: color);
  }

  Widget _buildFilterChip(
    String category,
    String label,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    final isSelected = _selectedCategory == category;
    return InkWell(
      onTap: () {
        setState(() => _selectedCategory = category);
        _applyFilter();
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.15))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? (isDark ? Colors.blue.shade400 : Colors.blue.shade700) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? (isDark ? Colors.blue.shade300 : Colors.blue.shade700) : secondaryTextColor,
          ),
        ),
      ),
    );
  }

  Widget _buildModelItem({
    required String model,
    required bool isSelected,
    required bool isCurrent,
    required bool isDark,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required Color surfaceColor,
    required Color borderColor,
  }) {
    // إصلاح تأكيد الإطار: كان ListTile ملفوفاً داخل Container ملوّن فيرمي
    // Flutter تأكيد «ink splashes may be invisible» — انتقل اللون إلى
    // tileColor المدمج (يرسمه ListTile نفسه فوق الـ Material بشكل سليم)
    // والهامش عبر Padding صرف.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        tileColor: isSelected
            ? (isDark ? const Color(0xFF1E2433) : const Color(0xFFEBF3FF))
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? (isDark ? Colors.blue.shade700 : Colors.blue.shade300)
                : Colors.transparent,
            width: 1,
          ),
        ),
        onTap: () => setState(() => _selectedModel = model),
        onLongPress: () {
          setState(() => _selectedModel = model);
          _save();
        },
        leading: Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
          size: 16,
          color: isSelected ? Colors.blue : secondaryTextColor,
        ),
        title: Text(
          model,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontFamily: DesignTokens.fontFamilyMono,
            color: isSelected ? primaryTextColor : primaryTextColor.withValues(alpha: 0.9),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCurrent)
              _buildBadge('الحالي', Colors.green, isDark),
            if (_isReasoningModel(model)) ...[
              const SizedBox(width: 4),
              _buildBadge('تفكير', Colors.purple, isDark),
            ],
            if (_isVisionModel(model)) ...[
              const SizedBox(width: 4),
              _buildBadge('رؤية', Colors.blue, isDark),
            ],
            if (_isFastModel(model)) ...[
              const SizedBox(width: 4),
              _buildBadge('سريع', Colors.amber, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  bool _isReasoningModel(String model) {
    final lower = model.toLowerCase();
    return lower.contains('r1') ||
        lower.contains('reason') ||
        lower.contains('thinking') ||
        lower.contains('o1') ||
        lower.contains('o3') ||
        lower.contains('nemotron');
  }

  bool _isCodeModel(String model) {
    final lower = model.toLowerCase();
    return lower.contains('coder') ||
        lower.contains('code') ||
        lower.contains('deepseek') ||
        lower.contains('qwen');
  }

  bool _isVisionModel(String model) {
    final lower = model.toLowerCase();
    return lower.contains('flash') ||
        lower.contains('vision') ||
        lower.contains('vl') ||
        lower.contains('gpt-4o') ||
        lower.contains('pro');
  }

  bool _isFastModel(String model) {
    final lower = model.toLowerCase();
    return lower.contains('flash') ||
        lower.contains('mini') ||
        lower.contains('8b') ||
        lower.contains('small');
  }

  String _keyHint(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'gemini':
        return 'AIzaSy... (Google AI Studio)';
      case 'anthropic':
        return 'sk-ant-... (Anthropic Console)';
      case 'openai':
        return 'sk-... (OpenAI Platform)';
      case 'groq':
        return 'gsk_... (Groq Console)';
      case 'deepseek':
        return 'sk-... (DeepSeek Platform)';
      case 'openrouter':
        return 'sk-or-... (OpenRouter)';
      case 'nvidia':
        return 'nvapi-... (build.nvidia.com)';
      default:
        return 'مفتاح API الخاص بهذا المزوّد...';
    }
  }
}
