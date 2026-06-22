import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/export_service.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

/// export_service の pure 中核（ISO 日付・ファイル名・メタ焼き込み PNG 合成）の
/// テスト (#43)。I/O（savePng）は path_provider の実プラットフォームを要するため
/// headless では検証せず、Issue の検証手段「PNG バイト非空・メタ一致」を満たす
/// 純粋関数（isoDate / exportFilename / composeExportImage）を直接検証する。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isoDate', () {
    test('YYYY-MM-DD（ゼロ埋め・スラッシュ禁止）で整形する', () {
      expect(isoDate(DateTime(2026, 6, 23)), '2026-06-23');
    });

    test('月日をゼロ埋めする', () {
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('スラッシュを含まない（ISO 固定）', () {
      final s = isoDate(DateTime(2026, 12, 31));
      expect(s.contains('/'), isFalse);
      expect(s, '2026-12-31');
    });
  });

  group('exportFilename', () {
    test('メタ（symptomId・strengthPercent・isoDate）を含み .png 拡張子を持つ', () {
      final name = exportFilename(
        symptomId: 'protanopia',
        strengthPercent: 100,
        isoDate: '2026-06-23',
      );
      expect(name, contains('protanopia'));
      expect(name, contains('100pct'));
      expect(name, contains('2026-06-23'));
      expect(name, endsWith('.png'));
    });

    test('決定論的（同じ入力なら同じ出力）', () {
      String make() => exportFilename(
            symptomId: 'deuteranopia',
            strengthPercent: 60,
            isoDate: '2026-01-05',
          );
      expect(make(), make());
      expect(make(), 'ue-deuteranopia-60pct-2026-01-05.png');
    });

    test('symptomId が none でも妥当なファイル名になる', () {
      final name = exportFilename(
        symptomId: 'none',
        strengthPercent: 0,
        isoDate: '2026-06-23',
      );
      expect(name, 'ue-none-0pct-2026-06-23.png');
    });

    test('ファイル名に使えない文字を含まない', () {
      final name = exportFilename(
        symptomId: 'weird/id:with*bad?chars',
        strengthPercent: 50,
        isoDate: '2026-06-23',
      );
      for (final ch in <String>['/', '\\', ':', '*', '?', '"', '<', '>', '|']) {
        expect(name.contains(ch), isFalse, reason: 'must not contain "$ch"');
      }
      expect(name, endsWith('.png'));
    });
  });

  group('composeExportImage', () {
    /// テスト用の小さなダミー [ui.Image] を生成する。
    Future<ui.Image> makeBase(int w, int h) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = const ui.Color(0xFF3366CC),
      );
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(w, h);
      } finally {
        picture.dispose();
      }
    }

    test('帯ぶん base より高い画像を返し、幅は維持する', () async {
      final base = await makeBase(64, 48);
      const caption = ExportCaption(
        symptomLabel: 'Protanopia',
        strengthLabel: 'Strength: 100%',
        isoDate: '2026-06-23',
      );
      final composed = await composeExportImage(base, caption);
      addTearDown(() {
        base.dispose();
        composed.dispose();
      });

      expect(composed.width, base.width);
      expect(composed.height, greaterThan(base.height));
    });

    test('合成画像を PNG 化すると非空バイトが得られる', () async {
      final base = await makeBase(64, 48);
      const caption = ExportCaption(
        symptomLabel: 'Tritanopia',
        strengthLabel: 'Strength: 60%',
        isoDate: '2026-01-05',
      );
      final composed = await composeExportImage(base, caption);
      final png = await encodeImagePng(composed);
      addTearDown(() {
        base.dispose();
        composed.dispose();
      });

      expect(png, isNotNull);
      expect(png!.isNotEmpty, isTrue);
    });

    test('受診喚起あり（urgencyMessage 非 null）でも合成・PNG 化できる', () async {
      final base = await makeBase(80, 60);
      const caption = ExportCaption(
        symptomLabel: 'Glaucoma',
        strengthLabel: 'Strength: 80%',
        urgencyMessage: 'Sudden changes in vision can need prompt care.',
        isoDate: '2026-06-23',
      );
      final composed = await composeExportImage(base, caption);
      final png = await encodeImagePng(composed);
      addTearDown(() {
        base.dispose();
        composed.dispose();
      });

      // urgency 行ぶん、urgency なしより高くなる（行が増える）。
      expect(composed.height, greaterThan(base.height));
      expect(png, isNotNull);
      expect(png!.isNotEmpty, isTrue);
    });
  });
}
