import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/item_repository.dart';

enum SyncPhase { idle, syncing, success, error }

class SyncStatus {
  final SyncPhase phase;
  final String? message;
  final DateTime? lastSyncedAt;
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.message,
    this.lastSyncedAt,
  });

  SyncStatus copyWith({SyncPhase? phase, String? message, DateTime? lastSyncedAt}) =>
      SyncStatus(
        phase: phase ?? this.phase,
        message: message,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
}

/// 自托管云同步：基于服务器单调 seq 的增量拉取 + 全量推送 + 删除墓碑。
///
/// 本地优先，完全可选：未登录则什么都不做。登录后每次 [sync]：
///   1. 推送本地所有同步表的行 + 待删除墓碑；
///   2. 按 lastSeq 拉取服务器增量，应用 upsert/删除；
///   3. 推进 lastSeq、清除已推送的墓碑。
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final ItemRepository _repo = ItemRepository();
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  static const _kServer = 'sync_server_url';
  static const _kEmail = 'sync_email';
  static const _kToken = 'sync_token';
  static const _kUserId = 'sync_user_id';
  static const _kLastSeq = 'sync_last_seq';
  static const _kBackfilled = 'sync_backfilled';

  String? _serverUrl;
  String? _email;
  String? _token;
  bool _running = false;

  String? get serverUrl => _serverUrl;
  String? get email => _email;
  bool get isSignedIn => _token != null && _serverUrl != null;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _serverUrl = p.getString(_kServer);
    _email = p.getString(_kEmail);
    _token = p.getString(_kToken);
    final last = p.getInt(_kLastSeq);
    if (last != null) {
      status.value = status.value.copyWith();
    }
  }

  String _normalizeUrl(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    return u;
  }

  /// 用邮箱登录指定服务器，成功后保存凭据并把拉取游标重置为 0（首次全量拉取）。
  Future<void> signIn(String serverUrl, String email) async {
    final url = _normalizeUrl(serverUrl);
    final res = await http
        .post(
          Uri.parse('$url/auth'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('登录失败（${res.statusCode}）：${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = data['token'] as String?;
    final userId = data['userId'] as String?;
    if (token == null || userId == null) {
      throw Exception('登录响应无效');
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, url);
    await p.setString(_kEmail, email.trim());
    await p.setString(_kToken, token);
    await p.setString(_kUserId, userId);
    await p.setInt(_kLastSeq, 0);
    _serverUrl = url;
    _email = email.trim();
    _token = token;
  }

  Future<void> signOut() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kServer);
    await p.remove(_kEmail);
    await p.remove(_kToken);
    await p.remove(_kUserId);
    await p.remove(_kLastSeq);
    _serverUrl = null;
    _email = null;
    _token = null;
    status.value = const SyncStatus();
  }

  /// 执行一次同步。[silent] 为 true 时不抛异常（用于自动同步）。
  Future<bool> sync({bool silent = true}) async {
    if (!isSignedIn || _running) return false;
    _running = true;
    status.value = status.value.copyWith(phase: SyncPhase.syncing, message: '同步中…');
    try {
      final p = await SharedPreferences.getInstance();

      if (!(p.getBool(_kBackfilled) ?? false)) {
        await _repo.backfillTimestamps();
        await p.setBool(_kBackfilled, true);
      }

      // 1) 收集本地全量变更
      final changes = <Map<String, dynamic>>[];
      for (final table in ItemRepository.syncTables) {
        final rows = await _repo.allRows(table);
        if (rows.isNotEmpty) changes.add({'table': table, 'rows': rows});
      }
      // 2) 收集墓碑
      final tombstones = await _repo.pendingDeletions();
      final deletions = tombstones
          .map((t) => {
                'table': t['row_table'],
                'id': t['row_id'],
                'updated_at': t['deleted_at'],
              })
          .toList();
      final tombstoneIds =
          tombstones.map((t) => t['id'] as String).toList();

      final lastSeq = p.getInt(_kLastSeq) ?? 0;
      final res = await http
          .post(
            Uri.parse('$_serverUrl/sync'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $_token',
            },
            body: jsonEncode({
              'lastSeq': lastSeq,
              'changes': changes,
              'deletions': deletions,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        throw Exception('同步失败（${res.statusCode}）：${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // 3) 应用服务器增量
      final remoteChanges = (data['changes'] as List?) ?? const [];
      for (final group in remoteChanges) {
        final table = group['table'] as String;
        final rows = (group['rows'] as List?) ?? const [];
        for (final row in rows) {
          await _repo.applyRemoteUpsert(
              table, Map<String, dynamic>.from(row as Map));
        }
      }
      final remoteDeletions = (data['deletions'] as List?) ?? const [];
      for (final d in remoteDeletions) {
        await _repo.applyRemoteDelete(d['table'] as String, d['id'].toString());
      }

      // 4) 推进游标 + 清墓碑
      final newSeq = (data['seq'] as num?)?.toInt() ?? lastSeq;
      await p.setInt(_kLastSeq, newSeq);
      if (tombstoneIds.isNotEmpty) await _repo.clearDeletions(tombstoneIds);

      status.value = SyncStatus(
        phase: SyncPhase.success,
        message: '已同步',
        lastSyncedAt: DateTime.now(),
      );
      return true;
    } catch (e) {
      status.value = status.value.copyWith(
        phase: SyncPhase.error,
        message: '同步出错：$e',
      );
      if (!silent) rethrow;
      return false;
    } finally {
      _running = false;
    }
  }
}
