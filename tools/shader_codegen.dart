/// Pure shader codegen for the sensus -> Impeller (Flutter) sync (#12).
///
/// This library has no side effects (no file IO): it is imported by both the
/// CLI (`tools/generate_shaders.dart`) and the tests
/// (`test/shader_codegen_test.dart`). All IO lives in the CLI.
///
/// Conversion (sensus GLSL ES 3.00 -> Impeller GLSL subset):
///   1. Drop `#version 300 es` and `precision ... float;`; prepend
///      `#include <flutter/runtime_effect.glsl>`.
///   2. Drop the original `uniform ...;` declarations and `in vec2 vTexCoord;`;
///      keep `out vec4 fragColor;`. Re-emit scalar uniforms in `layout` order as
///      `uniform float <name>;`, then `uniform sampler2D uTexture;`.
///   3. Expand array-uniform reads `name[k]` -> `namek` in the body, for every
///      array uniform declared in the source (multi-digit indices supported).
///   4. Replace `vec2` uniforms referenced in the body (e.g. `uTexelSize`) with
///      `vec2(<name>_x, <name>_y)`.
///   5. Impeller has no `vTexCoord` varying, so replace body `vTexCoord` with UV
///      derived from `FlutterFragCoord()` and the synthetic `uResolution` pair.
///   6. Assert the emitted `uniform float` order (up to `uTexture`) == `layout`.
library;

/// Marker placed at the top of every generated `.frag` so humans know not to
/// hand-edit it.
const String kGeneratedHeaderMarker = 'GENERATED FILE - DO NOT EDIT';

/// Synthetic resolution uniform base name (see rule 5). Its scalar components
/// `uResolution_x` / `uResolution_y` are the last two entries of every layout.
const String kResolutionBase = 'uResolution';

/// Path (relative to repo root) of the vendored sensus dump the generated
/// `.frag` files are derived from. Recorded in each header for traceability.
const String kDumpInputPath = 'tools/sensus_shaders.g.json';

/// Matches a top-level GLSL precision declaration of any qualifier and type,
/// e.g. `precision mediump float;` or `precision highp int;`. Impeller's
/// runtime-effect subset accepts no precision qualifiers at all, so every such
/// line is dropped during conversion (see Rule 1). The input is already
/// `trim()`med, so no leading-whitespace allowance is needed here.
final RegExp _precisionDeclRegex = RegExp(r'^precision\s+\w+\s+\w+\s*;$');

