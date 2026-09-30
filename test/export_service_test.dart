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

    test('連番の途中が空いていればそこを使う（a.png と a-3.png があれば a-2.png）', () async {
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

    test('作成後の書き込みに失敗したら作りかけのファイルを残さず、元の例外を投げる', () async {
      await expectLater(
        writeBytesWithoutOverwrite(
          dir,
          bytes(1),
          'a.png',
          writeFile: (file, b) async =>
              throw const FileSystemException('disk full'),
        ),
        throwsA(isA<FileSystemException>()
            .having((e) => e.message, 'message', 'disk full')),
      );
      expect(dir.listSync(), isEmpty, reason: '0 バイトのファイルが残っていない');

      // 失敗のあとに同名で書き直せる（失敗した名前を占有し続けない）。
      final path = await writeBytesWithoutOverwrite(dir, bytes(2), 'a.png');
      expect(path, p('a.png'));
    });

    test('書き込み失敗で消すのは自分が作ったファイルだけ（既存の同名は無傷）', () async {
      File(p('a.png')).writeAsBytesSync(bytes(1));
      await expectLater(
        writeBytesWithoutOverwrite(
          dir,
          bytes(2),
          'a.png',
          writeFile: (file, b) async => throw const FileSystemException('x'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(p('a.png')).readAsBytesSync(), bytes(1));
      expect(File(p('a-2.png')).existsSync(), isFalse);
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
    test('macOS は /usr/bin/open -R でファイルを選択状態にし、終了コードで成否を見る', () {
      final cmd = revealCommandFor('macos', '/Users/u/Downloads/a.png');
      expect(cmd!.executable, '/usr/bin/open');
      expect(cmd.arguments, ['-R', '/Users/u/Downloads/a.png']);
      expect(cmd.mode, RevealMode.runAndCheckExit);
    });

    test('Windows は explorer /select, にパスを続け、終了コードは見ない', () {
      final cmd = revealCommandFor('windows', r'C:\Users\u\Downloads\a.png');
      expect(cmd!.executable, 'explorer');
      expect(cmd.arguments, [r'/select,C:\Users\u\Downloads\a.png']);
      expect(cmd.mode, RevealMode.runIgnoreExit);
    });

    test('Linux は含むフォルダを xdg-open で開き、切り離して起動する', () {
      final cmd = revealCommandFor('linux', '/home/u/Downloads/a.png');
      expect(cmd!.executable, 'xdg-open');
      expect(cmd.arguments, ['/home/u/Downloads']);
      expect(cmd.mode, RevealMode.startDetached);
    });

    test('未対応 OS は null', () {
      expect(revealCommandFor('android', '/x/a.png'), isNull);
    });
  });

  group('revealInFolder (#64)', () {
    Future<bool> reveal(String platform, RevealRunner runner) =>
        revealInFolder('/x/a.png', platform: platform, runner: runner);

    test('macOS: 終了コード 0 は成功、非 0 は失敗', () async {
      expect(await reveal('macos', (_) async => 0), isTrue);
      expect(await reveal('macos', (_) async => 1), isFalse);
    });

    test('macOS: 起動できなければ（ProcessException）失敗', () async {
      expect(
        await reveal(
            'macos', (_) async => throw const ProcessException('open', [])),
        isFalse,
      );
    });

    test('Windows: explorer は終了コード 1 でも成功として扱う', () async {
      expect(await reveal('windows', (_) async => 1), isTrue);
      expect(await reveal('windows', (_) async => 0), isTrue);
    });

    test('Windows: 起動できなければ失敗', () async {
      expect(
        await reveal('windows',
            (_) async => throw const ProcessException('explorer', [])),
        isFalse,
      );
    });

    test('Linux: 切り離し起動（終了コード null）は起動できれば成功', () async {
      expect(await reveal('linux', (_) async => null), isTrue);
      expect(
        await reveal(
            'linux', (_) async => throw const ProcessException('xdg-open', [])),
        isFalse,
      );
    });

    test('runner には revealCommandFor と同じコマンドが渡る', () async {
      RevealCommand? seen;
      await reveal('macos', (cmd) async {
        seen = cmd;
        return 0;
      });
      final expected = revealCommandFor('macos', '/x/a.png')!;
      expect(seen!.executable, expected.executable);
      expect(seen!.arguments, expected.arguments);
      expect(seen!.mode, expected.mode);
    });

    test('未対応 OS は runner を呼ばず失敗', () async {
      var called = false;
      final ok = await reveal('android', (_) async {
        called = true;
        return 0;
      });
      expect(ok, isFalse);
      expect(called, isFalse);
    });
  });

  group('savePngInto: シンボリックリンクを実パスに正規化する (#64)', () {
    late Directory root;
    late Directory realDir;
    late String linkPath;
    // Windows の CI ではシンボリックリンクを作れない環境がある。
    final skipSymlink =
        Platform.isWindows ? 'Windows では symlink を作れない場合がある' : null;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('ue_export_link_');
      // 一時ディレクトリ自体が symlink 配下のことがある（macOS の /var → /private/var）
      // ので、期待値は実パスに解決したルートから作る。
      final resolvedRoot = Directory(await root.resolveSymbolicLinks());
      realDir =
          await Directory('${resolvedRoot.path}${Platform.pathSeparator}real')
              .create();
      linkPath =
          '${resolvedRoot.path}${Platform.pathSeparator}container-downloads';
      if (skipSymlink == null) await Link(linkPath).create(realDir.path);
    });
    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('リンク経由で与えても、返るパスはリンク先の実パス（リンク側の名前ではない）', () async {
      final path = await savePngInto(
        Directory(linkPath),
        Uint8List.fromList([1, 2, 3]),
        'a.png',
      );
      expect(path, '${realDir.path}${Platform.pathSeparator}a.png');
      expect(path, isNot(contains('container-downloads')));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    }, skip: skipSymlink);

    test('リンク越しでも同名は上書きせず連番、返るパスは実パス', () async {
      final first = await savePngInto(
          Directory(linkPath), Uint8List.fromList([1]), 'a.png');
      final second = await savePngInto(
          Directory(linkPath), Uint8List.fromList([2]), 'a.png');
      expect(first, '${realDir.path}${Platform.pathSeparator}a.png');
      expect(second, '${realDir.path}${Platform.pathSeparator}a-2.png');
      expect(File(first).readAsBytesSync(), [1]);
    }, skip: skipSymlink);

    test('リンクでないディレクトリでもそのまま実パスを返す', () async {
      final path = await savePngInto(realDir, Uint8List.fromList([9]), 'b.png');
      expect(path, '${realDir.path}${Platform.pathSeparator}b.png');
    });

    test('resolveDirectoryOrSelf: 解決できない（存在しない）ディレクトリは元のまま', () async {
      final missing =
          Directory('${realDir.path}${Platform.pathSeparator}no_such_dir');
      expect((await resolveDirectoryOrSelf(missing)).path, missing.path);
    });

    test('resolvePathOrSelf: 解決できないパスは元のまま', () async {
      final missing = '${realDir.path}${Platform.pathSeparator}no_such.png';
      expect(await resolvePathOrSelf(missing), missing);
    });

    test('リンク切れのディレクトリは、解決できず元のパスへ書こうとして例外になる', () async {
      final broken = '${root.path}${Platform.pathSeparator}broken';
      await Link(broken).create('${root.path}${Platform.pathSeparator}nowhere');
      await expectLater(
        savePngInto(Directory(broken), Uint8List.fromList([1]), 'a.png'),
        throwsA(isA<FileSystemException>()),
      );
    }, skip: skipSymlink);
  });

  group('macOS entitlements (#64)', () {
    // サンドボックス下でコンテナ内 Data/Downloads のリンク先（実 ~/Downloads）へ
    // 書ける条件。どちらかから落ちる（またはコメントアウトされる）と書き込みが
    // サンドボックスに拒否される。XML コメントを除いてから照合する。
    bool hasDownloadsEntitlement(String plist) {
      final active = plist.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      return RegExp(
        r'<key>com\.apple\.security\.files\.downloads\.read-write</key>\s*<true/>',
      ).hasMatch(active);
    }

    test('検出関数: 有効なキーは true、XML コメントアウトされたキーは false', () {
      const active =
          '<dict><key>com.apple.security.files.downloads.read-write</key>'
          '<true/></dict>';
      const commented =
          '<dict><!-- <key>com.apple.security.files.downloads.read-write'
          '</key>\n<true/> --></dict>';
      const falseValue =
          '<dict><key>com.apple.security.files.downloads.read-write</key>'
          '<false/></dict>';
      expect(hasDownloadsEntitlement(active), isTrue);
      expect(hasDownloadsEntitlement(commented), isFalse);
      expect(hasDownloadsEntitlement(falseValue), isFalse);
    });

    for (final name in ['DebugProfile', 'Release']) {
      test('$name.entitlements に有効な Downloads の読み書き entitlement がある', () {
        final plist =
            File('macos/Runner/$name.entitlements').readAsStringSync();
        expect(hasDownloadsEntitlement(plist), isTrue);
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
        simulationNotice: 'Simulation (approximation)',
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
        simulationNotice: 'Simulation (approximation)',
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
        simulationNotice: 'Simulation (approximation)',
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

    test('escalationGroups（段ごとの見出し + 条件文）ぶん、無しより高くなる', () async {
      final base = await makeBase(80, 60);
      const withoutGroups = ExportCaption(
        symptomLabel: 'BPPV Rotation',
        strengthLabel: 'Strength: 60%',
        isoDate: '2026-06-23',
        simulationNotice: 'Simulation (approximation)',
      );
      const withGroups = ExportCaption(
        symptomLabel: 'BPPV Rotation',
        strengthLabel: 'Strength: 60%',
        isoDate: '2026-06-23',
        simulationNotice: 'Simulation (approximation)',
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

    /// [png] を実際にデコードして RGBA の生画素を返す（焼き込みの検証は
    /// 描画命令ではなく、書き出される PNG の画素で行う）。
    Future<({int width, int height, Uint8List rgba})> decodePng(
        Uint8List png) async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = (
        width: image.width,
        height: image.height,
        rgba: data!.buffer.asUint8List()
      );
      image.dispose();
      codec.dispose();
      return result;
    }

    /// 帯の中で「注記の色（純白）」の画素が並ぶ行の塊（上から順）ごとの
    /// 横方向の広がり（px）を返す。
    List<int> whiteLineExtents(
        ({int width, int height, Uint8List rgba}) img, int bandTop) {
      final extents = <int>[];
      var minX = -1;
      var maxX = -1;
      var inLine = false;
      void flush() {
        if (inLine) extents.add(maxX - minX + 1);
        inLine = false;
        minX = -1;
        maxX = -1;
      }

      for (var y = bandTop; y < img.height; y++) {
        var rowMin = -1;
        var rowMax = -1;
        for (var x = 0; x < img.width; x++) {
          final o = (y * img.width + x) * 4;
          if (img.rgba[o] == 0xFF &&
              img.rgba[o + 1] == 0xFF &&
              img.rgba[o + 2] == 0xFF) {
            if (rowMin < 0) rowMin = x;
            rowMax = x;
          }
        }
        if (rowMin < 0) {
          flush();
        } else {
          inLine = true;
          minX = minX < 0 ? rowMin : (rowMin < minX ? rowMin : minX);
          maxX = rowMax > maxX ? rowMax : maxX;
        }
      }
      flush();
      return extents;
    }

    test(
        'simulationNotice は書き出した PNG の画素として焼き込まれ、'
        '文言の長さに応じて広がる（#80）', () async {
      final base = await makeBase(640, 40);
      addTearDown(base.dispose);

      Future<List<int>> extentsFor(String notice) async {
        final composed = await composeExportImage(
          base,
          ExportCaption(
            symptomLabel: 'Tritanopia',
            strengthLabel: 'Strength: 60%',
            isoDate: '2026-06-23',
            simulationNotice: notice,
          ),
        );
        final png = await encodeImagePng(composed);
        composed.dispose();
        return whiteLineExtents(await decodePng(png!), base.height);
      }

      final long = await extentsFor('Simulation (approximation)');
      final short = await extentsFor('Sim');

      // 純白の行の塊は 2 つ: 症状名（太字 18px）と、注記（14px）。
      expect(long, hasLength(2));
      expect(short, hasLength(2));
      // 症状名は同じ、注記だけが文言に応じて変わる。
      expect(long[0], short[0]);
      expect(long[1], greaterThan(short[1] * 4));
      expect(long[1], greaterThan(0));
    });

    test('simulationNotice は受診喚起の有無にかかわらず常に描かれる（#80）', () async {
      final base = await makeBase(640, 40);
      addTearDown(base.dispose);
      final composed = await composeExportImage(
        base,
        const ExportCaption(
          symptomLabel: 'Glaucoma',
          strengthLabel: 'Strength: 80%',
          isoDate: '2026-06-23',
          simulationNotice: 'Simulation (approximation)',
          urgencyMessage: 'Sudden changes in vision can need prompt care.',
        ),
      );
      final png = await encodeImagePng(composed);
      composed.dispose();
      final extents = whiteLineExtents(await decodePng(png!), base.height);
      expect(extents, hasLength(2));
    });

    /// 帯の中の純白（注記の色）の画素数。
    int whitePixels(
        ({int width, int height, Uint8List rgba}) img, int bandTop) {
      var n = 0;
      for (var y = bandTop; y < img.height; y++) {
        for (var x = 0; x < img.width; x++) {
          final o = (y * img.width + x) * 4;
          if (img.rgba[o] == 0xFF &&
              img.rgba[o + 1] == 0xFF &&
              img.rgba[o + 2] == 0xFF) {
            n++;
          }
        }
      }
      return n;
    }

    /// 幅 [width] の画像に焼き込まれた、simulationNotice だけの純白画素数。
    /// 注記が空の同じ caption との差を取り、症状名などを除く。
    Future<int> noticePixelsAtWidth(int width, {String? experimental}) async {
      final base = await makeBase(width, 40);
      addTearDown(base.dispose);
      Future<int> count(String notice, String? exp) async {
        final composed = await composeExportImage(
          base,
          ExportCaption(
            symptomLabel: 'Tritanopia',
            strengthLabel: 'Strength: 60%',
            isoDate: '2026-06-23',
            simulationNotice: notice,
            experimentalNotice: exp,
          ),
        );
        final png = await encodeImagePng(composed);
        composed.dispose();
        return whitePixels(await decodePng(png!), base.height);
      }

      return await count('Simulation (approximation)', experimental) -
          await count('', null);
    }

    test(
        'ごく狭い画像（64px・100px 幅）でも simulationNotice は省略されず全文が'
        '描かれる（広い画像と同じ画素量。近似の注記が欠けない）（#80）', () async {
      // 基準: 1 行に収まる幅 640px。テスト環境の文字（Ahem）は 1 文字が
      // 塗りつぶしの正方形なので、全文が描かれていれば画素量は幅によらず
      // ほぼ同じ（行送りの端数で縁がにじむぶんだけ差が出る）。
      final wide = await noticePixelsAtWidth(640);
      expect(wide, greaterThan(0));
      for (final width in [64, 100]) {
        final narrow = await noticePixelsAtWidth(width);
        expect(narrow, greaterThan((wide * 0.8).round()),
            reason: '$width px 幅で注記が欠けている（省略記号で切られている）');
        expect(narrow, lessThan((wide * 1.2).round()), reason: '$width px 幅');
      }
    });

    test('極小の画像（12px 幅）でも左余白で文字が画像の外に出ない（#80）', () async {
      // 余白が 16px 固定だと、12px 幅では文字の開始位置が画像の外になり、
      // 注記が 1 画素も残らない。
      final narrow = await noticePixelsAtWidth(12);
      expect(narrow, greaterThan(0));
    });

    test('experimentalNotice は全文が別の行として焼き込まれ、狭い画像でも省略されない（#80）', () async {
      // 広い画像: 症状名・シミュレーション注記・実験的注記の 3 行（純白の塊）。
      final base = await makeBase(640, 40);
      addTearDown(base.dispose);
      final composed = await composeExportImage(
        base,
        const ExportCaption(
          symptomLabel: 'Tetrachromacy',
          strengthLabel: 'Strength: 100%',
          isoDate: '2026-06-23',
          simulationNotice: 'Simulation (approximation)',
          experimentalNotice: 'Experimental visualization',
        ),
      );
      final png = await encodeImagePng(composed);
      composed.dispose();
      final extents = whiteLineExtents(await decodePng(png!), base.height);
      expect(extents, hasLength(3));

      // 狭い画像でも、実験的注記ぶんの画素が広い画像と同じ量だけ増える。
      final wideOnly = await noticePixelsAtWidth(640);
      final wideBoth = await noticePixelsAtWidth(640,
          experimental: 'Experimental visualization');
      final expWide = wideBoth - wideOnly;
      expect(expWide, greaterThan(0));

      final narrowOnly = await noticePixelsAtWidth(100);
      final narrowBoth = await noticePixelsAtWidth(100,
          experimental: 'Experimental visualization');
      final expNarrow = narrowBoth - narrowOnly;
      expect(expNarrow, greaterThan((expWide * 0.8).round()));
      expect(expNarrow, lessThan((expWide * 1.2).round()));
    });
  });
}
