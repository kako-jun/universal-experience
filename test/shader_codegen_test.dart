import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/shader_codegen.dart';

/// A 3x3-matrix + strength shader, structurally identical to what sensus-core
/// emits for the colour-vision filters (protanopia etc.).
const String _matrixGlsl = '''
#version 300 es
precision mediump float;

uniform sampler2D uTexture;
uniform float uStrength;
uniform float uMatrix[9];

in vec2 vTexCoord;
out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

void main() {
    vec4 tex = texture(uTexture, vTexCoord);
    float r = srgbToLinear(tex.r);
    float sr = uMatrix[0] * r + uMatrix[1] * r + uMatrix[2] * r;
    float sb = uMatrix[6] * r + uMatrix[7] * r + uMatrix[8] * r;
    fragColor = vec4(sr * uStrength, 0.0, sb, tex.a);
}
''';

const List<String> _matrixLayout = <String>[
  'uStrength',
  'uMatrix0', 'uMatrix1', 'uMatrix2',
  'uMatrix3', 'uMatrix4', 'uMatrix5',
  'uMatrix6', 'uMatrix7', 'uMatrix8',
  'uResolution_x', 'uResolution_y',
];

/// A shader with a `vec2 uTexelSize` payload uniform (like myopia / starbursts),
/// to exercise the vec2-splitting rule.
const String _payloadGlsl = '''
#version 300 es
precision highp float;

uniform sampler2D uTexture;
uniform float uStrength;
uniform vec2  uTexelSize;

in vec2 vTexCoord;
out vec4 fragColor;

void main() {
    vec2 uv = vTexCoord + uTexelSize;
    vec4 src = texture(uTexture, uv);
    fragColor = vec4(src.rgb * uStrength, src.a);
}
''';

const List<String> _payloadLayout = <String>[
  'uStrength',
  'uTexelSize_x',
  'uTexelSize_y',
  'uResolution_x',
  'uResolution_y',
];

const String _varying = 'vTexCoord';
const String _fragCoordCall = 'FlutterFragCoord()';

