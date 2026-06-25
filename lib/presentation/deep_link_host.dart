import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/today_widget_service.dart';
import '../domain/models/item.dart';
import 'providers/item_providers.dart';
import 'shared/widgets/add_edit_item_modal.dart';
import 'shared/widgets/when_picker_sheet.dart';

/// 监听 URL Scheme 快速捕获，并把「今天」实时同步到主屏小组件。
///   things://add?title=买牛奶   —— 直接捕获到收件箱
///   things://capture           —— 打开「新建任务」（默认今天），供小组件 ＋ 使用
class DeepLinkHost extends ConsumerStatefulWidget {
  final Widget child;
  const DeepLinkHost({super.key, required this.child});

  @override
  ConsumerState<DeepLinkHost> createState() => _DeepLinkHostState();
}

class _DeepLinkHostState extends ConsumerState<DeepLinkHost> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(Uri uri) async {
    // 小组件 ＋：打开「新建任务」，默认落到今天。
    final isCapture =
        uri.host == 'capture' || uri.pathSegments.contains('capture');
    if (isCapture) {
      if (!mounted) return;
      await AddEditItemModal.show(context, defaultWhen: WhenChoice.today);
      return;
    }

    // 兼容 things://add 与 things:///add 两种写法。
    final isAdd = uri.host == 'add' ||
        uri.pathSegments.contains('add') ||
        uri.path == '/add';
    if (!isAdd) return;
    final title = uri.queryParameters['title']?.trim();
    if (title == null || title.isEmpty) return;

    final repo = ref.read(itemRepositoryProvider);
    await repo.createTask(
      title: title,
      start: WhenStart.inbox,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已捕获到收件箱：$title')),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 「今天」列表一变就重算并推送给主屏小组件（首帧加载完即首推）。
    // 重算逻辑（含标签/筛选/进度）统一在 service 内用全局 db 完成。
    ref.listen<AsyncValue<List<Item>>>(todayProvider, (_, next) {
      if (next.value != null) {
        TodayWidgetService.instance.refresh();
      }
    });
    return widget.child;
  }
}
