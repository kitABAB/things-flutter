import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_view.dart';
import '../../providers/item_providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/progress_pie.dart';
import '../../shared/widgets/name_dialog.dart';
import '../../screens/search_screen.dart';
import '../../screens/trash_screen.dart';
import '../../screens/ai_settings_screen.dart';

/// 桌面端侧边栏选中项：要么是系统视图，要么是某个项目。
class SidebarSelection {
  final AppView? view;
  final String? projectId;
  final String? projectTitle;
  const SidebarSelection.system(this.view)
      : projectId = null,
        projectTitle = null;
  const SidebarSelection.project(this.projectId, this.projectTitle)
      : view = null;

  bool get isProject => projectId != null;
}

class ThingsSidebar extends ConsumerWidget {
  final SidebarSelection selection;
  final ValueChanged<SidebarSelection> onSelect;

  const ThingsSidebar({
    super.key,
    required this.selection,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(areasProvider).value ?? [];
    final projects = ref.watch(projectsProvider).value ?? [];

    return Container(
      width: 240,
      color: AppTheme.sidebarBg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          children: [
            _actionRow(context, Icons.search, '搜索', () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()));
            }),
            const SizedBox(height: 4),
            for (final v in AppView.values) _navItem(context, ref, v),
            if (areas.isNotEmpty || projects.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 14, 8, 6),
                child: Divider(),
              ),
            for (final area in areas) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(area.title,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary)),
                    ),
                    InkWell(
                      onTap: () => _newProject(context, ref, areaId: area.id),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.add, size: 16, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              for (final p in projects.where((p) => p.areaId == area.id))
                _projectItem(context, p.id, p.title),
            ],
            for (final p in projects.where((p) => p.areaId == null))
              _projectItem(context, p.id, p.title),
            const SizedBox(height: 10),
            _addRow(context, '新建项目', () => _newProject(context, ref)),
            _addRow(context, '新建领域', () => _newArea(context, ref)),
            const Divider(height: 16),
            _actionRow(context, Icons.delete_outline, '垃圾桶', () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrashScreen()));
            }),
            _actionRow(context, Icons.auto_awesome_outlined, 'AI 模型', () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _newProject(BuildContext context, WidgetRef ref,
      {String? areaId}) async {
    final name = await NameDialog.show(context, title: '新建项目', hint: '项目名称');
    if (name != null && name.isNotEmpty) {
      ref.read(itemRepositoryProvider).createProject(title: name, areaId: areaId);
    }
  }

  Future<void> _newArea(BuildContext context, WidgetRef ref) async {
    final name = await NameDialog.show(context, title: '新建领域', hint: '领域名称');
    if (name != null && name.isNotEmpty) {
      ref.read(itemRepositoryProvider).createArea(title: name);
    }
  }

  Widget _actionRow(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Text(label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 15, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _addRow(BuildContext context, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(Icons.add, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, WidgetRef ref, AppView view) {
    final selected = selection.view == view;
    final count = ref.watch(view.provider).value?.length ?? 0;
    return _tile(
      context,
      selected: selected,
      leading: Icon(view.icon, color: view.color, size: 20),
      label: view.title,
      trailing: (count > 0 && view != AppView.logbook) ? '$count' : null,
      onTap: () => onSelect(SidebarSelection.system(view)),
    );
  }

  Widget _projectItem(BuildContext context, String id, String title) {
    final selected = selection.projectId == id;
    return Consumer(builder: (context, ref, _) {
      final progress = ref.watch(projectProgressProvider(id));
      return _tile(
        context,
        selected: selected,
        leading: ProgressPie(
          progress:
              progress.maybeWhen(data: (p) => p.fraction, orElse: () => 0.0),
          size: 18,
          color: AppTheme.primaryBlue,
        ),
        label: title,
        onTap: () => onSelect(SidebarSelection.project(id, title)),
      );
    });
  }

  Widget _tile(
    BuildContext context, {
    required bool selected,
    required Widget leading,
    required String label,
    String? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (trailing != null)
              Text(trailing,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
