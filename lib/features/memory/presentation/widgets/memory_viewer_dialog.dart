import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_controller.dart';
import 'package:khwarizmi/features/memory/data/memory_repository.dart';
import 'package:khwarizmi/features/memory/domain/entities/memory_entry.dart';

class MemoryViewerDialog extends ConsumerStatefulWidget {
  const MemoryViewerDialog({super.key});

  @override
  ConsumerState<MemoryViewerDialog> createState() => _MemoryViewerDialogState();
}

class _MemoryViewerDialogState extends ConsumerState<MemoryViewerDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<MemoryEntry> _memories = [];
  bool _isLoading = false;
  final Set<String> _expandedMemoryIds = {};
  Future<int>? _pendingCountFuture;

  @override
  void initState() {
    super.initState();
    _loadAllMemories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllMemories() async {
    try {
      final mems = await MemoryRepository.getAllMemories(limit: 100);
      if (!mounted) return;
      setState(() {
        _memories = mems;
        _pendingCountFuture = MemoryRepository.getPendingEmbeddingsCount();
      });
    } catch (_) {}
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      _loadAllMemories();
      return;
    }

    setState(() => _isLoading = true);
    final apiKey = ref.read(chatProvider).apiKey;

    try {
      final scored = await MemoryRepository.searchMemory(
        query: query.trim(),
        limit: 20,
        minScore: 0.1,
        apiKey: apiKey,
      );

      if (!mounted) return;
      setState(() {
        _memories = scored.map((s) => s.entry).toList();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddMemoryDialog() async {
    final contentCtrl = TextEditingController();
    final categoryCtrl = TextEditingController(text: 'preference');
    int importance = 3;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('إضافة معلومة للذاكرة يدويًا'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: contentCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'مثال: يفضل المستخدم التحدث باللغة العربية الفصحى...',
                        labelText: 'نص المعلومة أو الحقيقة',
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space12),
                    TextField(
                      controller: categoryCtrl,
                      decoration: const InputDecoration(
                        hintText: 'preference / person / work / general',
                        labelText: 'التصنيف (Category)',
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space12),
                    Row(
                      children: [
                        const Text('مستوى الأهمية:', style: TextStyle(fontSize: DesignTokens.fontSizeSm)),
                        const SizedBox(width: DesignTokens.space12),
                        DropdownButton<int>(
                          value: importance,
                          items: [1, 2, 3, 4, 5].map((i) {
                            return DropdownMenuItem(
                              value: i,
                              child: Text('⭐ $i'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setModalState(() => importance = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final text = contentCtrl.text.trim();
                    if (text.isEmpty) return;

                    final apiKey = ref.read(chatProvider).apiKey;
                    await MemoryRepository.storeMemory(
                      content: text,
                      category: categoryCtrl.text.trim().isEmpty ? 'general' : categoryCtrl.text.trim(),
                      importance: importance,
                      apiKey: apiKey,
                    );

                    if (ctx.mounted) Navigator.of(ctx).pop();
                    _loadAllMemories();
                  },
                  child: const Text('حفظ بالذاكرة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final dateFormat = DateFormat('yyyy-MM-dd – HH:mm');

    return Dialog(
      child: Container(
        width: 680,
        height: 620,
        padding: const EdgeInsets.all(DesignTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Icon(Icons.storage_outlined, size: 20, color: primaryTextColor),
                const SizedBox(width: DesignTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الذاكرة الدائمة',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeLg,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      Text(
                        'تخزين محلي مع متجهات دلالية وبحث هجين',
                        style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DesignTokens.space8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('إضافة ذكرى'),
                  onPressed: _showAddMemoryDialog,
                ),
                const SizedBox(width: DesignTokens.space4),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: secondaryTextColor, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.space16),
            Divider(height: DesignTokens.hairline, thickness: DesignTokens.hairline, color: borderColor),
            const SizedBox(height: DesignTokens.space12),

            // Search Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث بالمعنى الدلالي أو الكلمات المفتاحية في الذاكرة...',
                      prefixIcon: Icon(Icons.search_rounded, size: 18, color: secondaryTextColor),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, size: 16, color: secondaryTextColor),
                              onPressed: () {
                                _searchController.clear();
                                _loadAllMemories();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: _performSearch,
                  ),
                ),
                const SizedBox(width: DesignTokens.space8),
                IconButton.filled(
                  icon: _isLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? DesignTokens.bgDark : DesignTokens.bgLight,
                            ),
                          ),
                        )
                      : const Icon(Icons.arrow_forward_rounded, size: 16),
                  onPressed: () => _performSearch(_searchController.text),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.space12),

            // Subtitle status bar
            Row(
              children: [
                Text(
                  'عدد الذكريات: ${_memories.length}',
                  style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                ),
                const SizedBox(width: DesignTokens.space12),

                FutureBuilder<int>(
                  future: _pendingCountFuture,
                  builder: (context, snap) {
                    final count = snap.data ?? 0;
                    if (count <= 0) return const SizedBox.shrink();
                    return TextButton.icon(
                      icon: const Icon(Icons.sync_rounded, size: 14),
                      label: Text(
                        'توليد المتجهات الدلالية ($count)',
                        style: const TextStyle(fontSize: DesignTokens.fontSizeXs),
                      ),
                      onPressed: () async {
                        final apiKey = ref.read(chatProvider).apiKey;
                        if (apiKey != null && apiKey.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('جارٍ توليد المتجهات للذكريات...')),
                          );
                          await MemoryRepository.syncPendingEmbeddings(apiKey);
                          _loadAllMemories();
                        }
                      },
                    );
                  },
                ),
                const Spacer(),

                if (_memories.isNotEmpty)
                  TextButton.icon(
                    icon: Icon(Icons.delete_outline_rounded, size: 14, color: secondaryTextColor),
                    label: Text(
                      'مسح الكل',
                      style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('تأكيد مسح الذاكرة بالكامل'),
                          content: const Text('هل أنت متأكد من رغبتك في حذف جميع الذكريات؟ لا يمكن التراجع عن هذا الإجراء.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('إلغاء'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('نعم، امسح الذاكرة'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await MemoryRepository.clearAll();
                        _loadAllMemories();
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.space8),

            // Clean list with hairline dividers
            Expanded(
              child: _memories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.psychology_outlined, size: 40, color: secondaryTextColor),
                          const SizedBox(height: DesignTokens.space8),
                          Text(
                            'لا توجد ذكريات مخزنة بعد',
                            style: TextStyle(color: primaryTextColor, fontSize: DesignTokens.fontSizeSm),
                          ),
                          const SizedBox(height: DesignTokens.space4),
                          Text(
                            'سيبدأ خوارزمي بحفظ الحقائق تلقائياً أثناء محادثتك معه.',
                            style: TextStyle(color: secondaryTextColor, fontSize: DesignTokens.fontSizeXs),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _memories.length,
                      separatorBuilder: (context, index) => Divider(
                        height: DesignTokens.hairline,
                        thickness: DesignTokens.hairline,
                        color: borderColor,
                      ),
                      itemBuilder: (context, index) {
                        final mem = _memories[index];
                        final isExpanded = _expandedMemoryIds.contains(mem.id);

                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedMemoryIds.remove(mem.id);
                              } else {
                                _expandedMemoryIds.add(mem.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: DesignTokens.space12,
                              horizontal: DesignTokens.space8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Importance Indicator
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? DesignTokens.hoverDark : DesignTokens.hoverLight,
                                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                                  ),
                                  child: Text(
                                    '⭐ ${mem.importance}',
                                    style: TextStyle(
                                      fontSize: DesignTokens.fontSizeXs,
                                      fontWeight: FontWeight.w600,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: DesignTokens.space12),

                                // Main Content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            mem.category,
                                            style: TextStyle(
                                              fontSize: DesignTokens.fontSizeXs,
                                              color: secondaryTextColor,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (mem.embedding != null) ...[
                                            const SizedBox(width: DesignTokens.space8),
                                            Text(
                                              '• متطابق دلالياً',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                          const Spacer(),
                                          Text(
                                            dateFormat.format(mem.createdAt),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: DesignTokens.space4),
                                      Text(
                                        mem.content,
                                        style: TextStyle(
                                          fontSize: DesignTokens.fontSizeSm,
                                          color: primaryTextColor,
                                          height: 1.45,
                                        ),
                                        maxLines: isExpanded ? null : 2,
                                        overflow: isExpanded ? null : TextOverflow.ellipsis,
                                      ),

                                      // Expanded extra metadata
                                      if (isExpanded) ...[
                                        const SizedBox(height: DesignTokens.space8),
                                        Text(
                                          'مرات الاسترجاع: ${mem.accessCount}  |  المعرّف: #${mem.id}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontFamily: DesignTokens.fontFamilyMono,
                                            fontFamilyFallback: DesignTokens.monoFallbacks,
                                            color: secondaryTextColor,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // Delete single item button
                                IconButton(
                                  icon: Icon(Icons.close_rounded, size: 14, color: secondaryTextColor),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'حذف',
                                  onPressed: () async {
                                    await MemoryRepository.deleteMemory(mem.id);
                                    _loadAllMemories();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
