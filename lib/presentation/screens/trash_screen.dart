import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';

/// 垃圾桶：恢复、彻底删除单条、或清空全部。
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(trashProvider);
    final repo = ref.read(itemRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppTheme.textSecondary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('垃圾桶'),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清空垃圾桶'),
                  content: const Text('将永久删除其中所有条目，无法恢复。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('取消')),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.deadlineRed),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('清空'),
                    ),
                  ],
                ),
              );
              if (ok == true) repo.emptyTrash();
            },
            child: const Text('清空',
                style: TextStyle(color: AppTheme.deadlineRed)),
          ),
        ],
      ),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('出错了：$e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text('垃圾桶是空的',
                  style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '恢复',
                      icon: const Icon(Icons.restore,
                          color: AppTheme.primaryBlue),
                      onPressed: () => repo.restore(item.id),
                    ),
                    IconButton(
                      tooltip: '彻底删除',
                      icon: const Icon(Icons.delete_forever,
                          color: AppTheme.deadlineRed),
                      onPressed: () => repo.deletePermanently(item.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
