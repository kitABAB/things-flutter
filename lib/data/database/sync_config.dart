/// 云同步配置（多端同步）。
///
/// 默认全部留空 → App 以「本地优先 / 纯离线」模式运行，绝不影响使用。
/// 要开启同步，请填入你自己的 Supabase 与 PowerSync 实例信息，并在后端：
///   1. 在 Supabase 建好与 [appSchema] 同名的表（items / areas / checklist_items / tags / item_tags），
///      字段与本地一致，并开启 Row Level Security 按 user_id 隔离；
///   2. 在 PowerSync 控制台配置指向该 Supabase 的 Sync Rules；
///   3. 用 Supabase Auth（邮箱/匿名登录）登录后即开始双向同步。
class SyncConfig {
  /// 例如 https://xxxx.supabase.co
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon public key
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// 例如 https://xxxx.powersync.journeyapps.com
  static const String powersyncUrl = String.fromEnvironment('POWERSYNC_URL');

  /// 三者齐全才视为已配置；否则保持纯本地模式。
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      powersyncUrl.isNotEmpty;
}
