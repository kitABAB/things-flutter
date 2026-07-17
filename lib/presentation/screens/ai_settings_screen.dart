import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../ai/ai_providers.dart';
import '../../ai/config/ai_config.dart';
import '../../ai/config/model_connection.dart';
import '../../ai/core/llm_exception.dart';
import '../../ai/core/llm_message.dart';
import '../../ai/providers/openai_compat_client.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/magic_plus.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _uuid = const Uuid();
  final _expandedIds = <String>{};
  bool _batchTesting = false;

  Future<void> _addDraft() async {
    final preset = AiConfig.preset(AiProvider.openai, apiKey: '');
    final conn = ModelConnection(
      id: _uuid.v4(),
      label: '',
      provider: AiProvider.openai,
      baseUrl: preset.baseUrl,
      apiKey: '',
      models: const [],
      status: ModelConnectionStatus.unknown,
    );
    _expandedIds.add(conn.id);
    await ref.read(aiSettingsProvider.notifier).upsertConnection(conn);
    _toast('草稿已保存');
  }

  Future<void> _testConnection(ModelConnection conn) async {
    if (!conn.isReady) {
      _toast('草稿已保存');
      await ref
          .read(aiSettingsProvider.notifier)
          .upsertConnection(
            conn.copyWith(status: ModelConnectionStatus.unknown),
          );
      return;
    }

    try {
      final cfg = conn.configFor(conn.primaryModel);
      await OpenAiCompatClient(cfg).complete([
        const LlmMessage.user('reply with the single word: ok'),
      ], timeout: const Duration(seconds: 15));
      await ref
          .read(aiSettingsProvider.notifier)
          .upsertConnection(conn.copyWith(status: ModelConnectionStatus.ok));
      _toast('测试完成');
    } on LlmException catch (e) {
      await ref
          .read(aiSettingsProvider.notifier)
          .upsertConnection(
            conn.copyWith(status: ModelConnectionStatus.failed),
          );
      _toast(e.message);
    } catch (e) {
      await ref
          .read(aiSettingsProvider.notifier)
          .upsertConnection(
            conn.copyWith(status: ModelConnectionStatus.failed),
          );
      _toast('连接失败：$e');
    }
  }

  Future<void> _batchTest(AiSettings settings) async {
    final ready = settings.connections.where((c) => c.isReady).toList();
    if (ready.isEmpty) {
      _toast('没有可用模型');
      return;
    }

    setState(() => _batchTesting = true);
    try {
      for (final conn in ready) {
        if (!mounted) return;
        await _testConnection(conn);
      }
    } finally {
      if (mounted) setState(() => _batchTesting = false);
    }
  }

  void _openAdvanced(AiSettings settings) {
    if (MediaQuery.sizeOf(context).width >= 900) {
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 430,
            child: _FunctionStrategySheet(settings: settings),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _FunctionStrategySheet(settings: settings),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final connections = settings.connections;
    final desktop = MediaQuery.sizeOf(context).width >= 900;

    if (desktop) {
      return _buildDesktop(context, settings, connections);
    }

    return MagicCreateScope(
      context: const MagicCreateContext(hidePlus: true),
      child: _buildMobile(context, settings, connections),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    AiSettings settings,
    List<ModelConnection> connections,
  ) {
    return Scaffold(
      backgroundColor: _AiPalette.page(context),
      appBar: AppBar(
        backgroundColor: _AiPalette.page(context),
        leading: const BackButton(),
        titleSpacing: 0,
        title: _StrategyTitle(
          name: settings.strategyName,
          onChanged: (value) =>
              ref.read(aiSettingsProvider.notifier).renameStrategy(value),
        ),
        actions: [
          IconButton(
            tooltip: '功能策略',
            onPressed: () => _openAdvanced(settings),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: '批量测试',
            onPressed: _batchTesting ? null : () => _batchTest(settings),
            icon: _batchTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bolt_rounded),
          ),
          IconButton.filled(
            tooltip: '添加',
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: _addDraft,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: connections.isEmpty
                ? _EmptyStrategy(onAdd: _addDraft)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    itemCount: connections.length,
                    onReorderItem: ref
                        .read(aiSettingsProvider.notifier)
                        .reorderConnection,
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      final conn = connections[index];
                      return Padding(
                        key: ValueKey(conn.id),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ModelStrategyCard(
                          index: index,
                          connection: conn,
                          settings: settings,
                          expanded: _expandedIds.contains(conn.id),
                          onExpandedChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedIds.add(conn.id);
                              } else {
                                _expandedIds.remove(conn.id);
                              }
                            });
                            if (!conn.isReady) _toast('草稿已保存');
                          },
                          onChanged: (next) => ref
                              .read(aiSettingsProvider.notifier)
                              .upsertConnection(next),
                          onDelete: () => ref
                              .read(aiSettingsProvider.notifier)
                              .removeConnection(conn.id),
                          onTest: () => _testConnection(conn),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _AddCardButton(onTap: _addDraft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    AiSettings settings,
    List<ModelConnection> connections,
  ) {
    return Scaffold(
      backgroundColor: _AiPalette.page(context),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: _AiPalette.panel(context),
                border: Border(
                  bottom: BorderSide(color: _AiPalette.line(context)),
                ),
              ),
              child: Row(
                children: [
                  const BackButton(),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 320,
                    child: _StrategyTitle(
                      name: settings.strategyName,
                      onChanged: (value) => ref
                          .read(aiSettingsProvider.notifier)
                          .renameStrategy(value),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '功能策略',
                    onPressed: () => _openAdvanced(settings),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  IconButton(
                    tooltip: '批量测试',
                    onPressed: _batchTesting
                        ? null
                        : () => _batchTest(settings),
                    icon: _batchTesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt_rounded),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addDraft,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('添加'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 14, 24),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _AiPalette.panel(context),
                            border: Border.all(color: _AiPalette.line(context)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: connections.isEmpty
                              ? _EmptyStrategy(onAdd: _addDraft)
                              : _connectionList(
                                  settings,
                                  connections,
                                  const EdgeInsets.fromLTRB(18, 18, 18, 24),
                                ),
                        ),
                      ),
                    ),
                  ),
                  _AiDesktopAside(
                    settings: settings,
                    batchTesting: _batchTesting,
                    onAdvanced: () => _openAdvanced(settings),
                    onBatchTest: () => _batchTest(settings),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionList(
    AiSettings settings,
    List<ModelConnection> connections,
    EdgeInsets padding,
  ) {
    return ReorderableListView.builder(
      padding: padding,
      itemCount: connections.length,
      onReorderItem: ref.read(aiSettingsProvider.notifier).reorderConnection,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final conn = connections[index];
        return Padding(
          key: ValueKey(conn.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: _ModelStrategyCard(
            index: index,
            connection: conn,
            settings: settings,
            expanded: _expandedIds.contains(conn.id),
            onExpandedChanged: (expanded) {
              setState(() {
                if (expanded) {
                  _expandedIds.add(conn.id);
                } else {
                  _expandedIds.remove(conn.id);
                }
              });
              if (!conn.isReady) _toast('草稿已保存');
            },
            onChanged: (next) =>
                ref.read(aiSettingsProvider.notifier).upsertConnection(next),
            onDelete: () =>
                ref.read(aiSettingsProvider.notifier).removeConnection(conn.id),
            onTest: () => _testConnection(conn),
          ),
        );
      },
    );
  }
}

class _AiPalette {
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color page(BuildContext context) =>
      _dark(context) ? const Color(0xFF101115) : const Color(0xFFF5F7FA);

  static Color panel(BuildContext context) =>
      _dark(context) ? const Color(0xFF15171C) : Colors.white;

  static Color card(BuildContext context, {required bool gateway}) {
    if (_dark(context)) {
      return gateway ? const Color(0xFF1A1722) : const Color(0xFF171A20);
    }
    return gateway ? const Color(0xFFF8F6FF) : Colors.white;
  }

  static Color cardBorder(
    BuildContext context, {
    required bool gateway,
    required bool complete,
  }) {
    if (!complete) return warning(context).withValues(alpha: 0.85);
    if (gateway) {
      return gatewayAccent.withValues(alpha: _dark(context) ? 0.34 : 0.24);
    }
    return line(context);
  }

  static Color line(BuildContext context) =>
      _dark(context) ? const Color(0xFF2B3038) : const Color(0xFFE1E5EC);

  static Color field(BuildContext context) =>
      _dark(context) ? const Color(0xFF101218) : const Color(0xFFF8FAFC);

  static Color control(BuildContext context) =>
      _dark(context) ? const Color(0xFF222631) : const Color(0xFFF0F3F7);

  static Color controlActive(BuildContext context) =>
      _dark(context) ? const Color(0xFF11141A) : Colors.white;

  static Color text(BuildContext context) =>
      _dark(context) ? const Color(0xFFF3F5F7) : const Color(0xFF1A1D23);

  static Color muted(BuildContext context) =>
      _dark(context) ? const Color(0xFFA2AAB6) : const Color(0xFF737B87);

  static Color subtle(BuildContext context) =>
      _dark(context) ? const Color(0xFF7D8490) : const Color(0xFF9AA1AC);

  static Color selectedFill(BuildContext context) => _dark(context)
      ? AppTheme.primaryBlue.withValues(alpha: 0.18)
      : AppTheme.primaryBlue.withValues(alpha: 0.08);

  static Color warning(BuildContext context) =>
      _dark(context) ? const Color(0xFFE6A817) : const Color(0xFFD99A00);

  static Color warningBg(BuildContext context) =>
      _dark(context) ? const Color(0xFF302612) : const Color(0xFFFFF4D6);

  static Color warningText(BuildContext context) =>
      _dark(context) ? const Color(0xFFF5CF75) : const Color(0xFF7C5600);

  static Color protocolBg(BuildContext context) =>
      _dark(context) ? const Color(0xFF141821) : const Color(0xFFF1F4F8);

  static Color protocolText(BuildContext context) =>
      _dark(context) ? const Color(0xFFC9D0DA) : const Color(0xFF4D5663);

  static const Color gatewayAccent = Color(0xFF8B7CF6);
}

class _AiDesktopAside extends StatelessWidget {
  final AiSettings settings;
  final bool batchTesting;
  final VoidCallback onAdvanced;
  final VoidCallback onBatchTest;

  const _AiDesktopAside({
    required this.settings,
    required this.batchTesting,
    required this.onAdvanced,
    required this.onBatchTest,
  });

  @override
  Widget build(BuildContext context) {
    final ready = settings.readyConnections.length;
    final total = settings.connections.length;

    return Container(
      width: 320,
      margin: const EdgeInsets.fromLTRB(0, 20, 24, 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _AiPalette.panel(context),
        border: Border.all(color: _AiPalette.line(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.primaryBlue,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  settings.strategyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _AsideMetric(label: '可用', value: '$ready'),
          const SizedBox(height: 8),
          _AsideMetric(label: '全部', value: '$total'),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 10),
          _AsideAction(
            icon: Icons.tune_rounded,
            label: '功能策略',
            onTap: onAdvanced,
          ),
          _AsideAction(
            icon: Icons.bolt_rounded,
            label: batchTesting ? '测试中' : '批量测试',
            onTap: batchTesting ? null : onBatchTest,
          ),
          const Spacer(),
          Text(
            'OpenAI-compatible',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AsideMetric extends StatelessWidget {
  final String label;
  final String value;

  const _AsideMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _AiPalette.control(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AsideAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _AsideAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _AiPalette.muted(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _StrategyTitle extends StatefulWidget {
  final String name;
  final ValueChanged<String> onChanged;

  const _StrategyTitle({required this.name, required this.onChanged});

  @override
  State<_StrategyTitle> createState() => _StrategyTitleState();
}

class _StrategyTitleState extends State<_StrategyTitle> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
  }

  @override
  void didUpdateWidget(covariant _StrategyTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.name != _controller.text) {
      _controller.text = widget.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          maxLines: 1,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF20B26B),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '已自动保存',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AiPalette.muted(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyStrategy extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyStrategy({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(child: _AddCardButton(onTap: onAdd));
  }
}

class _AddCardButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddCardButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 58,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _AiPalette.control(context).withValues(alpha: 0.44),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.primaryBlue.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.add_rounded,
          color: AppTheme.primaryBlue.withValues(alpha: 0.86),
        ),
      ),
    );
  }
}

class _ModelStrategyCard extends StatefulWidget {
  final int index;
  final ModelConnection connection;
  final AiSettings settings;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<ModelConnection> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onTest;

  const _ModelStrategyCard({
    required this.index,
    required this.connection,
    required this.settings,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onChanged,
    required this.onDelete,
    required this.onTest,
  });

  @override
  State<_ModelStrategyCard> createState() => _ModelStrategyCardState();
}

class _ModelStrategyCardState extends State<_ModelStrategyCard> {
  late final TextEditingController _apiKey;
  late final TextEditingController _gatewayName;
  late final TextEditingController _baseUrl;
  late final TextEditingController _gatewayKey;
  bool _protocolOpen = false;
  List<String> _fetchedModels = const ['qwen-plus', 'qwen-max'];
  bool _fetching = false;

  bool get _isGateway => widget.connection.provider == AiProvider.custom;

  @override
  void initState() {
    super.initState();
    _apiKey = TextEditingController(text: widget.connection.apiKey);
    _gatewayName = TextEditingController(text: widget.connection.label);
    _baseUrl = TextEditingController(text: widget.connection.baseUrl);
    _gatewayKey = TextEditingController(text: widget.connection.apiKey);
  }

  @override
  void didUpdateWidget(covariant _ModelStrategyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_apiKey, widget.connection.apiKey);
    _sync(_gatewayName, widget.connection.label);
    _sync(_baseUrl, widget.connection.baseUrl);
    _sync(_gatewayKey, widget.connection.apiKey);
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _gatewayName.dispose();
    _baseUrl.dispose();
    _gatewayKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = widget.connection;
    final complete = conn.isReady;
    final color = _AiPalette.card(context, gateway: _isGateway);
    final border = _AiPalette.cardBorder(
      context,
      gateway: _isGateway,
      complete: complete,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: complete ? 1 : 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.20
                  : 0.05,
            ),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => widget.onExpandedChanged(!widget.expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: _AiPalette.subtle(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ProviderLogo(connection: conn),
                  const SizedBox(width: 12),
                  Expanded(child: _CardTitle(connection: conn)),
                  if (!complete) ...[
                    const SizedBox(width: 6),
                    const _WarningIcon(),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '测试',
                    onPressed: widget.onTest,
                    icon: const Icon(Icons.bolt_rounded),
                    color: AppTheme.primaryBlue,
                  ),
                  IconButton(
                    tooltip: widget.expanded ? '收起' : '展开',
                    onPressed: () => widget.onExpandedChanged(!widget.expanded),
                    color: _AiPalette.subtle(context),
                    icon: AnimatedRotation(
                      turns: widget.expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: widget.expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: _isGateway ? _gatewayEditor() : _cloudEditor(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cloudEditor() {
    final selected = _presets.firstWhere(
      (p) =>
          p.provider == widget.connection.provider &&
          p.model == widget.connection.primaryModel,
      orElse: () => _presets.first,
    );
    final missingKey = widget.connection.apiKey.trim().isEmpty;
    final missingModel = widget.connection.primaryModel.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeSwitch(isGateway: false, onChanged: _switchMode),
        const SizedBox(height: 10),
        _SearchBox(),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(label: '全部', active: true),
              _FilterChip(label: 'OpenAI'),
              _FilterChip(label: 'Gemini'),
              _FilterChip(label: 'DeepSeek'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final preset in _presets.take(3))
          _PresetTile(
            preset: preset,
            selected:
                selected.model == preset.model &&
                widget.connection.primaryModel == preset.model,
            onTap: () => _selectPreset(preset),
          ),
        const SizedBox(height: 10),
        _TextFieldShell(
          controller: _apiKey,
          hintText: 'API Key',
          mono: true,
          secret: true,
          onChanged: (value) => _saveCloud(apiKey: value),
        ),
        const SizedBox(height: 8),
        _ValidationRow(
          messages: [if (missingModel) '缺模型', if (missingKey) '缺 API Key'],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '删除',
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: _AiPalette.subtle(context),
          ),
        ),
      ],
    );
  }

  Widget _gatewayEditor() {
    final missingBase = !_validBaseUrl(widget.connection.baseUrl);
    final missingModel = widget.connection.primaryModel.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeSwitch(isGateway: true, onChanged: _switchMode),
        const SizedBox(height: 10),
        _TextFieldShell(
          controller: _gatewayName,
          hintText: '网关名称',
          onChanged: (value) => _saveGateway(label: value),
        ),
        const SizedBox(height: 8),
        _TextFieldShell(
          controller: _baseUrl,
          hintText: 'Base URL',
          mono: true,
          onChanged: (value) => _saveGateway(baseUrl: value),
        ),
        const SizedBox(height: 8),
        _TextFieldShell(
          controller: _gatewayKey,
          hintText: 'API Key 可选',
          mono: true,
          secret: true,
          onChanged: (value) => _saveGateway(apiKey: value),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _SmallSegment(label: 'Bearer', active: true),
            _SmallSegment(label: '无'),
            _SmallSegment(label: 'Header'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: _fetching ? null : _fetchModels,
              style: FilledButton.styleFrom(
                backgroundColor: _AiPalette.control(context),
                foregroundColor: _AiPalette.text(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              icon: _fetching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('拉取'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() => _protocolOpen = !_protocolOpen),
              style: TextButton.styleFrom(
                foregroundColor: _AiPalette.muted(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: AnimatedRotation(
                turns: _protocolOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              label: const Text('协议要求'),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _protocolOpen
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _AiPalette.protocolBg(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _AiPalette.line(context)),
            ),
            child: Text(
              'OpenAI Chat Completions: POST {baseUrl}/chat/completions\n'
              '可选: GET {baseUrl}/models',
              style: TextStyle(
                color: _AiPalette.protocolText(context),
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final model in _gatewayModels)
              ChoiceChip(
                label: Text(model),
                selected: widget.connection.models.contains(model),
                onSelected: (_) => _toggleGatewayModel(model),
                selectedColor: _AiPalette.selectedFill(context),
                backgroundColor: _AiPalette.control(context),
                checkmarkColor: AppTheme.primaryBlue,
                labelStyle: TextStyle(
                  color: widget.connection.models.contains(model)
                      ? AppTheme.primaryBlue
                      : _AiPalette.muted(context),
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(
                  color: widget.connection.models.contains(model)
                      ? AppTheme.primaryBlue.withValues(alpha: 0.42)
                      : _AiPalette.line(context),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _ValidationRow(
          messages: [if (missingBase) '缺 Base URL', if (missingModel) '缺模型'],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '删除',
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: _AiPalette.subtle(context),
          ),
        ),
      ],
    );
  }

  List<String> get _gatewayModels {
    final set = <String>{..._fetchedModels, ...widget.connection.models};
    return set.where((m) => m.trim().isNotEmpty).toList();
  }

  void _selectPreset(_ModelPreset preset) {
    final reusableKey = _savedKeyFor(preset.provider);
    _apiKey.text = widget.connection.apiKey.isNotEmpty
        ? widget.connection.apiKey
        : reusableKey;
    _saveCloud(
      provider: preset.provider,
      label: preset.name,
      model: preset.model,
      baseUrl: AiConfig.preset(preset.provider, apiKey: '').baseUrl,
      apiKey: _apiKey.text,
    );
  }

  String _savedKeyFor(AiProvider provider) {
    for (final c in widget.settings.connections) {
      if (c.id != widget.connection.id &&
          c.provider == provider &&
          c.apiKey.trim().isNotEmpty) {
        return c.apiKey;
      }
    }
    return '';
  }

  void _saveCloud({
    AiProvider? provider,
    String? label,
    String? model,
    String? baseUrl,
    String? apiKey,
  }) {
    final next = widget.connection.copyWith(
      provider: provider ?? widget.connection.provider,
      label: label ?? widget.connection.label,
      baseUrl: baseUrl ?? widget.connection.baseUrl,
      apiKey: apiKey ?? widget.connection.apiKey,
      models: model != null ? [model] : widget.connection.models,
      status: ModelConnectionStatus.unknown,
    );
    widget.onChanged(next);
  }

  void _saveGateway({
    String? label,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
  }) {
    final next = widget.connection.copyWith(
      provider: AiProvider.custom,
      label: label ?? widget.connection.label,
      baseUrl: baseUrl ?? widget.connection.baseUrl,
      apiKey: apiKey ?? widget.connection.apiKey,
      models: models ?? widget.connection.models,
      status: ModelConnectionStatus.unknown,
    );
    widget.onChanged(next);
  }

  void _switchMode(bool gateway) {
    if (gateway) {
      final currentLabel = widget.connection.label.trim();
      final cloudPresetLabel = _presets.any((p) => p.name == currentLabel);
      final nextLabel =
          currentLabel.isEmpty ||
              cloudPresetLabel ||
              widget.connection.provider != AiProvider.custom
          ? '自定义网关'
          : currentLabel;
      _saveGateway(label: nextLabel, baseUrl: '', apiKey: '', models: const []);
    } else {
      final preset = _presets.first;
      _selectPreset(preset);
    }
  }

  Future<void> _fetchModels() async {
    final base = _baseUrl.text.trim();
    if (!_validBaseUrl(base)) {
      widget.onChanged(
        widget.connection.copyWith(
          baseUrl: base,
          status: ModelConnectionStatus.unknown,
        ),
      );
      return;
    }
    setState(() => _fetching = true);
    try {
      final cfg = AiConfig(
        provider: AiProvider.custom,
        baseUrl: base,
        model: widget.connection.primaryModel.isEmpty
            ? 'placeholder'
            : widget.connection.primaryModel,
        apiKey: _gatewayKey.text.trim(),
      );
      final models = await OpenAiCompatClient(cfg).listModels();
      if (models.isNotEmpty) {
        setState(() => _fetchedModels = models);
        if (widget.connection.models.isEmpty) {
          _saveGateway(models: [models.first]);
        }
      }
    } on LlmException catch (_) {
      setState(() => _fetchedModels = const ['qwen-plus', 'qwen-max']);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _toggleGatewayModel(String model) {
    final models = [...widget.connection.models];
    if (models.contains(model)) {
      models.remove(model);
    } else {
      models
        ..clear()
        ..add(model);
    }
    _saveGateway(models: models);
  }

  bool _validBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

class _CardTitle extends StatelessWidget {
  final ModelConnection connection;

  const _CardTitle({required this.connection});

  @override
  Widget build(BuildContext context) {
    final title = _titleFor(connection);
    final provider = connection.provider == AiProvider.custom
        ? '自定义网关'
        : connection.provider.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _AiPalette.text(context),
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Flexible(
              child: Text(
                provider,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _AiPalette.muted(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 7),
            _StatusLight(connection: connection),
          ],
        ),
      ],
    );
  }

  static String _titleFor(ModelConnection connection) {
    if (connection.provider == AiProvider.custom) {
      final label = connection.label.trim().isEmpty
          ? '自定义网关'
          : connection.label.trim();
      if (connection.primaryModel.isEmpty) return label;
      return '$label / ${connection.primaryModel}';
    }
    if (connection.primaryModel.isEmpty) return '选择模型';
    final preset = _presets.where((p) => p.model == connection.primaryModel);
    return preset.isEmpty ? connection.primaryModel : preset.first.name;
  }
}

class _ProviderLogo extends StatelessWidget {
  final ModelConnection connection;

  const _ProviderLogo({required this.connection});

  @override
  Widget build(BuildContext context) {
    final style = _logoStyle(connection);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        style.letter,
        style: TextStyle(
          color: style.foreground,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }

  _LogoStyle _logoStyle(ModelConnection c) {
    if (c.primaryModel.isEmpty && c.provider != AiProvider.custom) {
      return const _LogoStyle('+', Color(0xFFFFF4D6), Color(0xFFD99A00));
    }
    switch (c.provider) {
      case AiProvider.gemini:
        return const _LogoStyle('G', Color(0xFFEEF3FF), Color(0xFF586BEF));
      case AiProvider.openai:
        return const _LogoStyle('O', Color(0xFFF1F2F5), Color(0xFF17171C));
      case AiProvider.deepseek:
        return const _LogoStyle('D', Color(0xFFE7FAF8), Color(0xFF13A9A0));
      case AiProvider.custom:
        return const _LogoStyle('网', Color(0xFFF0ECFF), Color(0xFF7A67F2));
    }
  }
}

class _LogoStyle {
  final String letter;
  final Color background;
  final Color foreground;

  const _LogoStyle(this.letter, this.background, this.foreground);
}

class _StatusLight extends StatelessWidget {
  final ModelConnection connection;

  const _StatusLight({required this.connection});

  @override
  Widget build(BuildContext context) {
    final color = !connection.isReady
        ? _AiPalette.warning(context)
        : switch (connection.status) {
            ModelConnectionStatus.ok => const Color(0xFF20B26B),
            ModelConnectionStatus.failed => const Color(0xFFE5484D),
            ModelConnectionStatus.unknown => _AiPalette.warning(context),
          };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.26),
            blurRadius: 7,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _WarningIcon extends StatelessWidget {
  const _WarningIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: _AiPalette.warningBg(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.priority_high_rounded,
        color: _AiPalette.warning(context),
        size: 17,
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final bool isGateway;
  final ValueChanged<bool> onChanged;

  const _ModeSwitch({required this.isGateway, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _AiPalette.control(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: '云模型',
              active: !isGateway,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _ModeButton(
              label: '网关',
              active: isGateway,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _AiPalette.controlActive(context) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppTheme.primaryBlue : _AiPalette.muted(context),
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _AiPalette.field(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AiPalette.line(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: _AiPalette.subtle(context),
          ),
          const SizedBox(width: 8),
          Text(
            'gpt / gemini / deepseek',
            style: TextStyle(
              color: _AiPalette.muted(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;

  const _FilterChip({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        backgroundColor: active
            ? _AiPalette.selectedFill(context)
            : _AiPalette.control(context),
        labelStyle: TextStyle(
          color: active ? AppTheme.primaryBlue : _AiPalette.muted(context),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        side: BorderSide.none,
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final _ModelPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: selected
                ? _AiPalette.selectedFill(context)
                : _AiPalette.field(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryBlue.withValues(alpha: 0.45)
                  : _AiPalette.line(context),
            ),
          ),
          child: Row(
            children: [
              _PresetLogo(preset: preset),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        color: _AiPalette.text(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${preset.provider.label} · ${preset.tag}',
                      style: TextStyle(
                        color: _AiPalette.muted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.primaryBlue,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetLogo extends StatelessWidget {
  final _ModelPreset preset;

  const _PresetLogo({required this.preset});

  @override
  Widget build(BuildContext context) {
    final style = switch (preset.provider) {
      AiProvider.gemini => const _LogoStyle(
        'G',
        Color(0xFFEEF3FF),
        Color(0xFF586BEF),
      ),
      AiProvider.openai => const _LogoStyle(
        'O',
        Color(0xFFF1F2F5),
        Color(0xFF17171C),
      ),
      AiProvider.deepseek => const _LogoStyle(
        'D',
        Color(0xFFE7FAF8),
        Color(0xFF13A9A0),
      ),
      AiProvider.custom => const _LogoStyle(
        '网',
        Color(0xFFF0ECFF),
        Color(0xFF7A67F2),
      ),
    };
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        style.letter,
        style: TextStyle(color: style.foreground, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _TextFieldShell extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool mono;
  final bool secret;

  const _TextFieldShell({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.mono = false,
    this.secret = false,
  });

  @override
  State<_TextFieldShell> createState() => _TextFieldShellState();
}

class _TextFieldShellState extends State<_TextFieldShell> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      obscureText: widget.secret && _obscured,
      obscuringCharacter: '•',
      enableSuggestions: !widget.secret,
      autocorrect: false,
      style: TextStyle(
        color: _AiPalette.text(context),
        fontFamily: widget.mono ? 'monospace' : null,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        filled: true,
        fillColor: _AiPalette.field(context),
        hintStyle: TextStyle(
          color: _AiPalette.subtle(context),
          fontWeight: FontWeight.w600,
        ),
        suffixIcon: widget.secret
            ? IconButton(
                tooltip: _obscured ? '显示' : '隐藏',
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                color: _AiPalette.subtle(context),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _AiPalette.line(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _AiPalette.line(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppTheme.primaryBlue.withValues(alpha: 0.72),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

class _SmallSegment extends StatelessWidget {
  final String label;
  final bool active;

  const _SmallSegment({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 5),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? _AiPalette.controlActive(context)
              : _AiPalette.control(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: active ? AppTheme.primaryBlue : _AiPalette.muted(context),
          ),
        ),
      ),
    );
  }
}

class _ValidationRow extends StatelessWidget {
  final List<String> messages;

  const _ValidationRow({required this.messages});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final message in messages)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _AiPalette.warningBg(context),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.priority_high_rounded,
                  size: 13,
                  color: _AiPalette.warning(context),
                ),
                const SizedBox(width: 3),
                Text(
                  message,
                  style: TextStyle(
                    color: _AiPalette.warningText(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FunctionStrategySheet extends StatelessWidget {
  final AiSettings settings;

  const _FunctionStrategySheet({required this.settings});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '功能策略',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            _FunctionRow(label: '智能捕获', strategy: settings.strategyName),
            _FunctionRow(label: 'AI 理清', strategy: settings.strategyName),
            _FunctionRow(label: '回顾建议', strategy: settings.strategyName),
          ],
        ),
      ),
    );
  }
}

class _FunctionRow extends StatelessWidget {
  final String label;
  final String strategy;

  const _FunctionRow({required this.label, required this.strategy});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(strategy),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _ModelPreset {
  final String name;
  final AiProvider provider;
  final String model;
  final String tag;

  const _ModelPreset({
    required this.name,
    required this.provider,
    required this.model,
    required this.tag,
  });
}

const _presets = [
  _ModelPreset(
    name: 'Gemini 2.5 Flash',
    provider: AiProvider.gemini,
    model: 'gemini-2.5-flash',
    tag: '快速',
  ),
  _ModelPreset(
    name: 'DeepSeek Chat',
    provider: AiProvider.deepseek,
    model: 'deepseek-chat',
    tag: '中文理清',
  ),
  _ModelPreset(
    name: 'GPT-4.1 mini',
    provider: AiProvider.openai,
    model: 'gpt-4.1-mini',
    tag: '通用',
  ),
];
