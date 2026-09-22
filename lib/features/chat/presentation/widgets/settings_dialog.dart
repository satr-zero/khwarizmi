import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/core/theme/theme_controller.dart';
import 'package:khwarizmi/features/browser/services/agent_browser_service.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_controller.dart';
import 'package:khwarizmi/features/filesystem/services/file_system_service.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/providers/domain/provider_config.dart';
import 'package:khwarizmi/features/scheduler/services/windows_autostart_service.dart';
import 'package:khwarizmi/features/search/data/search_provider_registry.dart';
import 'package:khwarizmi/features/skills/presentation/screens/skills_settings_dialog.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  late final TextEditingController _apiKeyController;
  bool _obscureKey = true;
  String _selectedModel = 'gemini-3.8-flash';
  String _selectedProvider = 'gemini';
  bool _autostartEnabled = true;

  // Dynamic model fetching state
  List<String>? _fetchedModels;
  bool _isFetchingModels = false;
  String? _fetchError;

  // Search Provider State
  int _searchProviderMode = 0; // 0: DuckDuckGo, 1: Brave, 2: Custom
  final TextEditingController _braveKeyController = TextEditingController();
  bool _obscureBraveKey = true;
  final TextEditingController _customSearchUrlController = TextEditingController(text: 'https://');
  final TextEditingController _customSearchKeyController = TextEditingController();
  final TextEditingController _customSearchNameController = TextEditingController(text: 'Custom Search');
  bool _isSavingSearch = false;
  String _currentAllowedDir = FileSystemService.defaultAllowedDirectory;

  // Custom Provider Capability Test State
  bool _isTestingCapability = false;

  Future<void> _runCapabilityTest() async {
    setState(() {
      _isTestingCapability = true;
    });

    try {
      final success = await ProviderRegistry.runModelCapabilityTest(
        _selectedProvider,
        _apiKeyController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _isTestingCapability = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '✅ نجح الفحص: المزوّد يدعم استدعاء الأدوات (Tool Calling).'
                : '⚠️ تعذر استدعاء الأدوات مع هذا النموذج أو المزوّد.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTestingCapability = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final state = ref.read(chatProvider);
    _apiKeyController = TextEditingController(text: state.apiKey ?? '');
    _selectedModel = state.selectedModel;
    _selectedProvider = state.selectedProviderId;

    WindowsAutostartService.isAutostartEnabled().then((val) {
      if (mounted) setState(() => _autostartEnabled = val);
    });

    FileSystemService.instance.getAllowedDirectory().then((dir) {
      if (mounted) setState(() => _currentAllowedDir = dir);
    });

    if (state.apiKey != null && state.apiKey!.isNotEmpty) {
      _loadModelsForProvider(_selectedProvider, state.apiKey!);
    }

    _loadSearchConfig();
  }

  Future<void> _loadSearchConfig() async {
    final braveKey = await SearchProviderRegistry.getBraveApiKey() ?? '';
    final customUrl = await SearchProviderRegistry.getCustomSearchUrl() ?? '';
    final customName = await SearchProviderRegistry.getCustomSearchName() ?? 'Custom Search';
    final customKey = await SecureStorageService.getApiKey('custom_search') ?? '';

    if (!mounted) return;
    setState(() {
      if (customUrl.isNotEmpty) {
        _searchProviderMode = 2;
        _customSearchUrlController.text = customUrl;
        _customSearchNameController.text = customName;
        _customSearchKeyController.text = customKey;
      } else if (braveKey.isNotEmpty) {
        _searchProviderMode = 1;
        _braveKeyController.text = braveKey;
      } else {
        _searchProviderMode = 0;
      }
    });
  }

  Future<void> _saveSearchSettings() async {
    setState(() => _isSavingSearch = true);
    try {
      if (_searchProviderMode == 1) {
        final key = _braveKeyController.text.trim();
        await SearchProviderRegistry.saveBraveApiKey(key);
        await SearchProviderRegistry.clearCustomSearch();
      } else if (_searchProviderMode == 2) {
        final url = _customSearchUrlController.text.trim();
        final name = _customSearchNameController.text.trim();
        final key = _customSearchKeyController.text.trim();
        await SearchProviderRegistry.saveCustomSearch(
          url: url,
          name: name.isNotEmpty ? name : 'Custom Search',
          apiKey: key,
        );
      } else {
        await SearchProviderRegistry.clearBraveApiKey();
        await SearchProviderRegistry.clearCustomSearch();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ إعدادات مزوّد البحث بنجاح'),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingSearch = false);
    }
  }

  Future<void> _loadModelsForProvider(String providerId, String apiKey) async {
    if (apiKey.trim().isEmpty) return;
    final provider = ProviderRegistry.getProvider(providerId);

    setState(() {
      _isFetchingModels = true;
      _fetchError = null;
    });

    try {
      final models = await provider.fetchModels(apiKey.trim());
      if (!mounted) return;
      setState(() {
        _fetchedModels = models;
        _isFetchingModels = false;
        if (models.isNotEmpty && !models.contains(_selectedModel)) {
          _selectedModel = models.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFetchingModels = false;
        _fetchError = 'تعذر جلب قائمة النماذج';
      });
    }
  }

  Future<void> _onProviderChanged(String newProviderId) async {
    await ref.read(chatProvider.notifier).updateApiKey(_selectedProvider, _apiKeyController.text.trim());
    await ref.read(chatProvider.notifier).updateModel(_selectedModel);

    final key = await SecureStorageService.getApiKey(newProviderId) ?? '';
    final config = ProviderRegistry.getConfig(newProviderId);
    final savedModel = await SecureStorageService.getProviderModel(newProviderId) ?? config?.defaultModel ?? '';

    setState(() {
      _selectedProvider = newProviderId;
      _apiKeyController.text = key;
      _selectedModel = savedModel;
      _fetchedModels = null;
      _fetchError = null;
    });

    if (key.isNotEmpty) {
      _loadModelsForProvider(newProviderId, key);
    }
  }

  List<String> _getModelListForSelectedProvider() {
    if (_fetchedModels != null && _fetchedModels!.isNotEmpty) {
      return _fetchedModels!;
    }
    final config = ProviderRegistry.getConfig(_selectedProvider);
    if (config != null && config.availableModels.isNotEmpty) {
      return config.availableModels;
    }
    if (_selectedModel.isNotEmpty) {
      return [_selectedModel];
    }
    return const ['default-model'];
  }

  String _getApiKeyHint(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'gemini':
        return 'ألصق مفتاحك من Google AI Studio (يبدأ بـ AIzaSy...)';
      case 'claude':
        return 'ألصق مفتاحك من Anthropic Console (يبدأ بـ sk-ant-...)';
      case 'openai':
        return 'ألصق مفتاحك من OpenAI Platform (يبدأ بـ sk-...)';
      case 'groq':
        return 'ألصق مفتاحك من Groq Console (يبدأ بـ gsk_...)';
      case 'deepseek':
        return 'ألصق مفتاحك من DeepSeek Platform (يبدأ بـ sk-...)';
      case 'openrouter':
        return 'ألصق مفتاحك من OpenRouter (يبدأ بـ sk-or-...)';
      default:
        return 'ألصق مفتاح API الخاص بهذه الخدمة...';
    }
  }

  void _showAddCustomProviderDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://');
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('إضافة مزوّد ذكاء اصطناعي مخصص'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اسم المزوّد:'),
                  const SizedBox(height: DesignTokens.space4),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(hintText: 'مثال: Local Ollama أو vLLM'),
                  ),
                  const SizedBox(height: DesignTokens.space12),
                  const Text('رابط الـ API الأساسي (Base URL):'),
                  const SizedBox(height: DesignTokens.space4),
                  TextField(
                    controller: urlCtrl,
                    style: const TextStyle(fontFamily: DesignTokens.fontFamilyMono, fontSize: DesignTokens.fontSizeSm),
                    decoration: const InputDecoration(hintText: 'http://localhost:11434/v1'),
                  ),
                  const SizedBox(height: DesignTokens.space12),
                  const Text('مفتاح API (اختياري):'),
                  const SizedBox(height: DesignTokens.space4),
                  TextField(
                    controller: keyCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'ألصق المفتاح إن وجد...'),
                  ),
                  const SizedBox(height: DesignTokens.space12),
                  const Text('اسم النموذج (Model Name):'),
                  const SizedBox(height: DesignTokens.space4),
                  TextField(
                    controller: modelCtrl,
                    style: const TextStyle(fontFamily: DesignTokens.fontFamilyMono, fontSize: DesignTokens.fontSizeSm),
                    decoration: const InputDecoration(hintText: 'مثال: llama3 أو mistral'),
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
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final url = urlCtrl.text.trim();
                final model = modelCtrl.text.trim();
                final key = keyCtrl.text.trim();

                if (name.isEmpty || url.isEmpty || model.isEmpty) return;

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

                if (ctx.mounted) Navigator.of(ctx).pop();
                await _onProviderChanged(customId);
              },
              child: const Text('إضافة المزوّد'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final surfaceColor = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;

    final allConfigs = ProviderRegistry.getAllConfigs();
    final currentConfig = ProviderRegistry.getConfig(_selectedProvider) ?? allConfigs.first;

    final models = _getModelListForSelectedProvider();
    if (!models.contains(_selectedModel) && models.isNotEmpty) {
      _selectedModel = models.first;
    }

    final currentThemeMode = ref.watch(themeModeProvider);

    return Dialog(
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(DesignTokens.space24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.tune_outlined, size: 20, color: primaryTextColor),
                  const SizedBox(width: DesignTokens.space12),
                  Text(
                    'الإعدادات والمفاتيح',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeLg,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: secondaryTextColor, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space16),
              Divider(height: DesignTokens.hairline, thickness: DesignTokens.hairline, color: borderColor),
              const SizedBox(height: DesignTokens.space16),

              // ── Section 1: AI Providers ────────────────────────────────────
              _buildSectionHeader('مزوّدو الذكاء الاصطناعي (AI Providers)', primaryTextColor),
              const SizedBox(height: DesignTokens.space12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'المزوّد النشط:',
                    style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: secondaryTextColor),
                  ),
                  TextButton.icon(
                    onPressed: () => _showAddCustomProviderDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text('إضافة مزوّد مخصص', style: TextStyle(fontSize: DesignTokens.fontSizeXs)),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space12),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(color: borderColor, width: DesignTokens.hairline),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: allConfigs.any((c) => c.id == _selectedProvider) ? _selectedProvider : 'gemini',
                    isExpanded: true,
                    items: allConfigs.map((c) {
                      return DropdownMenuItem(
                        value: c.id,
                        child: Text(c.displayName, style: const TextStyle(fontSize: DesignTokens.fontSizeSm)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) _onProviderChanged(val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: DesignTokens.space12),

              // API Key
              Text(
                'مفتاح API الخاص بـ (${currentConfig.displayName}):',
                style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: secondaryTextColor),
              ),
              const SizedBox(height: DesignTokens.space4),
              TextField(
                controller: _apiKeyController,
                obscureText: _obscureKey,
                style: const TextStyle(
                  fontFamily: DesignTokens.fontFamilyMono,
                  fontFamilyFallback: DesignTokens.monoFallbacks,
                  fontSize: DesignTokens.fontSizeSm,
                ),
                decoration: InputDecoration(
                  hintText: _getApiKeyHint(_selectedProvider),
                  prefixIcon: Icon(Icons.key_outlined, size: 16, color: secondaryTextColor),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 16,
                      color: secondaryTextColor,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                onChanged: (val) {
                  if (val.trim().isNotEmpty && _fetchedModels == null) {
                    _loadModelsForProvider(_selectedProvider, val.trim());
                  }
                },
              ),
              const SizedBox(height: DesignTokens.space12),

              // Model Selection
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'النموذج المستخدم (Model):',
                    style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: secondaryTextColor),
                  ),
                  if (_apiKeyController.text.trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: _isFetchingModels
                          ? null
                          : () => _loadModelsForProvider(_selectedProvider, _apiKeyController.text.trim()),
                      icon: _isFetchingModels
                          ? SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: secondaryTextColor),
                            )
                          : const Icon(Icons.sync_rounded, size: 14),
                      label: const Text('تحديث قائمة النماذج', style: TextStyle(fontSize: DesignTokens.fontSizeXs)),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.space4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space12),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(color: borderColor, width: DesignTokens.hairline),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: models.contains(_selectedModel) ? _selectedModel : (models.isNotEmpty ? models.first : null),
                    isExpanded: true,
                    items: models.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(
                          m,
                          style: const TextStyle(
                            fontFamily: DesignTokens.fontFamilyMono,
                            fontFamilyFallback: DesignTokens.monoFallbacks,
                            fontSize: DesignTokens.fontSizeSm,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedModel = val);
                    },
                  ),
                ),
              ),
              if (_fetchError != null) ...[
                const SizedBox(height: DesignTokens.space4),
                Text(
                  _fetchError!,
                  style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                ),
              ],
              const SizedBox(height: DesignTokens.space8),

              // Custom Provider Capability Status & Test Button
              if (currentConfig.isCustom) ...[
                Container(
                  padding: const EdgeInsets.all(DesignTokens.space12),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    border: Border.all(color: borderColor, width: DesignTokens.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        currentConfig.toolCallCapable == true
                            ? Icons.check_circle_outline_rounded
                            : (currentConfig.toolCallCapable == false
                                ? Icons.warning_amber_rounded
                                : Icons.help_outline_rounded),
                        size: 18,
                        color: currentConfig.toolCallCapable == true
                            ? Colors.green
                            : (currentConfig.toolCallCapable == false ? Colors.amber : secondaryTextColor),
                      ),
                      const SizedBox(width: DesignTokens.space8),
                      Expanded(
                        child: Text(
                          currentConfig.toolCallCapable == true
                              ? 'يدعم استدعاء الأدوات (Tool Calling)'
                              : (currentConfig.toolCallCapable == false
                                  ? 'لا يدعم استدعاء الأدوات'
                                  : 'دعم الأدوات: لم يُختبر بعد'),
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: primaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isTestingCapability ? null : _runCapabilityTest,
                        icon: _isTestingCapability
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.5),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 14),
                        label: Text(
                          _isTestingCapability ? 'جارٍ الفحص...' : 'اختبر الأدوات',
                          style: const TextStyle(fontSize: DesignTokens.fontSizeXs),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignTokens.space8),
              ],

              // Agent identity line
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 14, color: secondaryTextColor),
                  const SizedBox(width: DesignTokens.space8),
                  Text(
                    'ملف الهوية AGENT.md: ${state.systemPrompt != null ? 'محمّل كـ System Prompt' : 'جارٍ التحميل...'}',
                    style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space16),
              Divider(height: DesignTokens.hairline, thickness: DesignTokens.hairline, color: borderColor),
              const SizedBox(height: DesignTokens.space16),

              // ── Section 2: Web Search Provider ─────────────────────────────
              _buildSectionHeader('مزوّد البحث على الويب (Web Search)', primaryTextColor),
              const SizedBox(height: DesignTokens.space12),

              _buildSearchRadioOption(
                value: 0,
                title: 'DuckDuckGo (افتراضي ومجاني — بدون مفتاح)',
                subtitle: 'يعمل تلقائياً ولا يتطلب أي مفتاح أو إعداد.',
                isDark: isDark,
                borderColor: borderColor,
              ),
              const SizedBox(height: DesignTokens.space8),
              _buildSearchRadioOption(
                value: 1,
                title: 'Brave Search (موصى به)',
                subtitle: '2000 استعلام مجاني شهرياً مع نتائج فائقة الدقة.',
                isDark: isDark,
                borderColor: borderColor,
              ),
              if (_searchProviderMode == 1) ...[
                const SizedBox(height: DesignTokens.space8),
                TextField(
                  controller: _braveKeyController,
                  obscureText: _obscureBraveKey,
                  style: const TextStyle(fontFamily: DesignTokens.fontFamilyMono, fontSize: DesignTokens.fontSizeSm),
                  decoration: InputDecoration(
                    hintText: 'BSA... (مفتاح Brave Search API)',
                    prefixIcon: Icon(Icons.key_outlined, size: 16, color: secondaryTextColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureBraveKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 16,
                        color: secondaryTextColor,
                      ),
                      onPressed: () => setState(() => _obscureBraveKey = !_obscureBraveKey),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: DesignTokens.space8),
              _buildSearchRadioOption(
                value: 2,
                title: 'مزوّد بحث مخصص (Custom Endpoint)',
                subtitle: 'خدمة بحث خارجية متوافقة مع REST API.',
                isDark: isDark,
                borderColor: borderColor,
              ),
              if (_searchProviderMode == 2) ...[
                const SizedBox(height: DesignTokens.space8),
                TextField(
                  controller: _customSearchNameController,
                  decoration: const InputDecoration(hintText: 'اسم العرض (مثال: SerpAPI)'),
                ),
                const SizedBox(height: DesignTokens.space8),
                TextField(
                  controller: _customSearchUrlController,
                  style: const TextStyle(fontFamily: DesignTokens.fontFamilyMono, fontSize: DesignTokens.fontSizeSm),
                  decoration: const InputDecoration(hintText: 'https://api.example.com/search'),
                ),
                const SizedBox(height: DesignTokens.space8),
                TextField(
                  controller: _customSearchKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'مفتاح API (اختياري)'),
                ),
              ],
              const SizedBox(height: DesignTokens.space8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton.icon(
                  onPressed: _isSavingSearch ? null : _saveSearchSettings,
                  icon: _isSavingSearch
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: secondaryTextColor),
                        )
                      : const Icon(Icons.save_outlined, size: 14),
                  label: const Text('حفظ إعدادات البحث', style: TextStyle(fontSize: DesignTokens.fontSizeXs)),
                ),
              ),

              const SizedBox(height: DesignTokens.space16),
              Divider(height: DesignTokens.hairline, thickness: DesignTokens.hairline, color: borderColor),
              const SizedBox(height: DesignTokens.space16),

              // ── Section 3: Filesystem & Dedicated Browser ──────────────────
              _buildSectionHeader('نظام الملفات والمتصفح المستقل (Sandbox)', primaryTextColor),
              const SizedBox(height: DesignTokens.space12),

              Text(
                'المجلد المسموح به لقراءة وكتابة الملفات:',
                style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: secondaryTextColor),
              ),
              const SizedBox(height: DesignTokens.space4),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.space12,
                        vertical: DesignTokens.space8,
                      ),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                        border: Border.all(color: borderColor, width: DesignTokens.hairline),
                      ),
                      child: Text(
                        _currentAllowedDir,
                        style: const TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontFamilyFallback: DesignTokens.monoFallbacks,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_outlined, size: 14),
                    label: const Text('تغيير...', style: TextStyle(fontSize: DesignTokens.fontSizeXs)),
                    onPressed: () async {
                      final selected = await FilePicker.getDirectoryPath(
                        dialogTitle: 'اختر مجلد العمليات المسموح لخوارزمي',
                      );
                      if (selected != null && selected.isNotEmpty) {
                        await FileSystemService.instance.setAllowedDirectory(selected);
                        setState(() => _currentAllowedDir = selected);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space12),

              // Sandbox Paths info
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      'ملف تعريف المتصفح (معزول)',
                      AgentBrowserService.profileDirectory,
                      borderColor,
                      surfaceColor,
                      secondaryTextColor,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space8),
                  Expanded(
                    child: _buildInfoItem(
                      'مجلد التنزيلات المخصص',
                      AgentBrowserService.downloadDirectory,
                      borderColor,
                      surfaceColor,
                      secondaryTextColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: DesignTokens.space16),
              Divider(height: DesignTokens.hairline, thickness: DesignTokens.hairline, color: borderColor),
              const SizedBox(height: DesignTokens.space16),

              // ── Section 4: Scheduling & Autostart ──────────────────────────
              _buildSectionHeader('الجدولة والتشغيل مع إقلاع النظام', primaryTextColor),
              const SizedBox(height: DesignTokens.space12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'التشغيل التلقائي مع بدء تشغيل Windows',
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeSm,
                            fontWeight: FontWeight.w500,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'تشغيل خوارزمي في الخلفية عند إقلاع النظام لضمان عمل التنبيهات بلا انقطاع.',
                          style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space8),
                  Switch(
                    value: _autostartEnabled,
                    onChanged: (val) async {
                      setState(() => _autostartEnabled = val);
                      await WindowsAutostartService.setAutostart(val);
                    },
                  ),
                ],
              ),

              const SizedBox(height: DesignTokens.space16),
              Divider(height: DesignTokens.hairline, thickness: DesignTokens.hairline, color: borderColor),
              const SizedBox(height: DesignTokens.space16),

              // ── Section 5: Appearance & Theme Mode ─────────────────────────
              _buildSectionHeader('المظهر ونظام الألوان (Appearance)', primaryTextColor),
              const SizedBox(height: DesignTokens.space12),

              Row(
                children: [
                  Expanded(
                    child: _buildThemeModeOption(
                      mode: ThemeMode.system,
                      title: 'نظام Windows',
                      icon: Icons.brightness_auto_outlined,
                      current: currentThemeMode,
                      isDark: isDark,
                      borderColor: borderColor,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space8),
                  Expanded(
                    child: _buildThemeModeOption(
                      mode: ThemeMode.light,
                      title: 'الوضع النهاري',
                      icon: Icons.light_mode_outlined,
                      current: currentThemeMode,
                      isDark: isDark,
                      borderColor: borderColor,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space8),
                  Expanded(
                    child: _buildThemeModeOption(
                      mode: ThemeMode.dark,
                      title: 'الوضع الليلي',
                      icon: Icons.dark_mode_outlined,
                      current: currentThemeMode,
                      isDark: isDark,
                      borderColor: borderColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: DesignTokens.space20),

              // ── Section 4: Skills & Plugins ────────────────────────────────
              _buildSectionHeader('نظام الإضافات (Skills & Plugins)', primaryTextColor),
              const SizedBox(height: DesignTokens.space8),
              Container(
                padding: const EdgeInsets.all(DesignTokens.space12),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(color: borderColor, width: DesignTokens.hairline),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.extension_outlined, size: 22, color: Colors.teal),
                    const SizedBox(width: DesignTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الإضافات والقدرات الخارجية (Skills)',
                            style: TextStyle(
                              fontSize: DesignTokens.fontSizeSm,
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'إدارة وتفعيل الإضافات الخارجية التي تعمل كعمليات مستقلة (Sidecars).',
                            style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        SkillsSettingsDialog.show(context);
                      },
                      icon: const Icon(Icons.tune_rounded, size: 14),
                      label: const Text('إدارة Skills'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: DesignTokens.space24),

              // ── Action Buttons ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: DesignTokens.space12),
                  ElevatedButton(
                    onPressed: () async {
                      final key = _apiKeyController.text.trim();
                      await ref.read(chatProvider.notifier).updateApiKey(_selectedProvider, key);
                      await ref.read(chatProvider.notifier).updateProvider(_selectedProvider);
                      await ref.read(chatProvider.notifier).updateModel(_selectedModel);

                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم حفظ الإعدادات ومفتاح API لـ (${currentConfig.displayName}) بأمان!'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: const Text('حفظ التغييرات'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        fontSize: DesignTokens.fontSizeBase,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    );
  }

  Widget _buildSearchRadioOption({
    required int value,
    required String title,
    required String subtitle,
    required bool isDark,
    required Color borderColor,
  }) {
    final isSelected = _searchProviderMode == value;
    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    return InkWell(
      onTap: () => setState(() => _searchProviderMode = value),
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space12,
          vertical: DesignTokens.space8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? DesignTokens.hoverDark : DesignTokens.hoverLight) : surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(
            color: isSelected ? primaryTextColor : borderColor,
            width: isSelected ? DesignTokens.hairlineThick : DesignTokens.hairline,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: isSelected ? primaryTextColor : secondaryTextColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeModeOption({
    required ThemeMode mode,
    required String title,
    required IconData icon,
    required ThemeMode current,
    required bool isDark,
    required Color borderColor,
  }) {
    final isSelected = mode == current;
    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    return InkWell(
      onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(mode),
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.space12,
          horizontal: DesignTokens.space8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? DesignTokens.hoverDark : DesignTokens.hoverLight) : surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(
            color: isSelected ? primaryTextColor : borderColor,
            width: isSelected ? DesignTokens.hairlineThick : DesignTokens.hairline,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: isSelected ? primaryTextColor : secondaryTextColor),
            const SizedBox(height: DesignTokens.space4),
            Text(
              title,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? primaryTextColor : secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    String title,
    String value,
    Color borderColor,
    Color surfaceColor,
    Color secondaryTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.space8),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: borderColor, width: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: DesignTokens.fontSizeXs, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontFamily: DesignTokens.fontFamilyMono,
              fontFamilyFallback: DesignTokens.monoFallbacks,
              color: secondaryTextColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
