import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';
import '../../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/natural_date.dart';

/// 一次「When」选择的结果（含可选的闹钟提醒）。
class WhenChoice {
  final WhenStart start;
  final DateTime? startDate;
  final bool evening;
  final String? reminderTime; // 'HH:mm'
  const WhenChoice(this.start,
      {this.startDate, this.evening = false, this.reminderTime});

  static const inbox = WhenChoice(WhenStart.inbox);
  static WhenChoice get today =>
      WhenChoice(WhenStart.anytime, startDate: DateTime.now());
  static WhenChoice get thisEvening =>
      WhenChoice(WhenStart.anytime, startDate: DateTime.now(), evening: true);
  static const anytime = WhenChoice(WhenStart.anytime);
  static const someday = WhenChoice(WhenStart.someday);
  static WhenChoice scheduled(DateTime d, {String? reminderTime}) =>
      WhenChoice(WhenStart.anytime, startDate: d, reminderTime: reminderTime);
}

/// Things 风格的 Jump Start 面板：自然语言输入 + 快捷桶 + 指定日期 + 闹钟。
/// 在大屏上自动呈现为对话框，小屏为底部抽屉。
class WhenPickerSheet {
  static Future<WhenChoice?> showChoice(BuildContext context) {
    return WoltModalSheet.show<WhenChoice>(
      context: context,
      modalTypeBuilder: (ctx) => MediaQuery.of(ctx).size.width > 720
          ? WoltModalType.dialog()
          : WoltModalType.bottomSheet(),
      pageListBuilder: (modalContext) => [
        WoltModalSheetPage(
          hasTopBarLayer: false,
          backgroundColor: Theme.of(modalContext).cardColor,
          child: _JumpStartBody(
            onPick: (choice) => Navigator.of(modalContext).pop(choice),
          ),
        ),
      ],
    );
  }

  static Future<void> apply(
      BuildContext context, WidgetRef ref, String itemId) async {
    final choice = await showChoice(context);
    if (choice == null) return;
    final repo = ref.read(itemRepositoryProvider);
    await repo.setWhen(
      itemId,
      start: choice.start,
      startDate: choice.startDate,
      evening: choice.evening,
    );
    if (choice.reminderTime != null) {
      await repo.setReminder(itemId, choice.reminderTime);
    }
  }
}

class _JumpStartBody extends StatefulWidget {
  final ValueChanged<WhenChoice> onPick;
  const _JumpStartBody({required this.onPick});

  @override
  State<_JumpStartBody> createState() => _JumpStartBodyState();
}

class _JumpStartBodyState extends State<_JumpStartBody> {
  final _controller = TextEditingController();
  NaturalDateResult _parsed = const NaturalDateResult();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _parsed = NaturalDate.parse(v));
  }

  void _confirmParsed() {
    final r = _parsed;
    if (r.date != null) {
      widget.onPick(WhenChoice.scheduled(r.date!, reminderTime: r.time));
    } else if (r.evening) {
      widget.onPick(WhenChoice.thisEvening);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 自然语言输入
            TextField(
              controller: _controller,
              autofocus: false,
              onChanged: _onChanged,
              onSubmitted: (_) => _confirmParsed(),
              decoration: InputDecoration(
                hintText: '试试「明天 晚上8点」「下周一」「3天后」',
                prefixIcon: const Icon(Icons.bolt_rounded,
                    color: AppTheme.todayYellow),
                suffixIcon: _parsed.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded,
                            color: AppTheme.primaryBlue),
                        onPressed: _confirmParsed,
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (!_parsed.isEmpty) _preview(t),
            const SizedBox(height: 8),
            _tile(Icons.star_rounded, AppTheme.todayYellow, '今天',
                () => widget.onPick(WhenChoice.today)),
            _tile(Icons.nightlight_round, AppTheme.eveningIndigo, '今晚',
                () => widget.onPick(WhenChoice.thisEvening)),
            _tile(Icons.layers_rounded, const Color(0xFF30A46C), '随时',
                () => widget.onPick(WhenChoice.anytime)),
            _tile(Icons.archive_rounded, AppTheme.somedayGrey, '将来',
                () => widget.onPick(WhenChoice.someday)),
            const Divider(height: 16),
            _tile(Icons.calendar_today_rounded, AppTheme.deadlineRed, '指定日期…',
                _pickDate),
          ]
              .animate(interval: 30.ms)
              .fadeIn(duration: 180.ms)
              .slideY(begin: 0.12, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  Widget _preview(TextTheme t) {
    final parts = <String>[];
    if (_parsed.date != null) parts.add(DateFmt.groupLabel(_parsed.date!));
    if (_parsed.evening) parts.add('今晚');
    if (_parsed.time != null) parts.add(_parsed.time!);
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 6),
          Text('解析为：${parts.join(' · ')}',
              style: t.bodyMedium?.copyWith(color: AppTheme.primaryBlue)),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms);
  }

  Widget _tile(IconData icon, Color color, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null && mounted) {
      widget.onPick(WhenChoice.scheduled(picked, reminderTime: _parsed.time));
    }
  }
}
