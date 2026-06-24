import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_view.dart';
import '../../screens/view_screen.dart';
import '../../screens/project_screen.dart';
import '../../screens/search_screen.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/add_edit_item_modal.dart';
import '../widgets/things_sidebar.dart';

class DesktopMainLayout extends StatefulWidget {
  const DesktopMainLayout({super.key});

  @override
  State<DesktopMainLayout> createState() => _DesktopMainLayoutState();
}

class _DesktopMainLayoutState extends State<DesktopMainLayout> {
  SidebarSelection _selection = const SidebarSelection.system(AppView.today);
  bool _slim = false;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool get _typingInField {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _openSearch({String? initial}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchScreen(initialQuery: initial),
    ));
  }

  /// Type Travel：未聚焦输入框时，敲下可见字符即跳进搜索。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_typingInField) return KeyEventResult.ignored;
    final ch = event.character;
    if (ch != null &&
        ch.isNotEmpty &&
        ch.trim().isNotEmpty &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        ch.codeUnitAt(0) >= 0x20) {
      _openSearch(initial: ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final meta = {
      LogicalKeyboardKey.meta,
      LogicalKeyboardKey.control,
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            AddEditItemModal.show(context),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            AddEditItemModal.show(context),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.backslash, meta: true): () =>
            setState(() => _slim = !_slim),
        const SingleActivator(LogicalKeyboardKey.backslash, control: true): () =>
            setState(() => _slim = !_slim),
      },
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: _slim
                    ? const SizedBox(width: 0)
                    : ThingsSidebar(
                        selection: _selection,
                        onSelect: (s) => setState(() => _selection = s),
                      ),
              ),
              Container(width: 1, color: Theme.of(context).dividerColor),
              Expanded(
                child: Column(
                  children: [
                    _topBar(context, meta),
                    Expanded(
                      child: _selection.isProject
                          ? ProjectScreen(
                              key: ValueKey(_selection.projectId),
                              projectId: _selection.projectId!,
                              projectTitle: _selection.projectTitle ?? '项目',
                            )
                          : ViewScreen(
                              key: ValueKey(_selection.view),
                              view: _selection.view ?? AppView.today,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, Set<LogicalKeyboardKey> _) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          IconButton(
            tooltip: _slim ? '展开侧栏 (⌘\\)' : '折叠侧栏 (⌘\\)',
            icon: Icon(_slim ? Icons.menu_open_rounded : Icons.menu_rounded,
                size: 20, color: AppTheme.textSecondary),
            onPressed: () => setState(() => _slim = !_slim),
          ),
          IconButton(
            tooltip: '搜索 (⌘F)',
            icon: Icon(Icons.search_rounded,
                size: 20, color: AppTheme.textSecondary),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: '新建任务 (⌘N)',
            icon: Icon(Icons.add_rounded,
                size: 20, color: AppTheme.textSecondary),
            onPressed: () => AddEditItemModal.show(context),
          ),
        ],
      ),
    );
  }
}
