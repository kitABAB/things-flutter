import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sync_config.dart';

/// 把本地 PowerSync 的变更上传到 Supabase，并向其拉取凭据。
///
/// 标准的 PowerSync + Supabase 连接器：fetchCredentials 用当前登录会话换取
/// PowerSync 的访问令牌；uploadData 把本地 CRUD 批次回写到 Supabase 同名表。
class SupabaseConnector extends PowerSyncBackendConnector {
  final PowerSyncDatabase db;
  SupabaseConnector(this.db);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;
    return PowerSyncCredentials(
      endpoint: SyncConfig.powersyncUrl,
      token: session.accessToken,
      userId: session.user.id,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) return;

    final rest = Supabase.instance.client;
    try {
      for (final op in batch.crud) {
        final table = rest.from(op.table);
        switch (op.op) {
          case UpdateType.put:
            final data = Map<String, dynamic>.from(op.opData ?? {});
            data['id'] = op.id;
            await table.upsert(data);
            break;
          case UpdateType.patch:
            await table.update(op.opData ?? {}).eq('id', op.id);
            break;
          case UpdateType.delete:
            await table.delete().eq('id', op.id);
            break;
        }
      }
      await batch.complete();
    } catch (e) {
      // 网络/权限异常：保留批次，下次重试（PowerSync 会再次调用本方法）。
      rethrow;
    }
  }
}
