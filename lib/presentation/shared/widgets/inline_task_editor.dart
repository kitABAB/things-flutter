import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'things_checkbox.dart';
import 'when_picker_sheet.dart';
import 'tag_picker_sheet.dart';

/// Things 风格的「原地展开」编辑卡片：
/// 在列表中点任务时不跳页，而是就地展开为可编辑卡片——
/// 标题可直接改，并提供 计划 / 死线 / 标签 的快捷入口，
/// 复杂项（检查项、重复、提醒、移动）通过「详情」进入完整页面。
class InlineTaskEditor extends ConsumerStatefulWidget {
  final Item item;
  final VoidCallback onCollapse;
  final VoidCallback onOpenDetail;

  const InlineTaskEditor({
    super.key,
    required this.item,
    required this.onCollapse,
    required this.onOpenDetail,
  });

  @override
  ConsumerState<InlineTaskEditor> createState() => _InlineTaskEditorState();
}

class _InlineTaskEditorState extends ConsumerState<InlineTaskEditor> {
  late final TextEditingController _titleCtrl;
  final FocusNode _titleFocus = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.item.title);
    // 展开即聚焦标题，光标落在末尾。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _titleFocus.requestFocus();
        _titleCtrl.selection = TextSelection.collapsed(
            offset: _titleCtrl.text.length);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _save();
    _titleCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _save() {
    final t = _titleCtrl.text.trim();
    final title = t.isEmpty ? widget.item.title : t;
    // 标题有变化才写库，避免无谓的同步噪音。
    if (title == widget.item.title) return;
    ref.read(itemRepositoryProvider).updateContent(
          widget.item.id,
          title: title,
        );
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final repo = ref.read(itemRepositoryProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppTheme.isDark ? 0.4 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: AppTheme.dividerColor, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: ThingsCheckbox(
                  value: item.isCompleted,
                  onChanged: (v) => repo.toggleComplete(item.id, v ?? false),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  focusNode: _titleFocus,
                  onChanged: (_) => _scheduleSave(),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => widget.onCollapse(),
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '新任务',
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '收起',
                icon: Icon(Icons.keyboard_arrow_up_rounded,
                    color: AppTheme.textSecondary),
                onPressed: widget.onCollapse,
              ),
            ],
          ),
          const SizedBox(height: 4),
          _toolbar(context, repo),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 160.ms)
        .scaleXY(begin: 0.98, end: 1, curve: Curves.easeOut);
  }

  Widget _toolbar(BuildContext context, repo) {
    final item = widget.item;
    final deadlineLabel =
        item.deadline != null ? DateFmt.deadlineLabel(item.deadline!) : '死线';
    final deadlineActive = item.deadline != null;

    return Padding(
      padding: const EdgeInsets.only(left: 31),
      child: Row(
        children: [
          _toolButton(
            icon: Icons.calendar_today_rounded,
            label: '计划',
            onTap: () => WhenPickerSheet.apply(context, ref, item.id),
          ),
          _toolButton(
            icon: Icons.flag_rounded,
            label: deadlineLabel,
            active: deadlineActive,
            color: deadlineActive ? AppTheme.deadlineRed : null,
            onTap: () => _pickDeadline(context, repo),
          ),
          _toolButton(
            icon: Icons.label_outline_rounded,
            label: '标签',
            onTap: () => TagPickerSheet.show(context, item.id),
          ),
          const Spacer(),
          _toolButton(
            icon: Icons.open_in_full_rounded,
            label: '详情',
            onTap: widget.onOpenDetail,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDeadline(BuildContext context, repo) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.item.deadline ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选择死线',
    );
    if (picked != null) {
      await repo.setDeadline(widget.item.id, picked);
    }
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? color,
  }) {
    final c = color ?? (active ? AppTheme.primaryBlue : AppTheme.textSecondary);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: c, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
