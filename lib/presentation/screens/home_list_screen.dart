import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_view.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/progress_pie.dart';
import '../shared/widgets/magic_plus.dart';
import '../shared/widgets/name_dialog.dart';
import '../shared/widgets/when_picker_sheet.dart';
import '../shared/widgets/tag_picker_sheet.dart';
import 'view_screen.dart';
import 'project_screen.dart';
import 'search_screen.dart';
import 'trash_screen.dart';
import 'sync_settings_screen.dart';

/// 移动端主页：Things 风格的清单导航（系统视图 + 领域/项目）。
class HomeListScreen extends ConsumerWidget {
  const HomeListScreen({super.key});

  void _openView(BuildContext context, AppView view) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViewScreen(view: view, showBack: true),
    ));
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(areasProvider).value ?? [];
    final projects = ref.watch(projectsProvider).value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Things'),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: AppTheme.textSecondary),
            onPressed: () => _openSearch(context),
          ),
          IconButton(
            icon: Icon(Icons.cloud_sync_outlined, color: AppTheme.textSecondary),
            tooltip: '云同步',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SyncSettingsScreen())),
          ),
        ],
      ),
      body: MagicCreateScope(
        context: const MagicCreateContext(defaultWhen: WhenChoice.inbox),
        child: SafeArea(
        child: NotificationListener<OverscrollNotification>(
          // Things 式「下拉弹出搜索」：在顶部继续下拉即打开 Quick Find。
          onNotification: (n) {
            if (n.overscroll < -8 && n.metrics.pixels <= 0) {
              _openSearch(context);
              return true;
            }
            return false;
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
            for (final v in AppView.values)
              _ViewTile(view: v, onTap: () => _openView(context, v)),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Divider(),
            ),
            for (final area in areas) ...[
              GestureDetector(
                onLongPress: () => TagPickerSheet.show(context, area.id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(area.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                ),
              ),
              for (final p in projects.where((p) => p.areaId == area.id))
                _ProjectTile(id: p.id, title: p.title),
            ],
            for (final p in projects.where((p) => p.areaId == null))
              _ProjectTile(id: p.id, title: p.title),
            _addTile(context, ref, '新建项目', isArea: false),
            _addTile(context, ref, '新建领域', isArea: true),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Divider(),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: AppTheme.textSecondary),
              title: Text('垃圾桶',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppTheme.textSecondary)),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrashScreen())),
            ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _addTile(BuildContext context, WidgetRef ref, String label,
      {required bool isArea}) {
    return ListTile(
      leading: Icon(Icons.add, color: AppTheme.textSecondary),
      title: Text(label,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: AppTheme.textSecondary)),
      onTap: () async {
        final name = await NameDialog.show(context,
            title: label, hint: isArea ? '领域名称' : '项目名称');
        if (name != null && name.isNotEmpty) {
          final repo = ref.read(itemRepositoryProvider);
          if (isArea) {
            repo.createArea(title: name);
          } else {
            repo.createProject(title: name);
          }
        }
      },
    );
  }
}

class _ViewTile extends ConsumerWidget {
  final AppView view;
  final VoidCallback onTap;
  const _ViewTile({required this.view, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(view.provider).value?.length ?? 0;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      minLeadingWidth: 30,
      horizontalTitleGap: 12,
      leading: Container(
        width: 29,
        height: 29,
        decoration: BoxDecoration(
          color: view.color,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(view.icon, color: Colors.white, size: 18),
      ),
      title: Text(view.title,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500)),
      trailing: (count > 0 && view != AppView.logbook)
          ? Text('$count',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary, fontSize: 15))
          : null,
      onTap: onTap,
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  final String id;
  final String title;
  const _ProjectTile({required this.id, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(projectProgressProvider(id));
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.only(left: 23, right: 20),
      minLeadingWidth: 26,
      horizontalTitleGap: 14,
      leading: ProgressPie(
        progress: progress.maybeWhen(data: (p) => p.fraction, orElse: () => 0.0),
        size: 18,
        color: AppTheme.primaryBlue,
      ),
      title: Text(title,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500)),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProjectScreen(projectId: id, projectTitle: title),
      )),
    );
  }
}
