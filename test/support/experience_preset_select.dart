// 体験プリセットのドロップダウン（`ExperiencePresetPicker`、#199）を操作するテスト用ヘルパ。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

/// 体験プリセットのドロップダウン（閉じているときのボタン）。
Finder experiencePresetDropdown() => find.descendant(
      of: find.byKey(experiencePresetDropdownKey),
      matching: find.byWidgetPredicate((w) => w is DropdownButton<String>),
    );

/// ドロップダウンを開く（メニューの項目は [experienceCardKey] で見つかる）。
///
/// `pumpAndSettle` は使わない（プレビューの「準備中」の表示など、終わらないアニメーションが
/// 画面にあると返ってこない）。メニューの開閉のアニメーションぶんだけ時計を進める。
Future<void> openExperiencePresetMenu(WidgetTester tester) async {
  await tester.ensureVisible(experiencePresetDropdown());
  await tester.pump();
  await tester.tap(experiencePresetDropdown());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// ドロップダウンを開いて、体験プリセット [experienceId] を選ぶ。
Future<void> selectExperiencePreset(
  WidgetTester tester,
  String experienceId,
) async {
  await openExperiencePresetMenu(tester);
  await tester.tap(find.byKey(experienceCardKey(experienceId)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// 閉じているドロップダウンに出ている文字列（選択中のプリセット名、または「プリセットなし」）。
Finder experiencePresetDropdownText(String text) => find.descendant(
      of: experiencePresetDropdown(),
      matching: find.text(text),
    );
