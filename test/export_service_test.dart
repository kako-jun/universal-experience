import 'dart:io';
import 'dart:typed_data';
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

  group('compactTime', () {
    test('HHMMSS（24 時間・ゼロ埋め・コロン無し）で整形する', () {
      expect(compactTime(DateTime(2026, 6, 23, 14, 5, 9)), '140509');
      expect(compactTime(DateTime(2026, 6, 23, 0, 0, 0)), '000000');
      expect(compactTime(DateTime(2026, 6, 23, 23, 59, 59)), '235959');
    });
  });

  group('exportFilename の時刻 (#64)', () {
    test('time を渡すと日付の後ろに _ 区切りで付く', () {
      expect(
        exportFilename(
          symptomId: 'protanopia',
          strengthPercent: 100,
          isoDate: '2026-06-23',
          time: '140509',
        ),
        'ue-protanopia-100pct-2026-06-23_140509.png',
      );
    });

    test('同じ日でも time が違えば別名になる（同日 2 回目で同名にならない）', () {
      String at(DateTime dt) => exportFilename(
            symptomId: 'protanopia',
            strengthPercent: 100,
            isoDate: isoDate(dt),
            time: compactTime(dt),
          );
      expect(
        at(DateTime(2026, 6, 23, 14, 5, 9)),
        isNot(at(DateTime(2026, 6, 23, 14, 5, 10))),
      );
    });

    test('時刻入りでもファイル名に使えない文字（: / \\ など）を含まない', () {
      final name = exportFilename(
        symptomId: 'protanopia',
        strengthPercent: 100,
        isoDate: isoDate(DateTime(2026, 6, 23)),
        time: compactTime(DateTime(2026, 6, 23, 14, 5, 9)),
      );
      for (final ch in <String>['/', '\\', ':', '*', '?']) {
        expect(name.contains(ch), isFalse, reason: 'must not contain "$ch"');
      }
    });
  });

  group('numberedFilename (#64)', () {
    test('1 回目は元の名前のまま', () {
      expect(numberedFilename('a.png', 1), 'a.png');
    });

    test('2 回目以降は拡張子の前に -N を挟む', () {
      expect(numberedFilename('a.png', 2), 'a-2.png');
      expect(numberedFilename('a.png', 10), 'a-10.png');
    });

    test('名前に複数の . があっても最後の拡張子の前に挟む', () {
      expect(numberedFilename('ue-x-100pct-2026-06-23_140509.png', 3),
          'ue-x-100pct-2026-06-23_140509-3.png');
      expect(numberedFilename('a.b.png', 2), 'a.b-2.png');
    });

    test('拡張子が無い名前は末尾に付ける', () {
      expect(numberedFilename('noext', 2), 'noext-2');
    });
  });

  group('writeBytesWithoutOverwrite (#64)', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ue_export_test_');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Uint8List bytes(int v) => Uint8List.fromList([v, v, v]);
    String p(String name) => '${dir.path}${Platform.pathSeparator}$name';

    test('空いている名前ならその名前で書き、フルパスを返す', () async {
      final path = await writeBytesWithoutOverwrite(dir, bytes(1), 'a.png');
      expect(path, p('a.png'));
      expect(File(path).readAsBytesSync(), bytes(1));
    });

    test('同名が既にあれば上書きせず -2, -3 で保存し、元の内容が残る', () async {
      final first = await writeBytesWithoutOverwrite(dir, bytes(1), 'a.png');
      final second = await writeBytesWithoutOverwrite(dir, bytes(2), 'a.png');
      final third = await writeBytesWithoutOverwrite(dir, bytes(3), 'a.png');

      expect(first, p('a.png'));
      expect(second, p('a-2.png'));
      expect(third, p('a-3.png'));
      expect(File(first).readAsBytesSync(), bytes(1));
      expect(File(second).readAsBytesSync(), bytes(2));
      expect(File(third).readAsBytesSync(), bytes(3));
    });

    test('連番の途中が空いていればそこを使う（a.png と a-3.png があれば a-2.png）',
        () async {
      File(p('a.png')).writeAsBytesSync(bytes(1));
      File(p('a-3.png')).writeAsBytesSync(bytes(3));
      final path = await writeBytesWithoutOverwrite(dir, bytes(2), 'a.png');
      expect(path, p('a-2.png'));
      expect(File(p('a-3.png')).readAsBytesSync(), bytes(3));
    });

    test('同時に同名で書いても互いを上書きせず全部残る', () async {
      final paths = await Future.wait([
        for (var i = 1; i <= 5; i++)
          writeBytesWithoutOverwrite(dir, bytes(i), 'a.png'),
      ]);
      expect(paths.toSet().length, 5, reason: '全て別のパスになる');
      final contents = {
        for (final path in paths) File(path).readAsBytesSync().first,
      };
      expect(contents, {1, 2, 3, 4, 5}, reason: '5 つとも内容が残っている');
    });

    test('存在しないディレクトリへの書き込みは連番で握りつぶさず例外にする', () async {
      final missing = Directory(p('no_such_dir'));
      expect(
        () => writeBytesWithoutOverwrite(missing, bytes(1), 'a.png'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('revealCommandFor (#64)', () {
    test('macOS は open -R でファイルを選択状態にする', () {
      final cmd = revealCommandFor('macos', '/Users/u/Downloads/a.png');
      expect(cmd!.executable, 'open');
      expect(cmd.arguments, ['-R', '/Users/u/Downloads/a.png']);
    });

    test('Windows は explorer /select, にパスを続ける', () {
      final cmd = revealCommandFor('windows', r'C:\Users\u\Downloads\a.png');
      expect(cmd!.executable, 'explorer');
      expect(cmd.arguments, [r'/select,C:\Users\u\Downloads\a.png']);
    });

    test('Linux は含むフォルダを xdg-open で開く', () {
      final cmd = revealCommandFor('linux', '/home/u/Downloads/a.png');
      expect(cmd!.executable, 'xdg-open');
      expect(cmd.arguments, ['/home/u/Downloads']);
    });

    test('未対応 OS は null', () {
      expect(revealCommandFor('android', '/x/a.png'), isNull);
    });
  });

  group('macOS entitlements (#64)', () {
    // サンドボックス下で getDownloadsDirectory() が実 ~/Downloads を返す条件。
    // どちらかから落ちると、書き出し先がコンテナ内（ユーザーに見えない場所）に戻る。
    for (final name in ['DebugProfile', 'Release']) {
      test('$name.entitlements に Downloads の読み書き entitlement がある', () {
        final plist = File('macos/Runner/$name.entitlements').readAsStringSync();
        expect(
          RegExp(
            r'<key>com\.apple\.security\.files\.downloads\.read-write</key>\s*<true/>',
          ).hasMatch(plist),
          isTrue,
        );
      });
    }
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

    test(
        'escalationGroups（段ごとの見出し + 条件文）ぶん、無しより高くなる '
        '（#76 レビュー M1・再レビュー S-a）', () async {
      final base = await makeBase(80, 60);
      const withoutGroups = ExportCaption(
        symptomLabel: 'BPPV Rotation',
        strengthLabel: 'Strength: 60%',
        isoDate: '2026-06-23',
      );
      const withGroups = ExportCaption(
        symptomLabel: 'BPPV Rotation',
        strengthLabel: 'Strength: 60%',
        isoDate: '2026-06-23',
        escalationGroups: [
          ExportEscalationGroup(
            header: 'See a doctor right away if:',
            lines: ['a sudden drop in hearing'],
          ),
          ExportEscalationGroup(
            header: 'Consider seeing a doctor if:',
            lines: ['recurrent or severe episodes'],
          ),
        ],
        disclaimer: 'Not a diagnosis; not medically reviewed. '
            'Source: sensus Medical notes',
      );
      final composedWithout = await composeExportImage(base, withoutGroups);
      final composedWith = await composeExportImage(base, withGroups);
      final pngWith = await encodeImagePng(composedWith);
      addTearDown(() {
        base.dispose();
        composedWithout.dispose();
        composedWith.dispose();
      });

      // 2 段（見出し 2 行 + 条件文 2 行）+ disclaimer 1 行ぶん、確実に高くなる。
      expect(composedWith.height, greaterThan(composedWithout.height));
      expect(pngWith, isNotNull);
      expect(pngWith!.isNotEmpty, isTrue);
    });
  });
}
