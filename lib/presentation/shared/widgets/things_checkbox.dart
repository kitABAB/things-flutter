import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Things 风格复选框：勾选时方框平滑填充，对勾带轻微回弹。
class ThingsCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const ThingsCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: value
                ? AppTheme.primaryBlue
                : (AppTheme.isDark
                    ? const Color(0xFF55555A)
                    : const Color(0xFFC7C7CC)),
            width: value ? 0 : 1.6,
          ),
          color: value ? AppTheme.primaryBlue : Colors.transparent,
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: value ? 1 : 0,
          child: const Icon(Icons.check, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
