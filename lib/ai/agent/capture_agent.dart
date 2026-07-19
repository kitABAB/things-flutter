import 'dart:convert';

import '../../domain/models/item.dart';
import '../capture/capture_draft.dart';
import '../capture/capture_draft_codec.dart';
import '../capture/capture_parser.dart' show CaptureContext;
import '../core/llm_client.dart';
import '../core/llm_message.dart';

part 'capture_agent_policy.dart';
part 'capture_agent_prompt.dart';

class CaptureAgentMessage {
  final String role;
  final String content;

  const CaptureAgentMessage(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class CaptureAgentResult {
  final CaptureDraft draft;
  final String message;
  final List<String> suggestions;
  final bool needsUser;

  const CaptureAgentResult({
    required this.draft,
    required this.message,
    this.suggestions = const [],
    this.needsUser = false,
  });
}

class CaptureAgent {
  final LlmClient client;

  const CaptureAgent(this.client);

  bool get isAvailable => client.isConfigured;

  Future<CaptureAgentResult> run({
    required String latest,
    required CaptureContext context,
    CaptureDraft? currentDraft,
    List<CaptureAgentMessage> history = const [],
  }) async {
    final raw = latest.trim();
    final updatingExisting = currentDraft?.items.isNotEmpty == true;
    if (raw.isEmpty) {
      return CaptureAgentResult(
        draft: currentDraft ?? const CaptureDraft(source: '', items: []),
        message: '',
      );
    }

    final workspace = _AgentWorkspace.fromDraft(currentDraft);
    final messages = <LlmMessage>[
      LlmMessage.system(_captureAgentSystemPrompt(context)),
      LlmMessage.user(
        jsonEncode({
          'latest_user_input': raw,
          'conversation': history.map((m) => m.toJson()).toList(),
          'current_workspace': workspace.toJson(),
        }),
      ),
    ];

    _AgentFinal? finalState;

    for (var turn = 0; turn < 3; turn += 1) {
      final reply = await client.complete(
        messages,
        jsonMode: true,
        temperature: 0.1,
      );
      final parsed = _AgentReply.tryParse(reply);

      if (parsed == null) {
        final fallback = CaptureDraftCodec.decodeReply(reply, raw);
        workspace.replace(fallback.items);
        finalState = _AgentFinal(message: _defaultReadyMessage(workspace));
        break;
      }

      if (parsed.legacyDraft != null) {
        workspace.replace(parsed.legacyDraft!.items);
      }

      final results = <Map<String, dynamic>>[];
      for (final call in parsed.toolCalls) {
        results.add(workspace.execute(call));
      }

      finalState = parsed.finalState ?? finalState;
      if (workspace.pendingQuestion != null) {
        finalState = workspace.pendingQuestion;
      }

      final hasTerminalTool = parsed.toolCalls.any(
        (call) => call.name == 'ask_user' || call.name == 'finish',
      );
      final shouldContinue =
          parsed.toolCalls.isNotEmpty &&
          parsed.finalState == null &&
          !hasTerminalTool &&
          turn < 2;
      if (!shouldContinue) break;

      messages
        ..add(LlmMessage.assistant(reply))
        ..add(
          LlmMessage.user(
            jsonEncode({
              'tool_results': results,
              'current_workspace': workspace.toJson(),
              'instruction': '根据内置动作执行结果继续。若已经完成，调用 finish。',
            }),
          ),
        );
    }

    if (workspace.pendingQuestion == null) {
      final policyQuestion = _AgentPolicy(
        context,
      ).apply(raw, workspace, hasCurrentDraft: updatingExisting);
      if (policyQuestion != null) {
        finalState = policyQuestion;
      }
    }

    final resolved =
        finalState ?? _AgentFinal(message: _defaultReadyMessage(workspace));
    return CaptureAgentResult(
      draft: workspace.toDraft(source: raw),
      message: resolved.needsUser
          ? (resolved.message.isEmpty ? '我需要再确认一下。' : resolved.message)
          : _defaultReadyMessage(workspace, updating: updatingExisting),
      suggestions: resolved.suggestions,
      needsUser: resolved.needsUser,
    );
  }

  static String _defaultReadyMessage(
    _AgentWorkspace workspace, {
    bool updating = false,
  }) {
    final count = workspace.createCount;
    if (count <= 0) return '我需要再确认一下。';
    if (updating) return '已更新待创建项。';
    return '已整理出 $count 项。';
  }
}

class _AgentReply {
  final List<_ToolCall> toolCalls;
  final _AgentFinal? finalState;
  final CaptureDraft? legacyDraft;

  const _AgentReply({
    required this.toolCalls,
    this.finalState,
    this.legacyDraft,
  });

  static _AgentReply? tryParse(String reply) {
    final jsonStr = CaptureDraftCodec.extractJson(reply);
    if (jsonStr == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);

    final rawCalls = map['tool_calls'];
    final calls = <_ToolCall>[];
    if (rawCalls is List) {
      for (final rawCall in rawCalls) {
        if (rawCall is! Map) continue;
        final name = rawCall['name'];
        final args = rawCall['arguments'];
        if (name is String) {
          calls.add(
            _ToolCall(
              name,
              args is Map ? Map<String, dynamic>.from(args) : const {},
            ),
          );
        }
      }
    }

    _AgentFinal? finalState;
    final rawFinal = map['final'];
    if (rawFinal is Map) {
      finalState = _AgentFinal.fromJson(Map<String, dynamic>.from(rawFinal));
    }

    CaptureDraft? legacyDraft;
    final rawItems = map['items'];
    if (rawItems is List) {
      legacyDraft = rawItems.isEmpty
          ? const CaptureDraft(source: '', items: [])
          : CaptureDraftCodec.fromJson(map, source: '');
    }

    if (calls.isEmpty && finalState == null && legacyDraft == null) return null;
    return _AgentReply(
      toolCalls: calls,
      finalState: finalState,
      legacyDraft: legacyDraft,
    );
  }
}

class _ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const _ToolCall(this.name, this.arguments);
}

class _AgentFinal {
  final String message;
  final List<String> suggestions;
  final bool needsUser;

