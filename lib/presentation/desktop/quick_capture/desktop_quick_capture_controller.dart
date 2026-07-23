import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class DesktopQuickCaptureSettings {
  static const _hotKeyIdentifier = 'things.desktop.quick.capture';

  final bool enabled;
  final HotKey hotKey;

  const DesktopQuickCaptureSettings({
    required this.enabled,
    required this.hotKey,
  });

  factory DesktopQuickCaptureSettings.defaults() {
    return DesktopQuickCaptureSettings(
      enabled: true,
      hotKey: HotKey(
        identifier: _hotKeyIdentifier,
        key: PhysicalKeyboardKey.space,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
    );
  }

  factory DesktopQuickCaptureSettings.fromJson(Map<String, dynamic> json) {
    try {
      final rawHotKey = json['hotKey'];
      return DesktopQuickCaptureSettings(
        enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
        hotKey: rawHotKey is Map<String, dynamic>
            ? normalizeHotKey(HotKey.fromJson(rawHotKey))
            : DesktopQuickCaptureSettings.defaults().hotKey,
      );
    } catch (_) {
      return DesktopQuickCaptureSettings.defaults();
    }
  }

  DesktopQuickCaptureSettings copyWith({bool? enabled, HotKey? hotKey}) {
    return DesktopQuickCaptureSettings(
      enabled: enabled ?? this.enabled,
      hotKey: hotKey == null ? this.hotKey : normalizeHotKey(hotKey),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hotKey': hotKey.toJson(),
  };

  static HotKey normalizeHotKey(HotKey hotKey) {
    return HotKey(
      identifier: _hotKeyIdentifier,
      key: hotKey.key,
      modifiers: _sortedModifiers(hotKey.modifiers ?? const []),
      scope: HotKeyScope.system,
    );
  }

  static bool hasModifier(HotKey hotKey) =>
      (hotKey.modifiers ?? const <HotKeyModifier>[]).isNotEmpty;

  static String labelFor(HotKey hotKey) {
    final parts = [
      for (final modifier in hotKey.modifiers ?? const <HotKeyModifier>[])
        _modifierLabel(modifier),
      _keyLabel(hotKey.key),
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? '未设置' : parts.join(' + ');
  }

  static List<HotKeyModifier> _sortedModifiers(List<HotKeyModifier> modifiers) {
    const order = [
      HotKeyModifier.control,
      HotKeyModifier.meta,
      HotKeyModifier.alt,
      HotKeyModifier.shift,
      HotKeyModifier.capsLock,
      HotKeyModifier.fn,
    ];
    return [
      for (final modifier in order)
        if (modifiers.contains(modifier)) modifier,
    ];
  }

  static String _modifierLabel(HotKeyModifier modifier) {
    switch (modifier) {
      case HotKeyModifier.control:
        return 'Ctrl';
      case HotKeyModifier.meta:
        return defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd' : 'Win';
      case HotKeyModifier.alt:
        return defaultTargetPlatform == TargetPlatform.macOS ? 'Option' : 'Alt';
      case HotKeyModifier.shift:
        return 'Shift';
      case HotKeyModifier.capsLock:
        return 'Caps';
      case HotKeyModifier.fn:
        return 'Fn';
    }
  }

  static String _keyLabel(KeyboardKey key) {
    final debugName = switch (key) {
      PhysicalKeyboardKey physical => physical.debugName ?? '',
      LogicalKeyboardKey logical => logical.debugName ?? '',
      _ => '',
    };
    if (debugName.isEmpty) return key.toString();
    if (debugName.startsWith('Key ')) return debugName.substring(4);
    if (debugName == 'Space') return 'Space';
    if (debugName == 'Backquote') return '`';
    if (debugName.startsWith('Digit ')) return debugName.substring(6);
    return debugName;
  }
}

class DesktopQuickCaptureSettingsStore {
  static const _key = 'desktop_quick_capture_settings_v1';

  const DesktopQuickCaptureSettingsStore();

  Future<DesktopQuickCaptureSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) {
      return DesktopQuickCaptureSettings.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DesktopQuickCaptureSettings.fromJson(decoded);
      }
    } catch (_) {
      // Fall through to the default shortcut if old data is malformed.
    }
    return DesktopQuickCaptureSettings.defaults();
  }

  Future<void> save(DesktopQuickCaptureSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}

class DesktopQuickCaptureController {
  DesktopQuickCaptureController._();

  static final DesktopQuickCaptureController instance =
      DesktopQuickCaptureController._();

  final settings = ValueNotifier<DesktopQuickCaptureSettings>(
    DesktopQuickCaptureSettings.defaults(),
  );
  final visible = ValueNotifier<bool>(false);
  final lastError = ValueNotifier<String?>(null);

  final _store = const DesktopQuickCaptureSettingsStore();
  HotKey? _registeredHotKey;
  bool _initialized = false;

  static bool get isSupported {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  Future<void> init() async {
    if (_initialized || !isSupported) return;
    _initialized = true;
    try {
      await windowManager.ensureInitialized();
    } catch (_) {
      // Window focusing is a best-effort desktop enhancement.
    }
    settings.value = await _store.load();
    await _registerCurrent();
  }

  Future<void> updateSettings(DesktopQuickCaptureSettings next) async {
    settings.value = next;
    await _store.save(next);
    await _registerCurrent();
  }

  Future<void> setEnabled(bool enabled) {
    return updateSettings(settings.value.copyWith(enabled: enabled));
  }

  Future<bool> setHotKey(HotKey hotKey) async {
    final normalized = DesktopQuickCaptureSettings.normalizeHotKey(hotKey);
    if (!DesktopQuickCaptureSettings.hasModifier(normalized)) return false;
    await updateSettings(
      settings.value.copyWith(enabled: true, hotKey: normalized),
    );
    return true;
  }

  Future<void> show() async {
    if (!isSupported) return;
    visible.value = true;
    await _focusWindow();
  }

  void hide() {
    visible.value = false;
  }

  Future<void> toggle() {
    return visible.value ? Future.sync(hide) : show();
  }

  Future<void> _registerCurrent() async {
    if (!isSupported) return;
    lastError.value = null;
    final old = _registeredHotKey;
    if (old != null) {
      try {
        await hotKeyManager.unregister(old);
      } catch (_) {
        // Old registrations can disappear after hot restart or platform reset.
      }
      _registeredHotKey = null;
    }

    final current = settings.value;
    if (!current.enabled) return;
    try {
      await hotKeyManager.register(
        current.hotKey,
        keyDownHandler: (_) => show(),
      );
      _registeredHotKey = current.hotKey;
    } catch (e) {
      lastError.value = '快捷键注册失败：$e';
    }
  }

  Future<void> _focusWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // The overlay still works when the app is already focused.
    }
  }
}
