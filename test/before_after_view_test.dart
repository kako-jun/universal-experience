import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

/// BeforeAfterView の before/after 生成ロジックと描画カバレッジのテスト（#17）。
///
/// 静的ヘルパ（generateSampleImage / renderAfter / canRender）を直接検証する。
/// protanopia は ShaderFilter 経由で実描画でき、他フィルタは未描画
/// （null = プレースホルダ表示）であることを確認する。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('canRender 描画カバレッジ', () {
    test('protanopia / protanomaly / none は描画可能', () {
      expect(BeforeAfterView.canRender(ColorVisionType.none), isTrue);
      expect(BeforeAfterView.canRender(ColorVisionType.protanopia), isTrue);
      expect(BeforeAfterView.canRender(ColorVisionType.protanomaly), isTrue);
    });

    test('未実装フィルタは描画不可（プレースホルダ）', () {
      expect(BeforeAfterView.canRender(ColorVisionType.deuteranopia), isFalse);
      expect(BeforeAfterView.canRender(ColorVisionType.tritanopia), isFalse);
      expect(BeforeAfterView.canRender(ColorVisionType.achromatopsia), isFalse);
      expect(BeforeAfterView.canRender(ColorVisionType.deuteranomaly), isFalse);
      expect(BeforeAfterView.canRender(ColorVisionType.tritanomaly), isFalse);
    });
  });

  group('generateSampleImage', () {
    test('指定サイズの正方形画像を生成し PNG 化できる', () async {
      final img = await BeforeAfterView.generateSampleImage(64);
      expect(img.width, 64);
      expect(img.height, 64);
      final png = await encodeImagePng(img);
      expect(png, isNotNull);
      expect(png!.isNotEmpty, isTrue);
      img.dispose();
    });
  });

  group('renderAfter', () {
    late ui.Image src;

    setUp(() async {
      src = await BeforeAfterView.generateSampleImage(64);
    });

    tearDown(() {
      src.dispose();
    });

    test('none は元画像をそのまま返す', () async {
      final out = await BeforeAfterView.renderAfter(
        src,
        ColorVisionType.none,
        1.0,
      );
      expect(identical(out, src), isTrue);
    });

    test('protanopia は GPU 実描画で after 画像を生成する', () async {
      final out = await BeforeAfterView.renderAfter(
        src,
        ColorVisionType.protanopia,
        1.0,
      );
      expect(out, isNotNull);
      expect(out!.width, 64);
      expect(out.height, 64);

      // after が原画と異なる（実際にフィルタが効いている）ことを確認。
      final beforePng = await encodeImagePng(src);
      final afterPng = await encodeImagePng(out);
      expect(beforePng, isNotNull);
      expect(afterPng, isNotNull);
      expect(afterPng, isNot(equals(beforePng)));
      out.dispose();
    });

    test('protanomaly も protanopia 経路で描画できる', () async {
      final out = await BeforeAfterView.renderAfter(
        src,
        ColorVisionType.protanomaly,
        0.6,
      );
      expect(out, isNotNull);
      out!.dispose();
    });

    test('未実装フィルタは null（プレースホルダ）を返す', () async {
      for (final type in [
        ColorVisionType.deuteranopia,
        ColorVisionType.tritanopia,
        ColorVisionType.achromatopsia,
        ColorVisionType.deuteranomaly,
        ColorVisionType.tritanomaly,
      ]) {
        final out = await BeforeAfterView.renderAfter(src, type, 1.0);
        expect(out, isNull, reason: '$type');
      }
    });
  });

  group('BeforeAfterView ウィジェット', () {
    testWidgets('protanopia で原画ラベルとフィルタ名ラベルの両ペインを出す',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BeforeAfterView(
              filterType: ColorVisionType.protanopia,
              intensity: 1.0,
              sampleSize: 32,
            ),
          ),
        ),
      );
      // 画像生成 + GPU 描画の Future を解決させる。
      await tester.pumpAndSettle();

      expect(find.text('Original'), findsOneWidget);
      expect(find.text(ColorVisionType.protanopia.displayName), findsOneWidget);
    });

    testWidgets('未実装フィルタでは coming soon プレースホルダを出す',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BeforeAfterView(
              filterType: ColorVisionType.deuteranopia,
              intensity: 1.0,
              sampleSize: 32,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rendering coming soon'), findsOneWidget);
    });
  });
}
