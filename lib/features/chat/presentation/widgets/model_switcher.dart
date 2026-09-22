import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

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

    return Tooltip(
      message: 'تغيير النموذج أو المزوّد ($providerName / ${chatState.selectedModel})',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          onTap: () => _openSwitcher(context, ref),
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
                  ? Border.all(color: borderColor, width: DesignTokens.hairline)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.memory_rounded,
                  size: compact ? 13 : 15,
                  color: secondaryTextColor,
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
                            color: secondaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: '/ ${chatState.selectedModel}',
                          style: TextStyle(
                            fontSize: compact
                                ? DesignTokens.fontSizeXs
                                : DesignTokens.fontSizeSm,
                            color: primaryTextColor,
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
                  color: secondaryTextColor,
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
// الحوار الرئيسي — منتقي النموذج والمزوّد مع تكيف كامل لكل الأحجام
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

    // تركيز البحث فور فتح النافذة
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
      _filteredModels = q.isEmpty
          ? List.from(_allModels)
          : _allModels.where((m) => m.toLowerCase().contains(q)).toList();
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

  /// نافذة إضافة مزوّد مخصص مع حقول تفاعلية وتحقق
  Future<void> _showAddCustomProvider() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryTextColor = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://');
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final extraCtrl = TextEditingController();

    String? formError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final media = MediaQuery.of(ctx);
            final dialogWidth = math.min(480.0, media.size.width - 32.0);

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'إضافة مزوّد مخصص',
                    style: TextStyle(fontSize: DesignTokens.fontSizeBase),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth,
                  maxHeight: media.size.height * 0.78,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'يدعم أي خادم متوافق مع OpenAI API مثل (Ollama، LM Studio، vLLM، Together AI، إلخ).',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space12),

                      if (formError != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: DesignTokens.space12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.space12,
                            vertical: DesignTokens.space8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusSm),
                            border: Border.all(
                                color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: Colors.red, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  formError!,
                                  style: const TextStyle(
                                    fontSize: DesignTokens.fontSizeXs,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // الاسم
                      const Text(
                        'اسم المزوّد *',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space4),
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'مثال: Ollama محلي أو Together AI',
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space12),

                      // Base URL
                      const Text(
                        'رابط الـ API الأساسي (Base URL) *',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space4),
                      TextField(
                        controller: urlCtrl,
                        style: const TextStyle(
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontSize: DesignTokens.fontSizeSm,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'http://localhost:11434/v1 أو https://api.together.xyz/v1',
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space12),

                      // API Key
                      const Text(
                        'مفتاح API (اختياري للخوادم المحلية)',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space4),
                      TextField(
                        controller: keyCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'اتركه فارغاً لـ Ollama أو أدخل مفتاحك',
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space12),

                      // النموذج الافتراضي
                      const Text(
                        'النموذج الافتراضي *',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space4),
                      TextField(
                        controller: modelCtrl,
                        style: const TextStyle(
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontSize: DesignTokens.fontSizeSm,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'مثال: llama3 أو mistral أو qwen2.5',
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space12),

                      // Extra Body Params
                      const Text(
                        'معاملات طلب إضافية (JSON اختياري)',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space4),
                      TextField(
                        controller: extraCtrl,
                        style: const TextStyle(
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontSize: DesignTokens.fontSizeXs,
                        ),
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: '{"temperature": 0.7, "max_tokens": 4096}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('إضافة وتطبيق'),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final url = urlCtrl.text.trim();
                    final model = modelCtrl.text.trim();
                    final key = keyCtrl.text.trim();
                    final extraRaw = extraCtrl.text.trim();

                    if (name.isEmpty || url.isEmpty || model.isEmpty) {
                      setDialogState(() {
                        formError = 'يرجى ملء كافة الحقول الإلزامية المؤشر عليها (*)';
                      });
                      return;
                    }

                    Map<String, dynamic> extraParams = {};
                    if (extraRaw.isNotEmpty) {
                      try {
                        final decoded = jsonDecode(extraRaw);
                        if (decoded is Map<String, dynamic>) {
                          extraParams = decoded;
                        } else {
                          setDialogState(() {
                            formError = 'المعاملات الإضافية يجب أن تكون كائن JSON صالح {...}';
                          });
                          return;
                        }
                      } catch (e) {
                        setDialogState(() {
                          formError = 'صيغة JSON غير صحيحة: $e';
                        });
                        return;
                      }
                    }

                    final customId =
                        'custom_${DateTime.now().millisecondsSinceEpoch}';
                    final config = ProviderConfig(
                      id: customId,
                      displayName: name,
                      type: 'openai_compatible',
                      baseUrl: url,
                      defaultModel: model,
                      availableModels: [model],
                      isCustom: true,
                      extraBodyParams: extraParams,
                    );

                    await ProviderRegistry.addCustomProvider(config);
                    if (key.isNotEmpty) {
                      await SecureStorageService.saveApiKey(customId, key);
                    }

                    if (ctx.mounted) Navigator.of(ctx).pop();

                    // التبديل التلقائي للمزوّد المضاف
                    await _switchProvider(customId);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted) setState(() {});
  }

  /// حذف مزوّد مخصص
  Future<void> _deleteCustomProvider(String id) async {
    final config = ProviderRegistry.getConfig(id);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المزوّد المخصص'),
        content: Text(
          'هل تريد حذف مزوّد "${config?.displayName ?? id}" نهائياً من خوارزمي؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
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

    final isCompact = screenWidth < 520;
    final isShort = screenHeight < 640;

    // حساب أبعاد متجاوبة ومرنة تناسب الشاشات الكبيرة والمصغرة
    final dialogWidth = math.min(580.0, screenWidth - (isCompact ? 16.0 : 40.0));
    final dialogMaxHeight =
        math.min(650.0, screenHeight - (isShort ? 24.0 : 64.0));
    final topMargin = isShort ? 12.0 : (isCompact ? 24.0 : 48.0);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final bgColor = isDark ? DesignTokens.bgDark : DesignTokens.bgLight;
    final primaryTextColor =
        isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final hoverColor =
        isDark ? DesignTokens.hoverDark : DesignTokens.hoverLight;

    final allConfigs = ProviderRegistry.getAllConfigs();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: EdgeInsets.only(top: topMargin),
          width: dialogWidth,
          constraints: BoxConstraints(maxHeight: dialogMaxHeight),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(
                isCompact ? DesignTokens.radiusMd : DesignTokens.radiusLg),
            border: Border.all(color: borderColor, width: DesignTokens.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header: Search Bar ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.space16,
                  DesignTokens.space12,
                  DesignTokens.space16,
                  DesignTokens.space8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: secondaryTextColor,
                    ),
                    const SizedBox(width: DesignTokens.space8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        style: const TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                        ),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن نموذج أو مرشّح...',
                          hintStyle: TextStyle(
                            fontSize: DesignTokens.fontSizeSm,
                            color: secondaryTextColor,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) {
                          if (_filteredModels.isNotEmpty) {
                            setState(
                                () => _selectedModel = _filteredModels.first);
                          }
                        },
                      ),
                    ),
                    if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          _searchFocus.requestFocus();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hoverColor,
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 13, color: secondaryTextColor),
                        ),
                      ),
                    const SizedBox(width: DesignTokens.space8),
                    // شارة عدد النماذج
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: hoverColor,
                        borderRadius:
                            BorderRadius.circular(999),
                        border: Border.all(
                          color: borderColor,
                          width: DesignTokens.hairline,
                        ),
                      ),
                      child: Text(
                        '${_filteredModels.length}',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          fontWeight: FontWeight.w600,
                          color: secondaryTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.space8),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: secondaryTextColor),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'إغلاق',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              Divider(
                height: DesignTokens.hairline,
                thickness: DesignTokens.hairline,
                color: borderColor,
              ),

              // ── Provider Tabs Bar ──────────────────────────────────────────
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                          },
                        ),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.space12),
                          itemCount: allConfigs.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: DesignTokens.space4),
                          itemBuilder: (ctx, i) {
                            final c = allConfigs[i];
                            final isSelected = c.id == _selectedProvider;

                            return GestureDetector(
                              onTap: () => _switchProvider(c.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: DesignTokens.space12,
                                  vertical: DesignTokens.space4,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? hoverColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                      DesignTokens.radiusSm),
                                  border: Border.all(
                                    color: isSelected
                                        ? borderColor
                                        : Colors.transparent,
                                    width: DesignTokens.hairline,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _shortProviderTabName(c.displayName),
                                      style: TextStyle(
                                        fontSize: DesignTokens.fontSizeXs,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? primaryTextColor
                                            : secondaryTextColor,
                                      ),
                                    ),
                                    if (c.isCustom) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? primaryTextColor
                                              : secondaryTextColor,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () =>
                                            _deleteCustomProvider(c.id),
                                        child: Icon(
                                          Icons.delete_outline_rounded,
                                          size: 13,
                                          color: isSelected
                                              ? primaryTextColor
                                              : secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // زر + إضافة مزوّد مخصص
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.space8),
                      child: Tooltip(
                        message: 'إضافة مزوّد مخصص جديد (OpenAI Compatible)',
                        child: InkWell(
                          onTap: _showAddCustomProvider,
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusSm),
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(
                                horizontal: DesignTokens.space8),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(DesignTokens.radiusSm),
                              border: Border.all(
                                color: borderColor,
                                width: DesignTokens.hairline,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  size: 15,
                                  color: secondaryTextColor,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'مخصص',
                                  style: TextStyle(
                                    fontSize: DesignTokens.fontSizeXs,
                                    color: secondaryTextColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(
                height: DesignTokens.hairline,
                thickness: DesignTokens.hairline,
                color: borderColor,
              ),

              // ── API Key Input Row ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.space12,
                  DesignTokens.space8,
                  DesignTokens.space12,
                  DesignTokens.space4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _apiKeyCtrl,
                        obscureText: _obscureKey,
                        style: const TextStyle(
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontFamilyFallback: DesignTokens.monoFallbacks,
                          fontSize: DesignTokens.fontSizeXs,
                        ),
                        decoration: InputDecoration(
                          hintText: _keyHint(_selectedProvider),
                          hintStyle: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: secondaryTextColor,
                          ),
                          prefixIcon: Icon(
                            Icons.key_outlined,
                            size: 14,
                            color: secondaryTextColor,
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 14,
                                  color: secondaryTextColor,
                                ),
                                onPressed: () => setState(
                                    () => _obscureKey = !_obscureKey),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: _obscureKey ? 'إظهار المفتاح' : 'إخفاء',
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: _isFetching
                                    ? SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: secondaryTextColor,
                                        ),
                                      )
                                    : Icon(
                                        Icons.sync_rounded,
                                        size: 15,
                                        color: secondaryTextColor,
                                      ),
                                tooltip: 'تحديث وجلب قائمة النماذج الحية',
                                onPressed:
                                    _isFetching ? null : _fetchModels,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: DesignTokens.space8),
                            ],
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.space8,
                            vertical: 8,
                          ),
                        ),
                        onChanged: (v) {
                          setState(() => _apiKey = v);
                          if (v.trim().length > 10) {
                            _debounce?.cancel();
                            _debounce = Timer(
                              const Duration(milliseconds: 700),
                              _fetchModels,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              if (_fetchError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.space12,
                    0,
                    DesignTokens.space12,
                    DesignTokens.space4,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 12, color: Colors.orange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _fetchError!,
                          style: const TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: Colors.orange,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              Divider(
                height: DesignTokens.hairline,
                thickness: DesignTokens.hairline,
                color: borderColor,
              ),

              // ── Models List (Flexible & Adaptive) ──────────────────────────
              Flexible(
                child: _filteredModels.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(DesignTokens.space24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _searchCtrl.text.isNotEmpty
                                    ? Icons.search_off_rounded
                                    : Icons.model_training_rounded,
                                size: 32,
                                color: secondaryTextColor,
                              ),
                              const SizedBox(height: DesignTokens.space8),
                              Text(
                                _searchCtrl.text.isNotEmpty
                                    ? 'لا توجد نماذج تطابق: "${_searchCtrl.text}"'
                                    : (_apiKeyCtrl.text.trim().isEmpty
                                        ? 'أدخل مفتاح API لهذا المزوّد لتحديث قائمة النماذج'
                                        : 'لم يتم العثور على نماذج لهذا المزوّد'),
                                style: TextStyle(
                                  fontSize: DesignTokens.fontSizeSm,
                                  color: secondaryTextColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (_searchCtrl.text.isNotEmpty) ...[
                                const SizedBox(height: DesignTokens.space8),
                                TextButton(
                                  onPressed: () => _searchCtrl.clear(),
                                  child: const Text('مسح البحث'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredModels.length,
                        padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.space4,
                          horizontal: DesignTokens.space8,
                        ),
                        itemBuilder: (ctx, i) {
                          final model = _filteredModels[i];
                          final isSelected = model == _selectedModel;
                          final currentActive =
                              widget.ref.read(chatProvider).selectedModel;
                          final isCurrent = model == currentActive &&
                              _selectedProvider ==
                                  widget.ref.read(chatProvider).selectedProviderId;

                          return InkWell(
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusSm),
                            onTap: () =>
                                setState(() => _selectedModel = model),
                            onDoubleTap: () {
                              setState(() => _selectedModel = model);
                              _save();
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 1.5),
                              padding: const EdgeInsets.symmetric(
                                horizontal: DesignTokens.space12,
                                vertical: DesignTokens.space8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? hoverColor
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusSm),
                                border: isSelected
                                    ? Border.all(
                                        color: borderColor,
                                        width: DesignTokens.hairline)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  // دائرة الاختيار
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? primaryTextColor
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? primaryTextColor
                                            : secondaryTextColor.withValues(alpha: 0.4),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: DesignTokens.space8),

                                  // اسم النموذج
                                  Expanded(
                                    child: Text(
                                      model,
                                      style: TextStyle(
                                        fontSize: DesignTokens.fontSizeSm,
                                        fontFamily: DesignTokens.fontFamilyMono,
                                        fontFamilyFallback:
                                            DesignTokens.monoFallbacks,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? primaryTextColor
                                            : secondaryTextColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),

                                  // شارات توضيحية ذكية
                                  if (isCurrent) ...[
                                    const SizedBox(width: 4),
                                    _buildBadge(
                                      label: 'الحالي',
                                      color: Colors.green,
                                      isDark: isDark,
                                    ),
                                  ],

                                  if (_isReasoningModel(model)) ...[
                                    const SizedBox(width: 4),
                                    _buildBadge(
                                      label: 'تفكير',
                                      color: Colors.purple,
                                      icon: Icons.psychology_rounded,
                                      isDark: isDark,
                                    ),
                                  ],

                                  if (isSelected) ...[
                                    const SizedBox(width: DesignTokens.space8),
                                    Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: primaryTextColor,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              Divider(
                height: DesignTokens.hairline,
                thickness: DesignTokens.hairline,
                color: borderColor,
              ),

              // ── Responsive Footer ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.space12,
                  vertical: DesignTokens.space8,
                ),
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 12,
                                color: secondaryTextColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'نقر مزدوج للتطبيق الفوري',
                                  style: TextStyle(
                                    fontSize: DesignTokens.fontSizeXs,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: DesignTokens.space8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('إلغاء'),
                              ),
                              const SizedBox(width: DesignTokens.space8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: DesignTokens.space16,
                                    vertical: DesignTokens.space8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        DesignTokens.radiusSm),
                                  ),
                                ),
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded, size: 14),
                                label: Text(_isSaving ? 'حفظ...' : 'تطبيق'),
                                onPressed: _isSaving ? null : _save,
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: secondaryTextColor,
                          ),
                          const SizedBox(width: DesignTokens.space4),
                          Expanded(
                            child: Text(
                              'نقر مزدوج للتطبيق الفوري — أو اختر ثم اضغط تطبيق',
                              style: TextStyle(
                                fontSize: DesignTokens.fontSizeXs,
                                color: secondaryTextColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('إلغاء'),
                          ),
                          const SizedBox(width: DesignTokens.space8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: DesignTokens.space16,
                                vertical: DesignTokens.space8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusSm),
                              ),
                            ),
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 14),
                            label: Text(
                              _isSaving ? 'جارٍ الحفظ...' : 'تطبيق',
                              style: const TextStyle(
                                  fontSize: DesignTokens.fontSizeSm),
                            ),
                            onPressed: _isSaving ? null : _save,
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

  Widget _buildBadge({
    required String label,
    required Color color,
    IconData? icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: DesignTokens.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
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

  String _shortProviderTabName(String name) {
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
    return map[name] ??
        (name.length > 12 ? '${name.substring(0, 10)}…' : name);
  }

  String _keyHint(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'gemini':
        return 'AIzaSy... (Google AI Studio)';
      case 'claude':
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
        return 'مفتاح API الخاص بهذا المزوّد (اختياري إن كان محلياً)...';
    }
  }
}