/// Converts a sensus GLSL ES 3.00 source into an Impeller-compatible shader.
///
/// [glsl] is the source from sensus `*_glsl()`. [layout] is the
/// `setFloat`-ordered scalar uniform names (from the vendored dump). [filterName]
/// is the snake_case stem used for the header comment. [sensusVersion] is the
/// `sensus_core_version` recorded in the dump; it is stamped into the header for
/// traceability (null/empty when a caller has none, e.g. a unit test).
///
/// Throws [StateError] if the regenerated `uniform float` declaration order (up
/// to `uTexture`) does not match [layout] exactly, or if the body references an
/// array uniform (`name[k]`) that the source never declared.
String convertShaderToImpeller(
  String glsl,
  List<String> layout,
  String filterName, {
  String? sensusVersion,
}) {
  // Compute the scalar-float layout that the source *implies*, and assert it
  // matches the provided [layout]. This is the real guard: it fails loudly if
  // the vendored layout drifts from the actual shader source (wrong order,
  // missing vec2 component, stray scalar, etc.).
  final expectedLayout = deriveLayoutFromSource(glsl, filterName);
  if (!_listEquals(expectedLayout, layout)) {
    throw StateError(
      'Shader "$filterName": provided layout does not match the layout implied '
      'by the source.\n  source-implied: $expectedLayout\n  provided:       '
      '$layout',
    );
  }

  // Collect every array uniform declared in the source so the body rewrite can
  // expand `name[k]` -> `name_k` for ALL of them (not just `uMatrix`). The layout
  // side (deriveLayoutFromSource) already supports arbitrary `float NAME[n]`
  // arrays, so this keeps the body rewrite and the layout in agreement.
  final arrayUniformNames = _arrayUniformNames(glsl);

  // Collect the names of the original `vec2` uniforms so we can rewrite their
  // body references to `vec2(<name>_x, <name>_y)`.
  final vec2Names = <String>[];

  final body = <String>[];
  for (final line in glsl.split('\n')) {
    final trimmed = line.trim();

    // Rule 1: drop the GLSL ES header lines.
    if (trimmed == '#version 300 es') continue;
    // Drop ANY top-level precision declaration, not just `precision ... float;`.
    // Impeller's runtime-effect subset rejects every precision qualifier
    // (lowp/mediump/highp) for every type (float/int/...). Matching only
    // `float;` previously let `precision highp int;` leak into the generated
    // astigmatism/nystagmus shaders.
    if (_precisionDeclRegex.hasMatch(trimmed)) {
      continue;
    }

    // Rule 2: drop original uniform declarations and the vTexCoord varying.
    if (trimmed.startsWith('uniform ')) {
      final decl = trimmed.substring('uniform '.length);
      if (decl.startsWith('vec2 ') || decl.startsWith('vec2  ')) {
        final ident = decl
            .substring('vec2'.length)
            .trim()
            .split(RegExp(r'[\s;]'))
            .first;
        vec2Names.add(ident);
      }
      continue;
    }
    if (trimmed == 'in vec2 vTexCoord;') continue;

    body.add(line);
  }

  var bodySrc = body.join('\n');

  // Rule 3: array expansion `name[k]` -> `namek` for every declared array
  // uniform. Multi-digit indices are supported (`[12]` -> `12`). Each name is
  // regex-escaped so it cannot inject metacharacters.
  for (final name in arrayUniformNames) {
    bodySrc = bodySrc.replaceAllMapped(
      RegExp('${RegExp.escape(name)}' r'\[(\d+)\]'),
      (m) => '$name${m.group(1)}',
    );
  }

  // Post-condition (should-1a): no array-style uniform access may survive the
  // rewrite. A leftover `<identifier>[<digits>]` means the source used an array
  // uniform it never declared, which would emit an `impellerc`-incompatible
  // array reference (or silently mis-bind). Fail loudly instead. Dynamic
  // indexing (`arr[i]`, non-constant) is out of scope and left untouched.
  final leftoverArrayAccess = RegExp(r'\b(\w+)\[\d+\]').firstMatch(bodySrc);
  if (leftoverArrayAccess != null) {
    throw StateError(
      'Shader "$filterName": unexpanded array uniform access '
      '`${leftoverArrayAccess.group(0)}` survived codegen. Declare it as '
      '`uniform float ${leftoverArrayAccess.group(1)}[N];` so its flat scalar '
      'layout can be generated.',
    );
  }

  // Rule 4: vec2 uniform refs in the body -> vec2(name_x, name_y).
  //
  // Use a strict identifier boundary (a trailing negative lookahead in addition
  // to `\b`) so a payload uniform like `uTexelSize` cannot partially match (and
  // corrupt) a longer identifier such as `uTexelSizeScale`.
  //
  // PRECONDITION (should-2): each vec2 uniform name must be globally unique in
  // the body — there must be no local `float NAME`/`vec2 NAME` declaration that
  // shadows it. The boundary-anchored replacement is whole-identifier but not
  // scope-aware, so a same-named local would be wrongly rewritten. We detect
  // such a collision and throw rather than silently corrupt the shader. (sensus
  // sources name uniforms with a `u` prefix and locals without one, so this is
  // a guard against future drift, not a current occurrence.)
  for (final name in vec2Names) {
    final localDecl = RegExp(
      '(?:float|vec2)\\s+${RegExp.escape(name)}\\b(?![A-Za-z0-9_])\\s*[;=]',
    );
    if (localDecl.hasMatch(bodySrc)) {
      throw StateError(
        'Shader "$filterName": vec2 uniform `$name` collides with a local '
        'variable of the same name; the non-scope-aware vec2 rewrite would '
        'corrupt it. Rename the local before dumping this filter.',
      );
    }
    bodySrc = bodySrc.replaceAllMapped(
      RegExp('\\b${RegExp.escape(name)}\\b(?![A-Za-z0-9_])'),
      (_) => 'vec2(${name}_x, ${name}_y)',
    );
  }

  // Rule 5: Impeller has no vTexCoord. Derive UV from FlutterFragCoord() and the
  // synthetic resolution pair. Wrap in parens so it is safe in any expression.
  // The trailing negative lookahead keeps a longer identifier such as
  // `vTexCoordScale` from being partially rewritten.
  bodySrc = bodySrc.replaceAllMapped(
    RegExp(r'\bvTexCoord\b(?![A-Za-z0-9_])'),
    (_) =>
        '(FlutterFragCoord().xy / vec2(${kResolutionBase}_x, ${kResolutionBase}_y))',
  );

  // Cosmetic (nit-2): collapse runs of 2+ blank lines (left behind by dropped
  // `precision`/`#version`/uniform lines, and by source formatting) down to a
  // single blank line, so the generated body reads cleanly. This only touches
  // whitespace, never comments or code.
  bodySrc = bodySrc.replaceAll(RegExp(r'\n[ \t]*\n([ \t]*\n)+'), '\n\n');

  // Trim leading blank lines so the body starts cleanly after the uniform block.
  final bodyTrimmed = bodySrc.replaceFirst(RegExp(r'^\s*\n+'), '');

  // Rule 1 (#include) + rule 2 (re-emit): build the uniform block.
  final uniformBlock = StringBuffer();
  uniformBlock.writeln('#include <flutter/runtime_effect.glsl>');
  uniformBlock.writeln();
  for (final name in layout) {
    uniformBlock.writeln('uniform float $name;');
  }
  uniformBlock.writeln('uniform sampler2D uTexture;');

  final header = _headerComment(filterName, layout, sensusVersion);
  final result = '$header\n${uniformBlock.toString()}\n$bodyTrimmed';

  return result.endsWith('\n') ? result : '$result\n';
}

