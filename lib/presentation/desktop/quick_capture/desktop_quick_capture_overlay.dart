import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../screens/ai_conversation_capture_screen.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/magic_plus.dart';
import 'desktop_quick_capture_controller.dart';

class DesktopQuickCaptureOverlay extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const DesktopQuickCaptureOverlay({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<DesktopQuickCaptureOverlay> createState() =>
      _DesktopQuickCaptureOverlayState();
}

class _DesktopQuickCaptureOverlayState
    extends State<DesktopQuickCaptureOverlay> {
  final _panelKey = GlobalKey<_DesktopQuickCapturePanelState>();

  DesktopQuickCaptureController get _controller =>
      DesktopQuickCaptureController.instance;

  @override
  Widget build(BuildContext context) {
    if (!DesktopQuickCaptureController.isSupported) return widget.child;

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: ValueListenableBuilder<bool>(
            valueListenable: _controller.visible,
            builder: (context, visible, _) {
              return IgnorePointer(
                ignoring: !visible,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  child: visible
                      ? _DesktopQuickCaptureLayer(
                          key: const ValueKey('desktop-quick-capture-layer'),
                          navigatorKey: widget.navigatorKey,
                          panelKey: _panelKey,
                          onDismiss: _controller.hide,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('desktop-quick-capture-empty'),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DesktopQuickCaptureLayer extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<_DesktopQuickCapturePanelState> panelKey;
  final VoidCallback onDismiss;

  const _DesktopQuickCaptureLayer({
    super.key,
    required this.navigatorKey,
    required this.panelKey,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 34,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width >= 980 ? 720 : 640,
                minWidth: 420,
              ),
              child:
                  _DesktopQuickCapturePanel(
                        key: panelKey,
                        navigatorKey: navigatorKey,
                        onDismiss: onDismiss,
                      )
                      .animate()
                      .fadeIn(duration: 160.ms)
                      .slideY(begin: 0.16, end: 0, curve: Curves.easeOutCubic)
                      .scale(
                        begin: const Offset(0.985, 0.985),
                        end: const Offset(1, 1),
                        duration: 180.ms,
                        curve: Curves.easeOutCubic,
                      ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopQuickCapturePanel extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final VoidCallback onDismiss;

  const _DesktopQuickCapturePanel({
    super.key,
    required this.navigatorKey,
    required this.onDismiss,
  });

  @override
  State<_DesktopQuickCapturePanel> createState() =>
      _DesktopQuickCapturePanelState();
}

class _DesktopQuickCapturePanelState extends State<_DesktopQuickCapturePanel> {
  final _input = TextEditingController();
  final _focusNode = FocusNode();
  final _speech = SpeechToText();

  bool _speechReady = false;
  bool _listening = false;
  String? _voiceError;
  String _voiceBase = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _speech.cancel();
    _input.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  BuildContext get _navContext =>
      widget.navigatorKey.currentState?.overlay?.context ??
      widget.navigatorKey.currentContext ??
      context;

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final createContext = MagicPlusController.instance.active.value;
    final navigator = Navigator.of(_navContext);
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(
        name: MagicPlusNavObserver.hidePlusRouteName,
      ),
      builder: (_) => AiConversationCaptureScreen(
        initialText: text,
        projectId: createContext.projectId,
        headingId: createContext.headingId,
      ),
    );
    if (_speech.isListening) await _speech.stop();
    _input.clear();
    widget.onDismiss();
    await navigator.push(route);
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    setState(() => _voiceError = null);
    try {
      if (!_speechReady) {
        _speechReady = await _speech.initialize(
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _voiceError = error.errorMsg;
              _listening = false;
            });
          },
          onStatus: (status) {
            if (!mounted) return;
            if (status == SpeechToText.doneStatus ||
                status == SpeechToText.notListeningStatus) {
              setState(() => _listening = false);
            }
          },
          finalTimeout: const Duration(milliseconds: 800),
        );
      }
      if (!_speechReady) {
        setState(() => _voiceError = '语音不可用');
        return;
      }

      _voiceBase = _input.text.trim();
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty || !mounted) return;
          final next = _voiceBase.isEmpty ? words : '$_voiceBase $words';
          _input
            ..text = next
            ..selection = TextSelection.collapsed(offset: next.length);
          setState(() {});
        },
        listenOptions: SpeechListenOptions(
          localeId: 'zh_CN',
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 45),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceError = '语音启动失败：$e';
        _listening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _input.text.trim().isNotEmpty;
    final hotKey = DesktopQuickCaptureController.instance.settings.value.hotKey;
    final shortcut = DesktopQuickCaptureSettings.labelFor(hotKey);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.primaryBlue.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppTheme.primaryBlue,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        'AI 捕获',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        shortcut,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: widget.onDismiss,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          fixedSize: const Size(32, 32),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF181B21)
                          : const Color(0xFFF6F8FB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.newline,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(fontSize: 15, height: 1.35),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: '说一个念头、任务或一组安排',
                              hintStyle: TextStyle(
                                color: AppTheme.textSecondary.withValues(
                                  alpha: 0.72,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                              contentPadding: const EdgeInsets.fromLTRB(
                                14,
                                13,
                                8,
                                13,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 6, bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: _toggleVoice,
                                icon: Icon(
                                  _listening
                                      ? Icons.graphic_eq_rounded
                                      : Icons.mic_none_rounded,
                                  size: 19,
                                ),
                                style: IconButton.styleFrom(
                                  foregroundColor: _listening
                                      ? AppTheme.primaryBlue
                                      : AppTheme.textSecondary,
                                  backgroundColor: _listening
                                      ? AppTheme.primaryBlue.withValues(
                                          alpha: 0.12,
                                        )
                                      : Colors.transparent,
                                  minimumSize: const Size(36, 36),
                                  fixedSize: const Size(36, 36),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton.filled(
                                onPressed: canSend ? _submit : null,
                                icon: const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 19,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.primaryBlue,
                                  disabledBackgroundColor: AppTheme
                                      .textSecondary
                                      .withValues(alpha: 0.16),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(36, 36),
                                  fixedSize: const Size(36, 36),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_voiceError != null || _listening) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _listening
                              ? Icons.fiber_manual_record_rounded
                              : Icons.info_outline_rounded,
                          size: 14,
                          color: _listening
                              ? AppTheme.deadlineRed
                              : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _listening ? '正在听...' : _voiceError!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _listening
                                      ? AppTheme.textSecondary
                                      : AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
