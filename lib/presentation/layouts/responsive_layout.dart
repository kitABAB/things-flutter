import 'package:flutter/material.dart';
import '../mobile/layouts/mobile_main_layout.dart';
import '../desktop/layouts/desktop_main_layout.dart';

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 600) {
          return const DesktopMainLayout();
        }
        return const MobileMainLayout();
      },
    );
  }
}