/// Derives the `setFloat`-ordered scalar uniform layout implied by a sensus
/// GLSL ES 3.00 [glsl] source, mirroring the Rust dumper's `derive_layout`.
///
/// Declaration order of `uniform float`/`uniform vec2`:
///   - `uniform float uMatrix[9];` -> `uMatrix0`..`uMatrix8`
///   - `uniform float uXxx;`       -> `uXxx`
///   - `uniform vec2  uXxx;`       -> `uXxx_x`, `uXxx_y`
/// Then appends the synthetic `uResolution_x`, `uResolution_y` pair.
///
/// Throws [StateError] for uniform kinds outside the host-compatible scope
/// (anything other than `sampler2D uTexture`, `float`, `vec2`).
List<String> deriveLayoutFromSource(String glsl, String filterName) {
  final layout = <String>[];
  for (final raw in glsl.split('\n')) {
    // Strip trailing `// ...` comments and surrounding whitespace.
    final line = (raw.contains('//') ? raw.substring(0, raw.indexOf('//')) : raw)
        .trim();
    if (!line.startsWith('uniform ')) continue;
    final rest =
        line.substring('uniform '.length).replaceAll(';', '').trim();
    final parts = rest.split(RegExp(r'\s+'));
    final ty = parts.isNotEmpty ? parts[0] : '';
    final ident = parts.length > 1 ? parts[1] : '';

    switch (ty) {
      case 'sampler2D':
        if (ident != 'uTexture') {
          throw StateError(
            'Shader "$filterName": only the single sampler `uTexture` is '
            'supported, got `$ident`.',
          );
        }
      case 'float':
        final bracket = ident.indexOf('[');
        if (bracket >= 0) {
          final base = ident.substring(0, bracket);
          final count =
              int.parse(ident.substring(bracket + 1, ident.indexOf(']')));
          for (var i = 0; i < count; i++) {
            layout.add('$base$i');
          }
        } else {
          layout.add(ident);
        }
      case 'vec2':
        layout.add('${ident}_x');
        layout.add('${ident}_y');
      default:
        throw StateError(
          'Shader "$filterName": uniform kind `$ty` ($ident) is outside the '
          'host-compatible scope (only sampler2D uTexture / float / vec2).',
        );
    }
  }
  layout.add('${kResolutionBase}_x');
  layout.add('${kResolutionBase}_y');
  return layout;
}

/// Returns the names of all array-style uniforms declared in [glsl], e.g.
/// `{uMatrix}` for `uniform float uMatrix[9];`. Matches `uniform float NAME[n];`
/// (optionally precision-qualified) in declaration position. Shared by the body
/// rewrite (Rule 3) so it expands exactly the arrays that
/// [deriveLayoutFromSource] flattens, keeping body and layout in agreement.
Set<String> _arrayUniformNames(String glsl) {
  final re = RegExp(
    r'^\s*uniform\s+(?:lowp\s+|mediump\s+|highp\s+)?float\s+(\w+)\s*\[\s*\d+\s*\]\s*;',
    multiLine: true,
  );
  return re.allMatches(glsl).map((m) => m.group(1)!).toSet();
}

