import 'package:flutter/material.dart';
import '../../screens/home_list_screen.dart';

/// 移动端入口：直接进入 Things 风格的主清单。
class MobileMainLayout extends StatelessWidget {
  const MobileMainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeListScreen();
  }
}
