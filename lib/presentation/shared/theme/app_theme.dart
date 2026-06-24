import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  /// 由 MaterialApp.builder 在每帧根据当前亮度刷新，
  /// 使下面的中性色 getter 自动适配深 / 浅色。
  static bool isDark = false;

  // Things 3 的标志性强调蓝（偏深、非青），用于链接 / 复选框 / 项目环。
  static const Color primaryBlue = Color(0xFF2D7DF6);

  // 语义色（深浅通用）—— 对齐 Things 3 配色
  static const Color todayYellow = Color(0xFFFAC51C); // 今天金星
  static const Color eveningIndigo = Color(0xFF5B6CF0); // 今晚靛蓝
  static const Color deadlineRed = Color(0xFFE5484D);
  static const Color somedayGrey = Color(0xFFB7935A); // 将来褐

  // 中性色：随亮度切换
  static Color get textPrimary =>
      isDark ? const Color(0xFFECECEC) : const Color(0xFF1A1A1A);
  static Color get textSecondary =>
      isDark ? const Color(0xFF98989F) : const Color(0xFF9A9AA0);
  static Color get backgroundLight =>
      isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF6F6F8);
  static Color get sidebarBg =>
      isDark ? const Color(0xFF161618) : const Color(0xFFF0F0F3);
  static Color get dividerColor =>
      isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEDEDF0);

  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  /// 平台自适应排版：
  ///   - Apple（macOS / iOS）：直接用系统字体——拉丁文即 SF Pro、中文回退 PingFang SC，
  ///     这是最"苹果味"的组合，也是 Things 本尊在 Apple 平台的做法。
  ///   - 其他平台（Android / Windows / Linux）：用 Noto Sans SC，中文显示一致清晰。
  ///     （SF Pro 为 Apple 专有字体，无法在非 Apple 平台合法内嵌分发。）
  static TextTheme _applyFont(TextTheme base) {
    final isApple = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (isApple) {
      // fontFamily 留空 → Flutter 在 Apple 平台默认使用 San Francisco（SF Pro）。
      return base.apply(fontFamilyFallback: const ['PingFang SC']);
    }
    return GoogleFonts.notoSansScTextTheme(base);
  }

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF1E1E20) : Colors.white;
    final scaffold = dark ? const Color(0xFF141416) : Colors.white;
    final textPrimaryC =
        dark ? const Color(0xFFECECEC) : const Color(0xFF1E1E1E);
    final textSecondaryC =
        dark ? const Color(0xFF98989F) : const Color(0xFF8E8E93);
    final divider = dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scaffold,
      primaryColor: primaryBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: brightness,
        surface: surface,
      ),
      textTheme: () {
        final themed = _applyFont(
          dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
        );
        // 在已套用字体族的基础上覆盖字号 / 字重，保留 fontFamily 与 fallback。
        return themed.copyWith(
          titleLarge: themed.titleLarge?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: textPrimaryC,
              letterSpacing: -0.6),
          titleMedium: themed.titleMedium?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: textPrimaryC,
              letterSpacing: -0.3),
          bodyLarge: themed.bodyLarge?.copyWith(
              fontSize: 17, fontWeight: FontWeight.w400, color: textPrimaryC),
          bodyMedium: themed.bodyMedium?.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: textSecondaryC),
        );
      }(),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: primaryBlue),
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600, color: textPrimaryC),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 3,
      ),
    );
  }
}
