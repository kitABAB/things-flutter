import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/database/powersync_db.dart';
import 'data/services/notification_service.dart';
import 'data/services/sync_service.dart';
import 'presentation/shared/theme/app_theme.dart';
import 'presentation/shared/widgets/magic_plus.dart';
import 'presentation/layouts/responsive_layout.dart';
import 'presentation/deep_link_host.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize PowerSync DB in local-only mode
  await openDatabase();
  await NotificationService.instance.init();
  await SyncService.instance.load();

  runApp(
    const ProviderScope(
      child: Things3CloneApp(),
    ),
  );
}

class Things3CloneApp extends StatefulWidget {
  const Things3CloneApp({super.key});

  @override
  State<Things3CloneApp> createState() => _Things3CloneAppState();
}

class _Things3CloneAppState extends State<Things3CloneApp>
    with WidgetsBindingObserver {
  Timer? _autoSync;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final MagicPlusNavObserver _magicObserver = MagicPlusNavObserver();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 启动后台同步：进入即同步一次，之后每 60s 增量同步。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncService.instance.sync();
    });
    _autoSync = Timer.periodic(
        const Duration(seconds: 60), (_) => SyncService.instance.sync());
  }

  @override
  void dispose() {
    _autoSync?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SyncService.instance.sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Things 3 克隆版',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      navigatorKey: _navKey,
      navigatorObservers: [_magicObserver],
      builder: (context, child) {
        // 让运行时中性色 getter 跟随当前亮度。
        AppTheme.isDark = Theme.of(context).brightness == Brightness.dark;
        // 全局常驻「魔法加号」：浮在 Navigator 之上，跨页面持续存在。
        return GlobalMagicPlus(
          navigatorKey: _navKey,
          observer: _magicObserver,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const DeepLinkHost(child: ResponsiveLayout()),
    );
  }
}
