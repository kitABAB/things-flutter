import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';

/// 给任务挑选 / 新建标签的面板。勾选即时生效（attach/detach）。
class TagPickerSheet {
  static Future<void> show(BuildContext context, String itemId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TagPickerBody(itemId: itemId),
    );
  }
}

class _TagPickerBody extends ConsumerStatefulWidget {
  final String itemId;
  const _TagPickerBody({required this.itemId});

  @override
  ConsumerState<_TagPickerBody> createState() => _TagPickerBodyState();
}

class _TagPickerBodyState extends ConsumerState<_TagPickerBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createAndAttach() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(itemRepositoryProvider);
    final id = await repo.createTag(title);
    await repo.attachTag(widget.itemId, id);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final allTags = ref.watch(tagsProvider).value ?? [];
    final attached = ref.watch(itemTagsProvider(widget.itemId)).value ?? [];
    final attachedIds = attached.map((t) => t.id).toSet();
    final repo = ref.read(itemRepositoryProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('标签', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            if (allTags.isNotEmpty)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in allTags)
                      CheckboxListTile(
                        value: attachedIds.contains(tag.id),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppTheme.primaryBlue,
                        title: Text('# ${tag.title}'),
                        onChanged: (v) {
                          if (v == true) {
                            repo.attachTag(widget.itemId, tag.id);
                          } else {
                            repo.detachTag(widget.itemId, tag.id);
                          }
                        },
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: '新建标签',
                        prefixText: '# ',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _createAndAttach(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: AppTheme.primaryBlue),
                    onPressed: _createAndAttach,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