  const _AgentFinal({
    required this.message,
    this.suggestions = const [],
    this.needsUser = false,
  });

  factory _AgentFinal.fromJson(Map<String, dynamic> json) {
    return _AgentFinal(
      message: (json['message'] as String?)?.trim() ?? '',
      suggestions: _readStrings(json['suggestions']),
      needsUser: json['needs_user'] is bool
          ? json['needs_user'] as bool
          : false,
    );
  }

  static List<String> _readStrings(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }
}

class _AgentWorkspace {
  final List<DraftItem> _items;
  _AgentFinal? pendingQuestion;

  _AgentWorkspace(this._items);

  factory _AgentWorkspace.fromDraft(CaptureDraft? draft) {
    return _AgentWorkspace([
      for (final item in draft?.items ?? const <DraftItem>[]) _copyItem(item),
    ]);
  }

  int get createCount {
    var total = 0;
    for (final item in _items) {
      if (item.title.trim().isEmpty) continue;
      total += 1;
      if (item.type == ItemType.project) {
        total += item.children
            .where((child) => child.include && child.title.trim().isNotEmpty)
            .length;
      }
    }
    return total;
  }

  void replace(List<DraftItem> items) {
    _items
      ..clear()
      ..addAll(items.map(_copyItem));
  }

  CaptureDraft toDraft({required String source}) {
    return CaptureDraft(
      source: source,
      items: [for (final item in _items) _copyItem(item)],
    );
  }

  Map<String, dynamic> toJson() {
    return {'items': _items.map(CaptureDraftCodec.itemToJson).toList()};
  }

  Map<String, dynamic> execute(_ToolCall call) {
    switch (call.name) {
      case 'replace_drafts':
        replace(_decodeItems(call.arguments['items']));
        return _ok(call.name);
      case 'append_drafts':
        _items.addAll(_decodeItems(call.arguments['items']).map(_copyItem));
        return _ok(call.name);
      case 'update_draft':
        return _update(call.arguments);
      case 'remove_draft':
        return _remove(call.arguments);
      case 'reorder_draft':
        return _reorder(call.arguments);
      case 'ask_user':
        pendingQuestion = _AgentFinal(
          message: (call.arguments['message'] as String?)?.trim() ?? '',
          suggestions: _AgentFinal._readStrings(call.arguments['suggestions']),
          needsUser: true,
        );
        return _ok(call.name);
      case 'finish':
        pendingQuestion = _AgentFinal.fromJson(call.arguments);
        return _ok(call.name);
      default:
        return {'tool': call.name, 'ok': false, 'error': 'unknown_tool'};
    }
  }

