import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'schema.dart';
import 'sync_config.dart';
import 'supabase_connector.dart';
import 'dart:io';

late PowerSyncDatabase db;

Future<void> openDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}${Platform.pathSeparator}things3_clone_db.sqlite';

  db = PowerSyncDatabase(
    schema: appSchema,
    path: path,
  );

  await db.initialize();

  // 本地优先：默认离线模式。仅当填好 Supabase / PowerSync 配置时才接入云同步。
  if (SyncConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SyncConfig.supabaseUrl,
        anonKey: SyncConfig.supabaseAnonKey,
      );
      await maybeConnectSync();
    } catch (_) {
      // 同步初始化失败不影响本地使用。
    }
  }
}

/// 已登录则接入云同步；未登录保持离线，登录后可再次调用。
Future<void> maybeConnectSync() async {
  if (!SyncConfig.isConfigured) return;
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return;
  await db.connect(connector: SupabaseConnector(db));
}
