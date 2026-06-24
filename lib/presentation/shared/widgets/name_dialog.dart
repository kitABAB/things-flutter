import 'package:flutter/material.dart';

/// 通用的「输入名称」对话框，返回输入文本（取消则返回 null）。
class NameDialog {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String hint = '名称',
    String confirm = '创建',
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(confirm),
          ),
        ],
      ),
    );
  }
}
