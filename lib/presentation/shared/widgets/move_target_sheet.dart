import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';

/// 移动目标。
class MoveTarget {
  final bool inbox;
  final String? areaId;
  final String? areaTitle;
  final String? projectId;
  final String? projectTitle;
  const MoveTarget.inbox()
      : inbox = true,
        areaId = null,
        areaTitle = null,
        projectId = null,
        projectTitle = null;
  const MoveTarget.area(this.areaId, this.areaTitle)
      : inbox = false,
        projectId = null,
        projectTitle = null;
  const MoveTarget.project(this.projectId, this.projectTitle)
      : inbox = false,
        areaId = null,
        areaTitle = null;
}

/// 选择把任务移动到哪里：收件箱 / 某领域 / 某项目（居中模态）。
class MoveTargetSheet {
  static Future<MoveTarget?> show(BuildContext context) {
    return showDialog<MoveTarget>(
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

class _MoveBody extends ConsumerWidget {
  const _MoveBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(areasProvider).value ?? [];
    final projects = ref.watch(projectsProvider).value ?? [];

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('移动到', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.inbox_rounded, color: Color(0xFF4C6FCC)),
            title: const Text('收件箱'),
            onTap: () => Navigator.of(context).pop(const MoveTarget.inbox()),
          ),
          for (final area in areas)
            ListTile(
              leading: const Icon(Icons.dashboard_rounded,
                  color: AppTheme.somedayGrey),
              title: Text(area.title),
              onTap: () => Navigator.of(context)
                  .pop(MoveTarget.area(area.id, area.title)),
            ),
          for (final p in projects)
            ListTile(
              leading:
                  const Icon(Icons.folder_rounded, color: AppTheme.primaryBlue),
              title: Text(p.title),
              onTap: () => Navigator.of(context)
                  .pop(MoveTarget.project(p.id, p.title)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
