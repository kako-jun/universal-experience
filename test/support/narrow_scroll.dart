// 縦積み（狭幅）の主画面で、プレビューまでスクロールするテスト用ヘルパ（#198）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';

/// 縦積みでは、プレビューのカードは一覧（選択）の下にあり、最初のビューポートには入らない
/// （#198。上から 選択 → プレビュー → 調整）。プレビューのカードを、上に 16dp（区画の間の余白）を
/// 残して本体領域の上端へスクロールする。「プレビューまでスクロールしたとき、画像から選択欄
/// （`ImageSourcePicker`）までが 1 画面に収まる」（#130）を測る前に呼ぶ。
Future<void> scrollPreviewIntoView(WidgetTester tester) async {
  final card = find
      .ancestor(
        of: find.byType(ImageSourcePicker),
        matching: find.byType(Card),
      )
      .first;
  final element = tester.element(card);
  await Scrollable.ensureVisible(element, alignment: 0);
  final position = Scrollable.of(element).position;
  position.jumpTo(
    (position.pixels - 16).clamp(0.0, position.maxScrollExtent),
  );
  await tester.pump();
}
