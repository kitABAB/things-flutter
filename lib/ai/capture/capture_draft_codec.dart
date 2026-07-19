import 'dart:convert';

import '../../domain/models/item.dart';
import 'capture_draft.dart';

class CaptureDraftCodec {
  const CaptureDraftCodec._();

  static CaptureDraft decodeReply(String reply, String source) {
    final jsonStr = extractJson(reply);
    if (jsonStr == null) {
      return CaptureDraft(
        source: source,
        items: [DraftItem(title: source)],
      );
    }

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return fromJson(decoded, source: source);
      }
      if (decoded is Map) {
        return fromJson(Map<String, dynamic>.from(decoded), source: source);
      }
    } catch (_) {
      // Fall through to the plain-text fallback below.
    }
    return CaptureDraft(
      source: source,
      items: [DraftItem(title: source)],
    );
  }

  static CaptureDraft fromJson(
    Map<String, dynamic> map, {
    required String source,
  }) {
    final rawItems = map['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      return CaptureDraft(
        source: source,
        items: [DraftItem(title: source)],
      );
    }

    final items = <DraftItem>[];
    for (final raw in rawItems) {
      if (raw is Map) {
        final item = decodeItem(raw);
        if (item != null) items.add(item);
      }
    }
    if (items.isEmpty) items.add(DraftItem(title: source));
    return CaptureDraft(source: source, items: items);
  }

  static Map<String, dynamic> toJson(CaptureDraft draft) {
    return {
      'source': draft.source,
      'items': draft.items.map(itemToJson).toList(),
    };
  }

  static DraftItem? decodeItem(Map raw) {
    final title = (raw['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    final type = raw['type'] == 'project' ? ItemType.project : ItemType.task;

    final tags = <String>[];
    final rawTags = raw['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        if (tag is String && tag.trim().isNotEmpty) tags.add(tag.trim());
      }
    }

    String? listName;
    DraftListKind? listKind;
    final list = raw['list'];
    if (list is String && list.trim().isNotEmpty && list != 'null') {
      final trimmed = list.trim();
      final lower = trimmed.toLowerCase();
      if (lower == 'inbox') {
        listName = DraftItem.inboxToken;
      } else if (lower.startsWith('new_area:')) {
        listName = trimmed.substring('new_area:'.length).trim();
        listKind = DraftListKind.newArea;
      } else if (lower.startsWith('new_project:')) {
        listName = trimmed.substring('new_project:'.length).trim();
        listKind = DraftListKind.newProject;
      } else {
        listName = trimmed;
      }
    } else if (list is Map) {
      final type = (list['type'] as String?)?.trim().toLowerCase();
      final name = (list['name'] as String?)?.trim();
      if (type == 'inbox') {
        listName = DraftItem.inboxToken;
      } else if (name != null && name.isNotEmpty) {
        listName = name;
        if (type == 'new_area') listKind = DraftListKind.newArea;
        if (type == 'new_project') listKind = DraftListKind.newProject;
      }
    }

    final children = <DraftChild>[];
    final rawChildren = raw['children'];
    if (rawChildren is List) {
      for (final child in rawChildren) {
        if (child is String && child.trim().isNotEmpty) {
          children.add(DraftChild(title: child.trim()));
        } else if (child is Map && child['title'] is String) {
          children.add(
            DraftChild(
              title: (child['title'] as String).trim(),
              when: decodeWhen(child['when']),
              deadline: decodeDate(child['deadline']),
              include: child['include'] is bool
                  ? child['include'] as bool
                  : true,
            ),
          );
        }
      }
    }

    return DraftItem(
      title: title,
      type: type,
      when: decodeWhen(raw['when']),
      deadline: decodeDate(raw['deadline']),
      tagNames: tags,
      listName: listName,
      listKind: listKind,
      children: children,
    );
  }

  static Map<String, dynamic> itemToJson(DraftItem item) {
    return {
      'title': item.title,
      'type': item.type == ItemType.project ? 'project' : 'task',
      'when': encodeWhen(item.when),
      'deadline': encodeDate(item.deadline),
      'tags': item.tagNames,
      'list': encodeList(item),
      'children': item.children.map(childToJson).toList(),
    };
  }

  static Object? encodeList(DraftItem item) {
    if (item.listName == null) return null;
    if (item.listName == DraftItem.inboxToken) return 'inbox';
    switch (item.listKind) {
      case DraftListKind.newArea:
        return {'type': 'new_area', 'name': item.listName};
      case DraftListKind.newProject:
        return {'type': 'new_project', 'name': item.listName};
      case null:
        return item.listName;
    }
  }

  static Map<String, dynamic> childToJson(DraftChild child) {
    return {
      'title': child.title,
      'when': encodeWhen(child.when),
      'deadline': encodeDate(child.deadline),
      'include': child.include,
    };
  }

  static DraftWhen decodeWhen(Object? raw) {
    if (raw is! String) return DraftWhen.none;
    switch (raw) {
      case 'today':
        return const DraftWhen(DraftWhenKind.today);
      case 'evening':
        return const DraftWhen(DraftWhenKind.evening);
      case 'someday':
        return const DraftWhen(DraftWhenKind.someday);
      case 'none':
      case '':
        return DraftWhen.none;
      default:
        final date = decodeDate(raw);
        return date == null
            ? DraftWhen.none
            : DraftWhen(DraftWhenKind.date, date: date);
    }
  }

  static String encodeWhen(DraftWhen when) {
    switch (when.kind) {
      case DraftWhenKind.none:
        return 'none';
      case DraftWhenKind.today:
        return 'today';
      case DraftWhenKind.evening:
        return 'evening';
      case DraftWhenKind.someday:
        return 'someday';
      case DraftWhenKind.date:
        return encodeDate(when.date) ?? 'none';
    }
  }

  static DateTime? decodeDate(Object? raw) {
    if (raw is! String || raw.isEmpty || raw == 'null') return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String? encodeDate(DateTime? date) {
    if (date == null) return null;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String? extractJson(String reply) {
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return reply.substring(start, end + 1);
  }
}
