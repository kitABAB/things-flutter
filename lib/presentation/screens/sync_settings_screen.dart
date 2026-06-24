import 'package:flutter/material.dart';

import '../../data/services/sync_service.dart';
import '../shared/theme/app_theme.dart';

/// 云同步设置：填写自托管服务器地址 + 邮箱登录，手动「立即同步」并查看状态。
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _service = SyncService.instance;
  late final TextEditingController _serverCtrl;
  late final TextEditingController _emailCtrl;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(
        text: _service.serverUrl ?? 'http://192.168.31.50:4000');
    _emailCtrl = TextEditingController(text: _service.email ?? '');
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.signIn(_serverCtrl.text, _emailCtrl.text);
      await _service.sync(silent: false);
      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.sync(silent: false);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await _service.signOut();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _service.isSignedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('云同步')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('自托管同步',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            '在电脑上运行 server 文件夹的同步服务，填写其地址与邮箱即可多端同步。'
            '同一邮箱视为同一账号。',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _serverCtrl,
            enabled: !signedIn,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'http://192.168.x.x:4000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _emailCtrl,
            enabled: !signedIn,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱',
              hintText: 'you@example.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          if (!signedIn)
            FilledButton.icon(
              onPressed: _busy ? null : _signIn,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Text('登录并同步'),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done, color: AppTheme.primaryBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('已登录：${_service.email}',
                            style: Theme.of(context).textTheme.bodyLarge),
                        Text(_service.serverUrl ?? '',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _syncNow,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: const Text('立即同步'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('退出'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          ValueListenableBuilder<SyncStatus>(
            valueListenable: _service.status,
            builder: (context, s, _) {
              final color = switch (s.phase) {
                SyncPhase.error => Colors.red,
                SyncPhase.success => AppTheme.primaryBlue,
                _ => AppTheme.textSecondary,
              };
              final last = s.lastSyncedAt;
              final lastText = last == null
                  ? ''
                  : '  ·  上次：${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}:${last.second.toString().padLeft(2, '0')}';
              return Text('${s.message ?? '未同步'}$lastText',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: color));
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
