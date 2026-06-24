import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/item.dart';
import 'providers/item_providers.dart';

/// 监听 URL Scheme 快速捕获：
///   things:///add?title=买牛奶
///   things://add?title=...
/// 收到后创建一条 Inbox 任务，并提示。
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
  Widget build(BuildContext context) => widget.child;
}
