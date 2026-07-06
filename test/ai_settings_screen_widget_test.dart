import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:things3_clone/presentation/screens/ai_settings_screen.dart';

void main() {
  testWidgets('AI 设置页新增草稿并在卡片内校验', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AiSettingsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加'));
    await tester.pumpAndSettle();

    expect(find.text('选择模型'), findsOneWidget);
    expect(find.text('缺 API Key'), findsOneWidget);

    await tester.tap(find.text('DeepSeek Chat'));
    await tester.pumpAndSettle();

    final emptyInput = find.byWidgetPredicate(
      (widget) => widget is EditableText && widget.controller.text.isEmpty,
    );
    await tester.enterText(emptyInput, 'sk-test');
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek Chat'), findsWidgets);
    expect(find.text('缺 API Key'), findsNothing);
  });

  testWidgets('AI 设置页草稿切到网关后校验 Base URL 和模型', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AiSettingsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('网关'));
    await tester.pumpAndSettle();

    expect(find.text('缺 Base URL'), findsOneWidget);
    expect(find.text('缺模型'), findsOneWidget);
  });
}
