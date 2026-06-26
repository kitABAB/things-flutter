import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'add_edit_item_modal.dart';
import 'when_picker_sheet.dart';

/// 「魔法加号」要在哪个语境下新建条目：
/// 进入项目则带 projectId，进入某个时间视图则带 defaultWhen，等等。
class MagicCreateContext {
  final String? projectId;
  final String? headingId;
  final WhenChoice? defaultWhen;
  const MagicCreateContext({this.projectId, this.headingId, this.defaultWhen});
}

/// 全局唯一的「当前新建语境」控制器：用一个栈跟踪随导航变化的语境。
/// 每个页面挂载时压栈、卸载时出栈，栈顶即当前语境——天然贴合 push/pop。
class MagicPlusController {
  MagicPlusController._();
  static final MagicPlusController instance = MagicPlusController._();

  final ValueNotifier<MagicCreateContext> active =
      ValueNotifier(const MagicCreateContext());
  final List<(int, MagicCreateContext)> _stack = [];
  int _seq = 0;

  int push(MagicCreateContext ctx) {
    final id = ++_seq;
    _stack.add((id, ctx));
    _emit();
    return id;
  }

  void replace(int id, MagicCreateContext ctx) {
    final i = _stack.indexWhere((e) => e.$1 == id);
    if (i != -1) {
      _stack[i] = (id, ctx);
      _emit();
    }
  }

  void remove(int id) {
    _stack.removeWhere((e) => e.$1 == id);
    _emit();
  }

  void _emit() {
    active.value =
        _stack.isEmpty ? const MagicCreateContext() : _stack.last.$2;
  }
}

/// 把页面内容包进它，即可在该页面活跃时把新建语境登记为 [context]。
class MagicCreateScope extends StatefulWidget {
  final MagicCreateContext context;
  final Widget child;
  const MagicCreateScope(
      {super.key, required this.context, required this.child});

  @override
  State<MagicCreateScope> createState() => _MagicCreateScopeState();
}

class _MagicCreateScopeState extends State<MagicCreateScope> {
  int? _id;

  @override
  void initState() {
    super.initState();
    _id = MagicPlusController.instance.push(widget.context);
  }

  @override
  void dispose() {
    if (_id != null) MagicPlusController.instance.remove(_id!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 监听模态/弹窗的出现，供全局加号在弹窗或对话框开启时自动隐藏，避免遮挡。
class MagicPlusNavObserver extends NavigatorObserver {
  final ValueNotifier<int> modalDepth = ValueNotifier(0);

  bool _isModal(Route<dynamic>? r) {
    if (r == null) return false;
    if (r is PopupRoute) return true;
    final name = r.runtimeType.toString().toLowerCase();
    return name.contains('modal') || name.contains('sheet') || name.contains('dialog');
  }

  void _dec() {
    modalDepth.value = (modalDepth.value - 1).clamp(0, 1 << 30);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) modalDepth.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) _dec();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) _dec();
  }
}

/// 全局常驻的「魔法加号」：渲染在 Navigator 之上，跨页面持续存在。
/// - 轻点：在当前语境下新建条目（收件箱/某视图/某项目）。
/// - 长按拖动：顶部浮现「收件箱 / 今天」两个投放区，松手落入对应桶。
/// - 弹窗开启或键盘弹起时自动隐藏，仅在移动尺寸显示。
class GlobalMagicPlus extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final MagicPlusNavObserver observer;
  final Widget child;

  const GlobalMagicPlus({
    super.key,
    required this.navigatorKey,
    required this.observer,
    required this.child,
  });

  @override
  State<GlobalMagicPlus> createState() => _GlobalMagicPlusState();
}

class _GlobalMagicPlusState extends State<GlobalMagicPlus> {
  // 只重建投放区、不重建 LongPressDraggable，避免拖拽中重建导致手势丢失。
  final ValueNotifier<bool> _dragging = ValueNotifier(false);

  @override
  void dispose() {
    _dragging.dispose();
    super.dispose();
  }

  void _endDrag() {
    if (_dragging.value) _dragging.value = false;
  }

