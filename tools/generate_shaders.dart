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

  final data = jsonDecode(jsonFile.readAsStringSync()) as List<dynamic>;

  final shadersDir = Directory('${root.path}/shaders');
  if (!check) shadersDir.createSync(recursive: true);

  final stems = <String>[];
  final drift = <String>[];

  for (final entry in data) {
    final e = entry as Map<String, dynamic>;
    final name = e['name'] as String;
    final glsl = e['glsl'] as String;
    final layout = (e['layout'] as List<dynamic>).cast<String>();

    final generated = convertShaderToImpeller(glsl, layout, name);
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
