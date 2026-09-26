/// CLI: generate `lib/rendering/color_matrices.g.dart` from the vendored
/// sensus Machado severity-table dump (#59, #34).
///
/// Usage:
///   dart run tools/generate_color_matrices.dart           # write the file
///   dart run tools/generate_color_matrices.dart --check    # verify, non-zero on drift
///
/// Input:  tools/color_matrices.g.json (vendored from sensus-core via
///         `rust/src/color_matrix_gen.rs`, `cargo test -- --ignored
///         gen_color_matrices`).
/// Output: lib/rendering/color_matrices.g.dart.
///
/// This mirrors `generate_shaders.dart`'s JSON→generated-artifact pipeline so
/// the two vendored-from-sensus pipelines stay structurally consistent. A
/// **generated Dart file** (rather than a JSON asset loaded at runtime via
/// `rootBundle`) is deliberate: `ShaderFilter` (`lib/rendering/shader_filter.dart`)
/// must also work from a plain `flutter test` host process with no
/// flutter_rust_bridge native library loaded (see that file's module doc), and
/// a `const` Dart file needs no async asset load or engine bridge at all.
library;

import 'dart:convert';
import 'dart:io';

import 'shader_codegen.dart' show sensusVersionSatisfiesDependency;

/// Schema id this CLI knows how to read (mirrors the generator's
/// `"schema": "sensus-color-matrices/v1"`).
const String _expectedSchema = 'sensus-color-matrices/v1';

/// The `sensus-core` crate version line ue depends on (see `rust/Cargo.toml`:
/// `sensus-core = "0.6"`). Same major.minor semantics as
/// `generate_shaders.dart`'s `_expectedSensusVersionLine`.
const String _expectedSensusVersionLine = '0.6';

const String _outputPath = 'lib/rendering/color_matrices.g.dart';

void main(List<String> args) {
  final check = args.contains('--check');

  final scriptDir = File(Platform.script.toFilePath()).parent;
  final root = scriptDir.parent;

  final jsonFile = File('${scriptDir.path}/color_matrices.g.json');
  if (!jsonFile.existsSync()) {
    stderr.writeln('error: ${jsonFile.path} not found.');
    exitCode = 2;
    return;
  }

  final Map<String, dynamic> dump;
  try {
    dump = _parseDump(jsonFile.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('error: ${jsonFile.path}: ${e.message}');
    exitCode = 2;
    return;
  }

  final generated = _renderDartFile(dump);
  final outFile = File('${root.path}/$_outputPath');

  if (check) {
    final existing = outFile.existsSync() ? outFile.readAsStringSync() : '';
    if (existing == generated) {
      stdout.writeln('color matrices up to date.');
    } else {
      stderr.writeln(
        'error: $_outputPath is stale. Run '
        '`dart run tools/generate_color_matrices.dart`.',
      );
      exitCode = 1;
    }
  } else {
    outFile.writeAsStringSync(generated);
    stdout.writeln('wrote $_outputPath');
  }
}

/// Parses + validates the top-level dump object. Throws [FormatException]
/// (human-readable) on: non-object root, missing/unknown `schema`,
/// missing/malformed `sensus_core_version`, a version mismatch against
/// [_expectedSensusVersionLine], or a missing/malformed grid/weights field.
Map<String, dynamic> _parseDump(String contents) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'expected a JSON object {schema, sensus_core_version, '
      'protanopia_grid, deuteranopia_grid, tritanopia_grid, '
      'achromatopsia_weights}, got a non-object root.',
    );
  }

  final schema = decoded['schema'];
  if (schema is! String) {
    throw const FormatException('missing string field `schema`.');
  }
  if (schema != _expectedSchema) {
    throw FormatException(
      'unknown schema `$schema` (expected `$_expectedSchema`). Regenerate the '
      'dump with a matching sensus-core.',
    );
  }

  final version = decoded['sensus_core_version'];
  if (version is! String || version.isEmpty) {
    throw const FormatException('missing string field `sensus_core_version`.');
  }
  if (int.tryParse(version.split('.').first) == null) {
    throw FormatException(
      'malformed `sensus_core_version` "$version" (expected semver x.y.z).',
    );
  }
  if (!sensusVersionSatisfiesDependency(version, _expectedSensusVersionLine)) {
    throw FormatException(
      'sensus_core_version "$version" does not match the sensus-core '
      'dependency "$_expectedSensusVersionLine" (rust/Cargo.toml '
      '`sensus-core = "$_expectedSensusVersionLine"`). The vendored dump is '
      'stale; regenerate it.',
    );
  }

  for (final key in [
    'protanopia_grid',
    'deuteranopia_grid',
    'tritanopia_grid',
  ]) {
    _validatedGrid(decoded[key], key);
  }
  _validatedWeights(decoded['achromatopsia_weights']);

  return decoded;
}

