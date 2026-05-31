import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';

void main() {
  group('LoupeWindowPolicy minimum size', () {
    test('minimum size is 320x240 (QVGA 4:3)', () {
      expect(LoupeWindowPolicy.minimumSize, const Size(320, 240));
    });

    test('default size is larger than minimum on both axes', () {
      expect(
        LoupeWindowPolicy.defaultSize.width,
        greaterThan(LoupeWindowPolicy.minimumSize.width),
      );
      expect(
        LoupeWindowPolicy.defaultSize.height,
        greaterThan(LoupeWindowPolicy.minimumSize.height),
      );
    });

    test('minimum size keeps a 4:3 aspect ratio', () {
      final s = LoupeWindowPolicy.minimumSize;
      expect(s.width / s.height, closeTo(4 / 3, 0.0001));
    });
  });

  group('LoupeWindowPolicy defaults', () {
    test('always-on-top is on by default', () {
      expect(LoupeWindowPolicy.defaultAlwaysOnTop, isTrue);
    });

    test('transparent background is on by default', () {
      expect(LoupeWindowPolicy.defaultTransparent, isTrue);
    });

    test('click-through is off by default (toggle-style)', () {
      expect(LoupeWindowPolicy.defaultClickThrough, isFalse);
    });
  });

  group('LoupeWindowPolicy.showFrame (frame policy)', () {
    test('normal shows a frame', () {
      expect(LoupeWindowPolicy.showFrame(LoupeWindowMode.normal), isTrue);
    });

    test('maximized still shows a frame (edge stays visible)', () {
      expect(LoupeWindowPolicy.showFrame(LoupeWindowMode.maximized), isTrue);
    });

    test('fullscreen hides the frame (immersive)', () {
      expect(LoupeWindowPolicy.showFrame(LoupeWindowMode.fullscreen), isFalse);
    });
  });

  group('LoupeWindowPolicy.resolveMode (state transitions)', () {
    test('restore always returns to normal', () {
      for (final m in LoupeWindowMode.values) {
        expect(
          LoupeWindowPolicy.resolveMode(m, LoupeWindowAction.restore),
          LoupeWindowMode.normal,
        );
      }
    });

    test('toggleMaximize: normal -> maximized', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.normal,
          LoupeWindowAction.toggleMaximize,
        ),
        LoupeWindowMode.maximized,
      );
    });

    test('toggleMaximize: maximized -> normal (back)', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.maximized,
          LoupeWindowAction.toggleMaximize,
        ),
        LoupeWindowMode.normal,
      );
    });

    test('toggleMaximize from fullscreen goes to maximized', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.fullscreen,
          LoupeWindowAction.toggleMaximize,
        ),
        LoupeWindowMode.maximized,
      );
    });

    test('toggleFullscreen: normal -> fullscreen', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.normal,
          LoupeWindowAction.toggleFullscreen,
        ),
        LoupeWindowMode.fullscreen,
      );
    });

    test('toggleFullscreen: fullscreen -> normal (back)', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.fullscreen,
          LoupeWindowAction.toggleFullscreen,
        ),
        LoupeWindowMode.normal,
      );
    });

    test('toggleFullscreen from maximized goes to fullscreen', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.maximized,
          LoupeWindowAction.toggleFullscreen,
        ),
        LoupeWindowMode.fullscreen,
      );
    });
  });
}
