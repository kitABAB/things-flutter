import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';
import 'smooth_dialog.dart';

/// 移动目标。
class MoveTarget {
  final bool inbox;
  final String? areaId;
  final String? areaTitle;
  final String? projectId;
  final String? projectTitle;
  final String? headingId;
  final String? headingTitle;
  const MoveTarget.inbox()
    : inbox = true,
      areaId = null,
      areaTitle = null,
      projectId = null,
      projectTitle = null,
      headingId = null,
      headingTitle = null;
  const MoveTarget.area(this.areaId, this.areaTitle)
    : inbox = false,
      projectId = null,
      projectTitle = null,
      headingId = null,
      headingTitle = null;
  const MoveTarget.project(this.projectId, this.projectTitle)
    : inbox = false,
      areaId = null,
      areaTitle = null,
      headingId = null,
      headingTitle = null;
  const MoveTarget.heading(
    this.projectId,
    this.projectTitle,
    this.headingId,
    this.headingTitle,
  ) : inbox = false,
      areaId = null,
      areaTitle = null;
}

/// 选择把任务移动到哪里：收件箱 / 某领域 / 某项目（居中模态）。
class MoveTargetSheet {
  static Future<MoveTarget?> show(BuildContext context) {
    return showSmoothDialog<MoveTarget>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: const _MoveBody(),
        ),
      ),
    );
  }
}

class _MoveBody extends ConsumerStatefulWidget {
  const _MoveBody();

  @override
  ConsumerState<_MoveBody> createState() => _MoveBodyState();
}

class _MoveBodyState extends ConsumerState<_MoveBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(areasProvider).value ?? [];
    final projects = ref.watch(projectsProvider).value ?? [];
    final query = _query.trim().toLowerCase();
    final filteredAreas = query.isEmpty
        ? areas
        : areas.where((a) => a.title.toLowerCase().contains(query)).toList();
    final headingsByProject = <String, List<Item>>{};
    for (final project in projects) {
      final projectItems =
          ref.watch(projectItemsProvider(project.id)).value ?? const [];
      final headings = projectItems
          .where((item) => item.isHeading)
          .where(
            (item) =>
                query.isEmpty || item.title.toLowerCase().contains(query),
          )
          .toList();
      if (query.isEmpty ||
          project.title.toLowerCase().contains(query) ||
          headings.isNotEmpty) {
        headingsByProject[project.id] = headings;
      }
    }
    final visibleProjects = query.isEmpty
        ? projects
        : projects
              .where((p) => headingsByProject.containsKey(p.id))
              .toList();

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('移动到', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '搜索领域、项目或标题',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inbox_rounded, color: Color(0xFF4C6FCC)),
            title: const Text('收件箱'),
            onTap: () => Navigator.of(context).pop(const MoveTarget.inbox()),
          ).animate().fadeIn(duration: 140.ms).slideX(begin: 0.02, end: 0),
          if (filteredAreas.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('领域'),
            ),
          for (final area in filteredAreas)
            ListTile(
              leading: const Icon(
                Icons.dashboard_rounded,
                color: AppTheme.somedayGrey,
              ),
              title: Text(area.title),
              onTap: () => Navigator.of(
                context,
              ).pop(MoveTarget.area(area.id, area.title)),
            ).animate().fadeIn(duration: 140.ms).slideX(begin: 0.02, end: 0),
          if (visibleProjects.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('项目'),
            ),
          for (final p in visibleProjects) ...[
            ListTile(
              leading: const Icon(
                Icons.folder_rounded,
                color: AppTheme.primaryBlue,
              ),
              title: Text(p.title),
              onTap: () =>
                  Navigator.of(context).pop(MoveTarget.project(p.id, p.title)),
            ).animate().fadeIn(duration: 140.ms).slideX(begin: 0.02, end: 0),
            for (final h in headingsByProject[p.id] ?? const [])
              ListTile(
                contentPadding: const EdgeInsets.only(left: 52, right: 16),
                leading: const Icon(
                  Icons.segment_rounded,
                  size: 18,
                  color: AppTheme.primaryBlue,
                ),
                title: Text(h.title),
                onTap: () => Navigator.of(context).pop(
                  MoveTarget.heading(p.id, p.title, h.id, h.title),
                ),
              ).animate().fadeIn(duration: 160.ms).slideX(begin: 0.03, end: 0),
          ],
          if (filteredAreas.isEmpty && visibleProjects.isEmpty && query.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Text('没有匹配的目标'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