  Map<String, dynamic> _update(Map<String, dynamic> args) {
    final index = _readIndex(args['index']);
    if (index == null || index >= _items.length) {
      return {
        'tool': 'update_draft',
        'ok': false,
        'error': 'index_out_of_range',
      };
    }
    final patch = args['patch'];
    if (patch is! Map) {
      return {'tool': 'update_draft', 'ok': false, 'error': 'missing_patch'};
    }
    _applyPatch(_items[index], patch);
    return _ok('update_draft');
  }

  Map<String, dynamic> _remove(Map<String, dynamic> args) {
    final index = _readIndex(args['index']);
    if (index == null || index >= _items.length) {
      return {
        'tool': 'remove_draft',
        'ok': false,
        'error': 'index_out_of_range',
      };
    }
    _items.removeAt(index);
    return _ok('remove_draft');
  }

  Map<String, dynamic> _reorder(Map<String, dynamic> args) {
    final from = _readIndex(args['from_index']);
    final to = _readIndex(args['to_index']);
    if (from == null || to == null || from >= _items.length) {
      return {
        'tool': 'reorder_draft',
        'ok': false,
        'error': 'index_out_of_range',
      };
    }
    final item = _items.removeAt(from);
    _items.insert(to.clamp(0, _items.length).toInt(), item);
    return _ok('reorder_draft');
  }

  void _applyPatch(DraftItem item, Map patch) {
    final title = patch['title'];
    if (title is String && title.trim().isNotEmpty) item.title = title.trim();

    final type = patch['type'];
    if (type == 'project') item.type = ItemType.project;
    if (type == 'task') item.type = ItemType.task;

    if (patch.containsKey('when')) {
      item.when = CaptureDraftCodec.decodeWhen(patch['when']);
    }
    if (patch.containsKey('deadline')) {
      item.deadline = CaptureDraftCodec.decodeDate(patch['deadline']);
    }
    if (patch.containsKey('list')) {
      final list = patch['list'];
      if (list == null) {
        item.listName = null;
        item.listKind = null;
      } else if (list is String && list.trim().isNotEmpty) {
        final decoded = CaptureDraftCodec.decodeItem({
          'title': '_',
          'list': list,
        });
        item.listName = decoded?.listName;
        item.listKind = decoded?.listKind;
      } else if (list is Map) {
        final decoded = CaptureDraftCodec.decodeItem({
          'title': '_',
          'list': list,
        });
        item.listName = decoded?.listName;
        item.listKind = decoded?.listKind;
      }
    }
    final tags = patch['tags'];
    if (tags is List) {
      item.tagNames = [
        for (final tag in tags)
          if (tag is String && tag.trim().isNotEmpty) tag.trim(),
      ];
    }
    final children = patch['children'];
    if (children is List) {
      item.children = _decodeChildren(children);
    }
  }

  static List<DraftItem> _decodeItems(Object? raw) {
    if (raw is! List) return const [];
    final items = <DraftItem>[];
    for (final rawItem in raw) {
      if (rawItem is! Map) continue;
      final item = CaptureDraftCodec.decodeItem(rawItem);
      if (item != null) items.add(item);
    }
    return items;
  }

  static List<DraftChild> _decodeChildren(List raw) {
    final wrapper = CaptureDraftCodec.decodeItem({
      'title': '_',
      'children': raw,
    });
    return wrapper?.children ?? const [];
  }

  static int? _readIndex(Object? raw) {
    final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (value == null || value < 1) return null;
    return value - 1;
  }

  static Map<String, dynamic> _ok(String tool) => {'tool': tool, 'ok': true};

  static DraftItem _copyItem(DraftItem item) {
    return DraftItem(
      title: item.title,
      type: item.type,
      when: item.when,
      deadline: item.deadline,
      tagNames: [...item.tagNames],
      listName: item.listName,
      listKind: item.listKind,
      children: [
        for (final child in item.children)
          DraftChild(
            title: child.title,
            when: child.when,
            deadline: child.deadline,
            include: child.include,
          ),
      ],
    );
  }
}
