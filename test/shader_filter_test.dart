import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/rendering/shader_filter.dart';

/// [SingleFlightCache] の単体テスト（#58 レビュー S1）。
///
/// `ShaderFilter._loadProgram` は元々 `Map<String, Future<ui.FragmentProgram>>
/// ??=` という素朴なキャッシュを使っていたため、一度失敗した Future を
/// 永久にキャッシュしてしまい、以後のすべての呼び出しが同じ失敗を再生する
/// だけになっていた（asset ロードの一時的な失敗が回復不能になる）。
///
/// `ui.FragmentProgram.fromAsset` は実 engine 依存で `flutter test` から任意に
/// 失敗させられないため、汎用化した [SingleFlightCache]（ShaderFilter が実際に
/// 使っているのと同じキャッシュ実装）を `int`/`String` などの平易な型で直接
/// 検証する。
void main() {
  group('SingleFlightCache (#58 レビュー S1)', () {
    test('成功した Future はキャッシュされ、create は1回しか呼ばれない', () async {
      final cache = SingleFlightCache<String, int>();
      var callCount = 0;
      Future<int> create() async {
        callCount++;
        return 42;
      }

      expect(await cache.get('k', create), 42);
      expect(await cache.get('k', create), 42);
      expect(callCount, 1);
      expect(cache.debugLength, 1);
    });

    test('失敗した Future はキャッシュに残らず、次回呼び出しで再試行される', () async {
      final cache = SingleFlightCache<String, int>();
      var callCount = 0;
      Future<int> create() {
        callCount++;
        if (callCount == 1) {
          return Future<int>.error(StateError('boom'));
        }
        return Future.value(42);
      }

      await expectLater(
        cache.get('k', create),
        throwsA(isA<StateError>()),
      );
      // 失敗が非同期に伝播してキャッシュから剥がれるまで1回 microtask を待つ。
      await Future<void>.delayed(Duration.zero);
      expect(cache.debugLength, 0, reason: '失敗した Future をキャッシュに残してはいけない');

      expect(await cache.get('k', create), 42);
      expect(callCount, 2, reason: '前回失敗しているので create が再度呼ばれるべき');
      expect(cache.debugLength, 1);
    });

    test('同時に呼んだ2回は同じ Future を共有する（重複ロードを避ける）', () async {
      final cache = SingleFlightCache<String, int>();
      var callCount = 0;
      Future<int> create() async {
        callCount++;
        return 42;
      }

      final f1 = cache.get('k', create);
      final f2 = cache.get('k', create);
      expect(identical(f1, f2), isTrue);
      await Future.wait([f1, f2]);
      expect(callCount, 1);
    });

    test('異なるキーは独立してキャッシュされる', () async {
      final cache = SingleFlightCache<String, int>();
      final callCounts = <String, int>{};
      Future<int> create(String key) async {
        callCounts[key] = (callCounts[key] ?? 0) + 1;
        return key.length;
      }

      expect(await cache.get('a', () => create('a')), 1);
      expect(await cache.get('bb', () => create('bb')), 2);
      expect(cache.debugLength, 2);
    });
  });
}