void main() {
  group('convertShaderToImpeller (matrix shader)', () {
    late String out;

    setUpAll(() {
      out = convertShaderToImpeller(_matrixGlsl, _matrixLayout, 'protanopia');
    });

    test('drops #version and precision header, prepends runtime_effect', () {
      expect(out.contains('#version'), isFalse);
      expect(out.contains('precision mediump float;'), isFalse);
      expect(out.contains('#include <flutter/runtime_effect.glsl>'), isTrue);
    });

    test('keeps fragColor out', () {
      expect(out.contains('out vec4 fragColor;'), isTrue);
    });

    test('removes every reference to the GLSL ES varying', () {
      expect(out.contains(_varying), isFalse);
    });

    test('derives UV from FlutterFragCoord and the resolution pair', () {
      expect(out.contains(_fragCoordCall), isTrue);
      expect(
        out.contains('$_fragCoordCall.xy / '
            'vec2(uResolution_x, uResolution_y)'),
        isTrue,
      );
    });

    test('expands uMatrix[k] to uMatrixk in the body', () {
      expect(out.contains('uMatrix['), isFalse);
      expect(out.contains('uMatrix0 * r'), isTrue);
      expect(out.contains('uMatrix8 * r'), isTrue);
    });

    test('keeps prelude helpers', () {
      expect(out.contains('srgbToLinear'), isTrue);
    });

    test('re-emits uniform float declarations in layout order + uTexture', () {
      expect(extractUniformFloatOrder(out), _matrixLayout);
      expect(out.contains('uniform sampler2D uTexture;'), isTrue);
    });

    test('has a do-not-edit header comment naming the filter', () {
      expect(out.contains(kGeneratedHeaderMarker), isTrue);
      expect(out.contains('protanopia'), isTrue);
    });
  });

  group('convertShaderToImpeller (vec2 payload shader)', () {
    late String out;

    setUpAll(() {
      out = convertShaderToImpeller(_payloadGlsl, _payloadLayout, 'myopia');
    });

    test('splits vec2 uniform body refs into vec2(name_x, name_y)', () {
      // The bare `uTexelSize` token must be gone; its scalar components remain.
      expect(RegExp(r'\buTexelSize\b').hasMatch(out), isFalse);
      expect(out.contains('vec2(uTexelSize_x, uTexelSize_y)'), isTrue);
    });

    test('emits scalar uniforms in layout order', () {
      expect(extractUniformFloatOrder(out), _payloadLayout);
    });
  });

  group('deriveLayoutFromSource', () {
    test('expands uMatrix[9] and appends the resolution pair', () {
      expect(
        deriveLayoutFromSource(_matrixGlsl, 'protanopia'),
        _matrixLayout,
      );
    });

    test('splits vec2 uniforms into _x / _y in declaration order', () {
      expect(deriveLayoutFromSource(_payloadGlsl, 'myopia'), _payloadLayout);
    });

    test('throws on an out-of-scope uniform kind (int)', () {
      const g = '''
#version 300 es
precision mediump float;
uniform sampler2D uTexture;
uniform float uStrength;
uniform int uMode;
out vec4 fragColor;
void main() { fragColor = vec4(uStrength); }
''';
      expect(
        () => deriveLayoutFromSource(g, 'glaucoma'),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('convertShaderToImpeller throws when layout drifts from the source', () {
    expect(
      () => convertShaderToImpeller(
        _payloadGlsl,
        // Missing uTexelSize components -> does not match the source layout.
        const <String>['uStrength', 'uResolution_x', 'uResolution_y'],
        'broken',
      ),
      throwsA(isA<StateError>()),
    );
  });

  group('M1: token boundaries + unknown array uniforms', () {
    // A vec2 payload uniform `uTexelSize` whose body ALSO references a longer
    // identifier `uTexelSizeScale` (a plain float). The rewrite must split the
    // bare `uTexelSize` but leave `uTexelSizeScale` byte-for-byte intact.
    const tricky = '''
#version 300 es
precision highp float;

uniform sampler2D uTexture;
uniform float uTexelSizeScale;
uniform vec2  uTexelSize;

in vec2 vTexCoord;
out vec4 fragColor;

void main() {
    vec2 uv = vTexCoord + uTexelSize * uTexelSizeScale;
    fragColor = texture(uTexture, uv);
}
''';
    const trickyLayout = <String>[
      'uTexelSizeScale',
      'uTexelSize_x',
      'uTexelSize_y',
      'uResolution_x',
      'uResolution_y',
    ];

    test('splits uTexelSize but does not corrupt uTexelSizeScale', () {
      final out = convertShaderToImpeller(tricky, trickyLayout, 'tricky');
      // The longer identifier must still appear, undamaged, in the body.
      expect(out.contains('uTexelSizeScale'), isTrue);
      expect(
        out.contains('vec2(uTexelSize_x, uTexelSize_y) * uTexelSizeScale'),
        isTrue,
        reason: 'bare uTexelSize should split; uTexelSizeScale untouched',
      );
      // No mangled `vec2(uTexelSize_x, uTexelSize_y)Scale` artefact.
      expect(out.contains('uTexelSize_y)Scale'), isFalse);
    });

    test('uResolution-prefixed identifiers in the UV rule are not over-matched',
        () {
      // The emitted UV uses uResolution_x/_y; ensure no bare `uResolution`
      // token (without suffix) leaks, and the synthetic split is exact.
      final out =
          convertShaderToImpeller(_matrixGlsl, _matrixLayout, 'protanopia');
      expect(out.contains('vec2(uResolution_x, uResolution_y)'), isTrue);
      expect(RegExp(r'\buResolution\b(?![_xy])').hasMatch(out), isFalse);
    });

    test('throws on an unknown array uniform (uKernel[5])', () {
      const g = '''
#version 300 es
precision mediump float;
uniform sampler2D uTexture;
uniform float uStrength;
uniform float uKernel[5];
in vec2 vTexCoord;
out vec4 fragColor;
void main() { fragColor = texture(uTexture, vTexCoord) * uStrength; }
''';
      // Layout matches what the source implies (so the layout guard passes and
      // we actually reach the unknown-array guard).
      const layout = <String>[
        'uStrength',
        'uKernel0', 'uKernel1', 'uKernel2', 'uKernel3', 'uKernel4',
        'uResolution_x', 'uResolution_y',
      ];
      expect(
        () => convertShaderToImpeller(g, layout, 'kernelish'),
        throwsA(isA<StateError>()),
      );
    });

    test('still accepts the known uMatrix[9] array uniform', () {
      expect(
        () => convertShaderToImpeller(_matrixGlsl, _matrixLayout, 'protanopia'),
        returnsNormally,
      );
    });
  });

  group('S3/N2: header traceability', () {
    test('stamps sensus version and the input dump path into the header', () {
      final out = convertShaderToImpeller(
        _matrixGlsl,
        _matrixLayout,
        'protanopia',
        sensusVersion: '0.5.0',
      );
      expect(out.contains('sensus-core v0.5.0'), isTrue);
      expect(out.contains('tools/sensus_shaders.g.json'), isTrue);
      expect(out.contains('sensus shaders/protanopia.frag'), isTrue);
    });

    test('falls back to "unknown" when no version is supplied', () {
      final out =
          convertShaderToImpeller(_matrixGlsl, _matrixLayout, 'protanopia');
      expect(out.contains('sensus-core vunknown'), isTrue);
    });
  });

  group('buildPubspecShadersBlock / updatePubspecShaders', () {
    test('emits alphabetically sorted entries under shaders:', () {
      final block = buildPubspecShadersBlock(<String>['myopia', 'achromatopsia']);
      expect(block, '''
  shaders:
    - shaders/achromatopsia.frag
    - shaders/myopia.frag''');
    });

    test('replaces an existing shaders block, leaving the rest intact', () {
      const pubspec = '''
name: demo
flutter:
  uses-material-design: true

  assets:
    - assets/images/

  shaders:
    - shaders/old.frag
''';
      final updated = updatePubspecShaders(pubspec, <String>['b', 'a']);
      expect(updated.contains('- shaders/old.frag'), isFalse);
      expect(updated.contains('- shaders/a.frag'), isTrue);
      expect(updated.contains('- shaders/b.frag'), isTrue);
      // The assets block must survive untouched.
      expect(updated.contains('- assets/images/'), isTrue);
      expect(updated.contains('uses-material-design: true'), isTrue);
    });

    test('inserts a shaders block when none exists yet', () {
      // No `shaders:` key at all under flutter: (initial state).
      const pubspec = '''
name: demo
flutter:
  uses-material-design: true

  assets:
    - assets/images/
''';
      final updated = updatePubspecShaders(pubspec, <String>['b', 'a']);
      expect(updated.contains('  shaders:'), isTrue);
      expect(updated.contains('    - shaders/a.frag'), isTrue);
      expect(updated.contains('    - shaders/b.frag'), isTrue);
      // Pre-existing content survives.
      expect(updated.contains('- assets/images/'), isTrue);
      expect(updated.contains('uses-material-design: true'), isTrue);
      // Re-running is idempotent (block now exists -> replaced in place).
      final again = updatePubspecShaders(updated, <String>['a', 'b']);
      expect('  shaders:'.allMatches(again).length, 1);
    });
  });

  group('generated shaders/*.frag (committed artifacts)', () {
    final fragDir = Directory('shaders');
    final fragFiles = fragDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.frag'))
        .toList();

    test('at least one .frag is generated', () {
      expect(fragFiles, isNotEmpty);
    });

    for (final f in fragFiles) {
      final name = f.uri.pathSegments.last;
      test('$name follows Impeller conventions', () {
        final src = f.readAsStringSync();
        expect(src.contains('#version'), isFalse, reason: '$name has #version');
        expect(src.contains('precision mediump float;'), isFalse,
            reason: '$name has mediump precision line');
        expect(src.contains('precision highp float;'), isFalse,
            reason: '$name has highp precision line');
        expect(src.contains('uMatrix['), isFalse,
            reason: '$name has unexpanded uMatrix[]');
        expect(src.contains(_varying), isFalse,
            reason: '$name still references the GLSL ES varying');
        expect(src.contains('#include <flutter/runtime_effect.glsl>'), isTrue,
            reason: '$name missing runtime_effect include');
      });
    }
  });

  group('layout consistency (.frag vs sensus dump)', () {
    final dumpRoot = jsonDecode(
      File('tools/sensus_shaders.g.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final dump = dumpRoot['shaders'] as List<dynamic>;

    for (final entry in dump) {
      final e = entry as Map<String, dynamic>;
      final name = e['name'] as String;
      final layout = (e['layout'] as List<dynamic>).cast<String>();
      test('$name uniform float order matches sensus layout', () {
        final src = File('shaders/$name.frag').readAsStringSync();
        expect(extractUniformFloatOrder(src), layout);
      });
    }
  });

  test('generate_shaders.dart --check reports no drift (committed in sync)', () {
    final result = Process.runSync(
      'dart',
      <String>['run', 'tools/generate_shaders.dart', '--check'],
    );
    expect(result.exitCode, 0,
        reason: 'shaders are stale; run dart run tools/generate_shaders.dart\n'
            '${result.stdout}\n${result.stderr}');
  });
}