/// An 11-entry grid of 9-element row-major 3x3 matrices (severity 0.0..1.0 in
/// steps of 0.1).
List<List<double>> _validatedGrid(dynamic raw, String field) {
  if (raw is! List || raw.length != 11) {
    throw FormatException('`$field` must be an array of 11 matrices.');
  }
  return raw.map((row) {
    if (row is! List || row.length != 9) {
      throw FormatException('`$field` entries must be 9-element arrays.');
    }
    return row.map((v) {
      if (v is! num) {
        throw FormatException('`$field` contains a non-numeric element.');
      }
      return v.toDouble();
    }).toList();
  }).toList();
}

Map<String, double> _validatedWeights(dynamic raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException(
      '`achromatopsia_weights` must be an object with r/g/b fields.',
    );
  }
  final out = <String, double>{};
  for (final key in ['r', 'g', 'b']) {
    final v = raw[key];
    if (v is! num) {
      throw FormatException('`achromatopsia_weights.$key` must be numeric.');
    }
    out[key] = v.toDouble();
  }
  return out;
}

String _renderGrid(String name, List<List<double>> grid) {
  final rows = grid
      .map((row) => '  <double>[${row.map(_formatDouble).join(', ')}],')
      .join('\n');
  return 'const List<List<double>> $name = <List<double>>[\n$rows\n];\n';
}

/// Renders a double the same way Dart source literals do, but always with a
/// decimal point (`1.0`, not `1`) so every grid entry reads as a `double`
/// literal consistently.
String _formatDouble(double v) {
  if (v == v.roundToDouble() && v.isFinite) {
    return v.toStringAsFixed(1);
  }
  return v.toString();
}

String _renderDartFile(Map<String, dynamic> dump) {
  final version = dump['sensus_core_version'] as String;
  final protanopia = _validatedGrid(dump['protanopia_grid'], 'protanopia_grid');
  final deuteranopia =
      _validatedGrid(dump['deuteranopia_grid'], 'deuteranopia_grid');
  final tritanopia = _validatedGrid(dump['tritanopia_grid'], 'tritanopia_grid');
  final weights = _validatedWeights(dump['achromatopsia_weights']);

  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT BY HAND.')
    ..writeln('//')
    ..writeln('// Source: tools/color_matrices.g.json (sensus_core $version).')
    ..writeln('// Regenerate:')
    ..writeln('//   1. cd rust && cargo test -- --ignored gen_color_matrices')
    ..writeln('//   2. dart run tools/generate_color_matrices.dart')
    ..writeln('//')
    ..writeln(
        '// Machado 2009 の 11 段 severity テーブル（severity=0.0..1.0 を 0.1 刻みで')
    ..writeln('// グリッド化したもの）。中間 strength の行列は')
    ..writeln('// `ShaderFilter.resolveSeverityMatrix()`（shader_filter.dart）が')
    ..writeln('// sensus_core の `resolve_severity_matrix` と同じ区分線形補間でグリッド間を')
    ..writeln('// 補間して求める。手書きの数値ではなく、すべて sensus-core（テーブル自体は')
    ..writeln('// `pub(crate)` で直接参照できないため、グリッド点ちょうどの `strength` で公開')
    ..writeln('// 関数 `shaders::*_uniforms()` を呼んで汲み出したもの）由来の生成物（#59、#34）。')
    ..writeln()
    ..writeln('/// grid[i]（i=0..10）は severity = i/10 に対応する解決済み 3x3 行列')
    ..writeln('/// （行優先、9要素）。1行1グリッド点で揃えた compact な形で書き出す')
    ..writeln('/// （このファイルは生成物であり手編集しない前提のため、`dart format` の')
    ..writeln('/// 折り返し規則には合わせない）。')
    ..writeln(_renderGrid('protanopiaColorMatrixGrid', protanopia))
    ..writeln(_renderGrid('deuteranopiaColorMatrixGrid', deuteranopia))
    ..writeln(_renderGrid('tritanopiaColorMatrixGrid', tritanopia))
    ..writeln('/// achromatopsia は severity テーブルを持たず、strength に依存しない固定重み')
    ..writeln('/// （BT.709 photopic luminance）をシェーダが直接使う')
    ..writeln('/// （`achromatopsia.frag` の `uRWeight`/`uGWeight`/`uBWeight`）。')
    ..writeln(
        'const double achromatopsiaRWeight = ${_formatDouble(weights['r']!)};')
    ..writeln(
        'const double achromatopsiaGWeight = ${_formatDouble(weights['g']!)};')
    ..writeln(
        'const double achromatopsiaBWeight = ${_formatDouble(weights['b']!)};');

  return buffer.toString();
}