  BuildContext get _navContext =>
      widget.navigatorKey.currentState?.overlay?.context ??
      widget.navigatorKey.currentContext ??
      context;

  void _openCreate({WhenChoice? overrideWhen}) {
    final ctx = MagicPlusController.instance.active.value;
    AddEditItemModal.show(
      _navContext,
      projectId: ctx.projectId,
      headingId: ctx.headingId,
      defaultWhen: overrideWhen ?? ctx.defaultWhen,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        // 加号浮层置于独立 Overlay 中：因为它位于 Navigator 之上，
        // LongPressDraggable / DragTarget 需要自己的 Overlay 祖先。
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (overlayContext) {
                  final mq = MediaQuery.of(overlayContext);
                  return ValueListenableBuilder<int>(
                    valueListenable: widget.observer.modalDepth,
                    builder: (context, depth, _) {
                      final keyboardUp = mq.viewInsets.bottom > 0;
                      final show =
                          depth == 0 && !keyboardUp && mq.size.width <= 600;
                      if (!show) return const SizedBox.shrink();
                      return _buildPlusLayer(context, mq);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlusLayer(BuildContext context, MediaQueryData mq) {
    return Stack(
      children: [
        // 顶部投放区（仅拖拽时出现）
        Positioned(
          top: mq.padding.top + 8,
          left: 16,
          right: 16,
          child: ValueListenableBuilder<bool>(
            valueListenable: _dragging,
            builder: (context, dragging, _) {
              if (!dragging) return const SizedBox.shrink();
              return Row(
                children: [
                  Expanded(
                    child: _dropZone(
                      icon: Icons.inbox_rounded,
                      label: '收件箱',
                      onAccept: () => _openCreate(overrideWhen: WhenChoice.inbox),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _dropZone(
                      icon: Icons.star_rounded,
                      label: '今天',
                      color: AppTheme.todayYellow,
                      onAccept: () => _openCreate(overrideWhen: WhenChoice.today),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _dropZone(
                      icon: Icons.nightlight_round,
                      label: '今晚',
                      color: AppTheme.eveningIndigo,
                      onAccept: () =>
                          _openCreate(overrideWhen: WhenChoice.thisEvening),
                    ),
                  ),
                ],
              )
                  .animate()
                  .fadeIn(duration: 160.ms)
                  .slideY(begin: -0.4, end: 0, curve: Curves.easeOut);
            },
          ),
        ),
        // 右下角加号
        Positioned(
          right: 16,
          bottom: 16 + mq.padding.bottom,
          child: LongPressDraggable<int>(
            data: 1,
            onDragStarted: () => _dragging.value = true,
            onDragEnd: (_) => _endDrag(),
            onDragCompleted: _endDrag,
            onDraggableCanceled: (_, _) => _endDrag(),
            feedback: const _Fab(elevated: true),
            childWhenDragging: const _Fab(ghost: true),
            child: GestureDetector(
              onTap: _openCreate,
              child: const _Fab(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropZone({
    required IconData icon,
    required String label,
    required VoidCallback onAccept,
    Color color = AppTheme.primaryBlue,
  }) {
    return DragTarget<int>(
      onAcceptWithDetails: (_) {
        _endDrag();
        WidgetsBinding.instance.addPostFrameCallback((_) => onAccept());
      },
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 56,
            decoration: BoxDecoration(
              color: hot ? color : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color, width: hot ? 0 : 1.4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: hot ? 0.4 : 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: hot ? Colors.white : color, size: 20),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: hot ? Colors.white : color,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Fab extends StatelessWidget {
  final bool elevated;
  final bool ghost;
  const _Fab({this.elevated = false, this.ghost = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: ghost
              ? AppTheme.primaryBlue.withValues(alpha: 0.4)
              : AppTheme.primaryBlue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: elevated ? 0.3 : 0.18),
              blurRadius: elevated ? 16 : 8,
              offset: Offset(0, elevated ? 8 : 3),
            ),
          ],
        ),
        child: const Icon(Icons.add, size: 28, color: Colors.white),
      ),
    );
  }
}