String _headerComment(
  String filterName,
  List<String> layout,
  String? sensusVersion,
) {
  final version = (sensusVersion == null || sensusVersion.isEmpty)
      ? 'unknown'
      : sensusVersion;
  final buf = StringBuffer();
  buf.writeln('// $kGeneratedHeaderMarker.');
  buf.writeln('//');
  buf.writeln('// Source of truth: sensus-core vision filter "$filterName"');
  buf.writeln('// (canonical GLSL: sensus shaders/$filterName.frag, '
      'sensus-core v$version).');
  buf.writeln('// Filter-specific provenance (e.g. the Machado 2009 matrix and');
  buf.writeln('// its citation) lives in the sensus source, not here.');
  buf.writeln('//');
  buf.writeln('// Regenerate with: dart run tools/generate_shaders.dart');
  buf.writeln('// (input dump: $kDumpInputPath, '
      'produced by sensus-core v$version).');
  buf.writeln('//');
  buf.writeln('// scalar uniform order (setFloat index): ${layout.join(', ')}');
  return buf.toString().trimRight();
}

/// Extracts the `uniform float <name>;` names in declaration order from
/// generated GLSL. Only `uniform float` declarations are matched, so the
/// `uniform sampler2D uTexture;` line (and any other non-float uniform) is
/// simply skipped rather than acting as a terminator.
List<String> extractUniformFloatOrder(String glsl) {
  final names = <String>[];
  final re = RegExp(r'^\s*uniform\s+float\s+(\w+)\s*;', multiLine: true);
  for (final m in re.allMatches(glsl)) {
    names.add(m.group(1)!);
  }
  return names;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Builds the `pubspec.yaml` `shaders:` block (the `  shaders:` key plus its
/// indented `- shaders/<name>.frag` list) for the given stems, sorted
/// alphabetically for stable output.
String buildPubspecShadersBlock(Iterable<String> shaderStems) {
  final stems = shaderStems.toList()..sort();
  final buf = StringBuffer();
  buf.writeln('  shaders:');
  for (final stem in stems) {
    buf.writeln('    - shaders/$stem.frag');
  }
  return buf.toString().trimRight();
}

/// Replaces (or inserts) the `shaders:` block under the top-level `flutter:`
/// key in [pubspecContent], leaving everything else (incl. the `assets:` block)
/// untouched. Returns the new pubspec content.
///
/// Assumptions about the input pubspec (true for this repo's, kept simple on
/// purpose):
///   * The `shaders:` key is at exactly 2-space indentation (`  shaders:`),
///     i.e. directly under the top-level `flutter:` key.
///   * The existing shader list is the block of lines following that key that
///     are indented MORE deeply than the key (>=3 leading spaces). Such lines
///     are consumed and replaced — this now also tolerates indented comments
///     (`    # ...`) interleaved with the `- shaders/*.frag` entries.
///   * A blank line or any line indented <=2 spaces terminates the block.
String updatePubspecShaders(
  String pubspecContent,
  Iterable<String> shaderStems,
) {
  final block = buildPubspecShadersBlock(shaderStems);
  final lines = pubspecContent.split('\n');

  final shadersIdx = lines.indexWhere((l) => l == '  shaders:');
  if (shadersIdx >= 0) {
    // End of the existing block: subsequent lines indented 3+ spaces (covers
    // `    - path` list items AND indented `    # comment` lines).
    var end = shadersIdx + 1;
    while (end < lines.length) {
      final l = lines[end];
      if (l.trim().isEmpty) break;
      if (l.startsWith('   ')) {
        end++;
        continue;
      }
      break;
    }
    return <String>[
      ...lines.sublist(0, shadersIdx),
      ...block.split('\n'),
      ...lines.sublist(end),
    ].join('\n');
  }

  // No existing block: append at the end of the flutter: section.
  final flutterIdx = lines.indexWhere((l) => l == 'flutter:');
  if (flutterIdx < 0) {
    throw StateError('pubspec.yaml has no top-level `flutter:` key.');
  }
  var insertAt = flutterIdx + 1;
  while (insertAt < lines.length) {
    final l = lines[insertAt];
    if (l.isEmpty || l.startsWith(' ')) {
      insertAt++;
      continue;
    }
    break;
  }
  return <String>[
    ...lines.sublist(0, insertAt),
    ...block.split('\n'),
    ...lines.sublist(insertAt),
  ].join('\n');
}
