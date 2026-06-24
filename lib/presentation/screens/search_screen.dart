import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/item.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';
import 'task_detail_screen.dart';
import 'project_screen.dart';

/// Quick Find（Type Travel 雏形）：
/// - 实时按标题过滤任务与项目；
/// - 自动识别标签：输入以 `#` 开头或命中标签名时，弹出全 App 范围的标签过滤。
class SearchScreen extends ConsumerStatefulWidget {
  /// 桌面端 Type Travel：打字即搜，带入首个字符。
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<Item> _results = [];
  bool _searching = false;
  Tag? _activeTag;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery;
    if (q != null && q.isNotEmpty) {
      _controller.text = q;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(q));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _query => _controller.text.trim();

  /// 当前输入命中的标签建议。
  List<Tag> _matchedTags() {
    final all = ref.read(tagsProvider).value ?? const [];
    var q = _query;
    if (q.startsWith('#')) q = q.substring(1).trim();
    if (q.isEmpty) return q == '' && _controller.text.startsWith('#') ? all : [];
    return all
        .where((t) => t.title.toLowerCase().contains(q.toLowerCase()))
        .toList();
  }

  Future<void> _run(String q) async {
    setState(() {
      _activeTag = null;
      _searching = true;
    });
    final results = await ref.read(itemRepositoryProvider).search(q);
    if (mounted) {
      setState(() {
        _results = results;
        _searching = false;
      });
    }
  }

  Future<void> _filterByTag(Tag tag) async {
    setState(() {
      _activeTag = tag;
      _searching = true;
    });
    final results = await ref.read(itemRepositoryProvider).itemsWithTag(tag.id);
    if (mounted) {
      setState(() {
        _results = results;
        _searching = false;
      });
    }
  }

  void _open(Item item) {
    final route = MaterialPageRoute(
      builder: (_) => item.isProject
          ? ProjectScreen(projectId: item.id, projectTitle: item.title)
          : TaskDetailScreen(initial: item),
    );
    Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final matched = _matchedTags();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: const InputDecoration(
            hintText: '搜索任务、项目，或输入 # 找标签…',
            border: InputBorder.none,
          ),
          onChanged: _run,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              color: AppTheme.textSecondary,
              onPressed: () {
                _controller.clear();
                setState(() {
                  _results = [];
                  _activeTag = null;
                });
              },
            ),
        ],
        bottom: matched.isEmpty && _activeTag == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: _tagSuggestions(matched),
              ),
      ),
      body: _buildBody(),
    );
  }

  Widget _tagSuggestions(List<Tag> tags) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          if (_activeTag != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InputChip(
                label: Text('# ${_activeTag!.title}'),
                selected: true,
                onDeleted: () => _run(_query),
                selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
              ),
            ),
          for (final t in tags)
            if (_activeTag?.id != t.id)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.tag, size: 16),
                  label: Text(t.title),
                  onPressed: () => _filterByTag(t),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty && _activeTag == null) {
      return Center(
        child: Text('输入关键字开始搜索', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }
    if (_searching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('没有匹配的结果', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return ListTile(
          leading: Icon(
            item.isProject ? Icons.folder_rounded : Icons.check_circle_outline,
            color: item.isProject ? AppTheme.primaryBlue : AppTheme.textSecondary,
          ),
          title: Text(
            item.title,
            style: TextStyle(
              decoration: item.isDone ? TextDecoration.lineThrough : null,
              color: item.isDone ? AppTheme.textSecondary : AppTheme.textPrimary,
            ),
          ),
          onTap: () => _open(item),
        ).animate().fadeIn(duration: 160.ms, delay: (index * 12).ms);
      },
    );
  }
}
