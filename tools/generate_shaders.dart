/// CLI: generate Impeller `.frag` shaders from the vendored sensus dump and
/// update `pubspec.yaml`'s `shaders:` block (#12).
///
/// Usage:
///   dart run tools/generate_shaders.dart           # write shaders + pubspec
///   dart run tools/generate_shaders.dart --check    # verify, non-zero on drift
///
/// Input:  tools/sensus_shaders.g.json (vendored from sensus-core dump_shaders).
/// Output: shaders/<name>.frag + pubspec.yaml shaders: block.
library;

import 'dart:convert';
import 'dart:io';

import 'shader_codegen.dart';

/// Schema id this CLI knows how to read (mirrors the dumper's `DUMP_SCHEMA`).
const String _expectedSchema = 'sensus-shader-dump/v1';

/// Major version of the `sensus-core` crate ue depends on (see
/// `rust/Cargo.toml`: `sensus-core = "0.5"`). The vendored dump's
/// `sensus_core_version` must share this major, else it is stale/incompatible.
const int _expectedSensusMajor = 0;

/// Filters intentionally NOT in the dump, with the reason each is excluded.
/// Logged to stderr on every run so the 20-of-N gap is never silent.
///
/// Keep in sync with the dumper's `filters()` list / module docs in
/// `sensus/crates/core/examples/dump_shaders.rs`.
const Map<String, String> _excludedFilters = <String, String>{
  'dry_eye': 'non-constant loop bound (radius); Impeller SkSL rejects it',
  'starbursts':
      'non-constant loop bound (iRayLen/numRays); Impeller SkSL rejects it',
  'glaucoma': 'int/uint uniform (mode); host wiring has no int support',
  'cataract': 'int/uint uniform; host wiring has no int support',
  'flickering_stars': 'int/uint uniform; host wiring has no int support',
  'metamorphopsia': 'int/uint uniform; host wiring has no int support',
  'vertigo': 'per-frame uTime uniform; host has no time wiring',
  'bppv_rotation': 'per-frame uTime uniform; host has no time wiring',
  'floaters': 'second sampler (uMask); host wires a single uTexture only',
  'depth_aware_blur':
      'second sampler (uDepth); host wires a single uTexture only',
};

void main(List<String> args) {
  final check = args.contains('--check');

  // This script lives in <root>/tools/.
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final root = scriptDir.parent;

  final jsonFile = File('${scriptDir.path}/sensus_shaders.g.json');
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

  final sensusVersion = dump['sensus_core_version'] as String;
  final entries = dump['shaders'] as List<dynamic>;

  // S1: surface the included/excluded split so the gap is never silent.
  stderr.writeln(
    'sensus-core v$sensusVersion: ${entries.length} filters in scope, '
    '${_excludedFilters.length} excluded:',
  );
  final excludedKeys = _excludedFilters.keys.toList()..sort();
  for (final name in excludedKeys) {
    stderr.writeln('  - $name: ${_excludedFilters[name]}');
  }

  final shadersDir = Directory('${root.path}/shaders');
  if (!check) shadersDir.createSync(recursive: true);

  final stems = <String>[];
  final drift = <String>[];

  for (var i = 0; i < entries.length; i++) {
    final e = _validatedEntry(entries[i], i);
    final name = e['name'] as String;
    final glsl = e['glsl'] as String;
    final layout = (e['layout'] as List<dynamic>).cast<String>();

    final generated = convertShaderToImpeller(
      glsl,
      layout,
      name,
      sensusVersion: sensusVersion,
    );
    stems.add(name);

    final outFile = File('${shadersDir.path}/$name.frag');
    if (check) {
      final existing = outFile.existsSync() ? outFile.readAsStringSync() : '';
      if (existing != generated) drift.add('shaders/$name.frag');
    } else {
      outFile.writeAsStringSync(generated);
      stdout.writeln('wrote shaders/$name.frag');
    }
  }

  final pubspecFile = File('${root.path}/pubspec.yaml');
  final pubspecContent = pubspecFile.readAsStringSync();
  final updatedPubspec = updatePubspecShaders(pubspecContent, stems);
  if (check) {
    if (pubspecContent != updatedPubspec) drift.add('pubspec.yaml');
  } else {
    pubspecFile.writeAsStringSync(updatedPubspec);
    stdout.writeln('updated pubspec.yaml shaders: block');
  }

  if (check) {
    if (drift.isEmpty) {
      stdout.writeln('shaders up to date (${stems.length} filters).');
    } else {
      stderr.writeln('error: generated artifacts are stale. Run '
          '`dart run tools/generate_shaders.dart`. Drifted:');
      for (final d in drift) {
        stderr.writeln('  - $d');
      }
      exitCode = 1;
    }
  } else {
    stdout.writeln('done: ${stems.length} shaders generated.');
  }
}

/// Parses + validates the top-level dump object (M2 freshness, S2 schema).
///
/// Throws [FormatException] (with a human-readable message) on: non-object
/// root, missing/unknown `schema`, missing/malformed `sensus_core_version`,
/// a major-version mismatch against [_expectedSensusMajor], or a missing
/// `shaders` array. The pre-#24 shape was a bare JSON array; that legacy form is
/// rejected here so a stale vendored file fails loudly.
Map<String, dynamic> _parseDump(String contents) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'expected a JSON object {schema, sensus_core_version, shaders}, got a '
      'non-object root. The pre-#24 bare-array dump is no longer supported; '
      'regenerate from sensus-core dump_shaders.',
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
  final major = int.tryParse(version.split('.').first);
  if (major == null) {
    throw FormatException(
      'malformed `sensus_core_version` "$version" (expected semver x.y.z).',
    );
  }
  if (major != _expectedSensusMajor) {
    throw FormatException(
      'sensus_core_version "$version" (major $major) does not match the '
      'sensus-core dependency major $_expectedSensusMajor (rust/Cargo.toml '
      '`sensus-core = "$_expectedSensusMajor.x"`). The vendored dump is stale; '
      'regenerate it.',
    );
  }

  final shaders = decoded['shaders'];
  if (shaders is! List) {
    throw const FormatException('missing array field `shaders`.');
  }
  return decoded;
}

/// S2: validates a single shader entry has the expected `name`/`glsl`/`layout`
/// shape, throwing [FormatException] with the offending index on any gap.
Map<String, dynamic> _validatedEntry(dynamic raw, int index) {
  if (raw is! Map<String, dynamic>) {
    throw FormatException('shaders[$index] is not a JSON object.');
  }
  final name = raw['name'];
  if (name is! String || name.isEmpty) {
    throw FormatException('shaders[$index] missing string field `name`.');
  }
  final glsl = raw['glsl'];
  if (glsl is! String || glsl.isEmpty) {
    throw FormatException('shaders[$index] ($name) missing string `glsl`.');
  }
  final layout = raw['layout'];
  if (layout is! List || layout.isEmpty) {
    throw FormatException('shaders[$index] ($name) missing array `layout`.');
  }
  for (final item in layout) {
    if (item is! String) {
      throw FormatException(
        'shaders[$index] ($name) has a non-string `layout` entry.',
      );
    }
  }
  return raw;
}
