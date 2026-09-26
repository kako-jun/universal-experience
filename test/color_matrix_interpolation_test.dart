import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/rendering/color_matrices.g.dart';
import 'package:universal_experience/rendering/shader_filter.dart';

/// [ShaderFilter.resolveSeverityMatrix]（sensus の `resolve_severity_matrix` を
/// Dart で再実装したもの）が、strength=0/0.25/0.5/0.75/1.0 で sensus_core の CPU
/// 出力と一致することを確認する（#59 完了条件）。
///
/// 0.25/0.75 は Machado 11 段グリッドのちょうど中間（グリッド index 2↔3, 7↔8 間、
/// frac=0.5）にあたるため、`color_matrices.g.dart` のグリッド点だけでは検出できない
/// 「補間の式そのもの」を検証する。
///
/// fixture (`test/golden/color_matrix_strengths.g.json`) は rust
/// `golden_gen::gen_color_matrix_strength_fixture` が sensus_core の公開関数
/// `vision_uniforms()` から直接汲み出した生成物（手書きの数値ではない）。
/// 再生成手順は fixture 内 `_comment` および `rust/src/golden_gen.rs` 参照。
void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    final raw =
        File('test/golden/color_matrix_strengths.g.json').readAsStringSync();
    fixture = jsonDecode(raw) as Map<String, dynamic>;
  });

  List<double> fixtureMatrix(String type, int index) {
    final list = fixture[type] as List<dynamic>;
    return (list[index] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();
  }

  const strengths = <double>[0.0, 0.25, 0.5, 0.75, 1.0];

  void expectMatrixCloseTo(
    List<double> actual,
    List<double> expected, {
    required String reason,
  }) {
    expect(actual.length, expected.length, reason: reason);
    for (var i = 0; i < expected.length; i++) {
      expect(
        actual[i],
        closeTo(expected[i], 1e-4),
        reason: '$reason (element $i)',
      );
    }
  }

  group('resolveSeverityMatrix は sensus CPU fixture と一致する', () {
    final cases = <String, List<List<double>>>{
      'protanopia': protanopiaColorMatrixGrid,
      'deuteranopia': deuteranopiaColorMatrixGrid,
      'tritanopia': tritanopiaColorMatrixGrid,
    };

    for (final entry in cases.entries) {
      final name = entry.key;
      final grid = entry.value;

      for (var i = 0; i < strengths.length; i++) {
        final strength = strengths[i];
        test('$name strength=$strength', () {
          final actual = ShaderFilter.resolveSeverityMatrix(grid, strength);
          final expected = fixtureMatrix(name, i);
          expectMatrixCloseTo(
            actual,
            expected,
            reason: '$name strength=$strength: Dart 補間結果が sensus CPU '
                'fixture と乖離している',
          );
        });
      }
    }
  });

  group('achromatopsia の重みは strength に依存しない定数', () {
    test('achromatopsiaR/G/BWeight が fixture と一致する', () {
      final weights =
          fixture['achromatopsia_weights'] as Map<String, dynamic>;
      expect(achromatopsiaRWeight, (weights['r'] as num).toDouble());
      expect(achromatopsiaGWeight, (weights['g'] as num).toDouble());
      expect(achromatopsiaBWeight, (weights['b'] as num).toDouble());
    });
  });

  group('グリッド境界の防御的な挙動', () {
    test('NaN strength は identity（grid[0]）を返す', () {
      final actual = ShaderFilter.resolveSeverityMatrix(
        protanopiaColorMatrixGrid,
        double.nan,
      );
      expect(actual, protanopiaColorMatrixGrid[0]);
    });

    test('範囲外 strength は 0.0..1.0 に clamp される', () {
      final below = ShaderFilter.resolveSeverityMatrix(
        protanopiaColorMatrixGrid,
        -1.0,
      );
      final above = ShaderFilter.resolveSeverityMatrix(
        protanopiaColorMatrixGrid,
        2.0,
      );
      expect(below, protanopiaColorMatrixGrid[0]);
      expect(above, protanopiaColorMatrixGrid[10]);
    });
  });
}
