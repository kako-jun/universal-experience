import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'vision_filter_snapshot.dart';
import 'vision_filter_state.dart';

/// [VisionFilterState]（選択フィルタ・payload・強度・プリセット由来）を
/// [SharedPreferences] へ JSON で永続化・復元する（#65）。
///
/// [FilterService] の per-type 強度（#57）と同じ作法:
///  * 変更は 300ms デバウンスで書く（スライダーのドラッグ中に毎フレーム書かない）。
///  * 終了シーケンスは [flush] で保留分を確定させる。
///  * 書き込み失敗は握りつぶす（次回起動は既定値に戻るだけ）。
///
/// 復元は失敗しても起動を止めない: 壊れた JSON・未知の版・カタログに無い id・
/// 範囲外の値は [VisionFilterSnapshot.fromJson] が補正するか捨て、何も復元
/// できなければ state は触らない（呼び出し側が先にシードした既定のまま）。
class VisionFilterStore {
  VisionFilterStore({
    SharedPreferences? prefs,
    Duration debounce = const Duration(milliseconds: 300),
  })  : _prefs = prefs,
        _debounceDuration = debounce;

  /// 永続化キー。値はスキーマ版つきの JSON 文字列。
  static const String keySnapshot = 'settings.visionFilter';

  SharedPreferences? _prefs;
  final Duration _debounceDuration;

  VisionFilterState? _state;
  Timer? _debounce;

  /// 最後に書いた（または読んだ）JSON。変化が無い通知（原画比較の切替など）で
  /// 無駄に書き込まないための比較用。
  String? _lastJson;

  /// 保存済みの snapshot を読む。無い・壊れている・未知の版なら null。
  Future<VisionFilterSnapshot?> load() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(keySnapshot);
    if (raw == null) return null;
    try {
      final snapshot = VisionFilterSnapshot.fromJson(jsonDecode(raw));
      if (snapshot != null) _lastJson = raw;
      return snapshot;
    } catch (_) {
      // 壊れた JSON は無視して既定値のまま起動する。
      return null;
    }
  }

  /// 保存済みの内容を [state] に復元し、以後の変更を保存するよう購読する。
  ///
  /// 復元できる snapshot が無ければ [state] は変更しない。購読は復元の成否に
  /// 関わらず張る。復元済みかどうかを返す。
  Future<bool> restoreAndBind(
    VisionFilterState state, {
    bool Function(String presetId, String catalogId)? isValidPreset,
  }) async {
    final snapshot = await load();
    var restored = false;
    if (snapshot != null && !snapshot.isEmpty) {
      state.restore(snapshot, isValidPreset: isValidPreset);
      restored = true;
    }
    bind(state);
    return restored;
  }

  /// [state] の変更を購読して保存する。二重に呼んでも 1 つの state だけを購読する。
  void bind(VisionFilterState state) {
    if (identical(_state, state)) return;
    _state?.removeListener(_onChanged);
    _state = state;
    state.addListener(_onChanged);
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      _debounce = null;
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final state = _state;
    if (state == null) return;
    try {
      final json = jsonEncode(state.snapshot().toJson());
      if (json == _lastJson) return;
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      await prefs.setString(keySnapshot, json);
      _lastJson = json;
    } catch (_) {
      // 永続化の失敗は致命的ではない（次回起動は既定値へフォールバックする）。
    }
  }

  /// 保留中のデバウンス書き込みを、タイマーの発火を待たず確定させる。終了
  /// シーケンス（トレイの終了・ウィンドウクローズ・`onExitRequested`）で呼ぶ。
  /// 保留が無ければ何もしない。
  Future<void> flush() async {
    if (_debounce == null) return;
    _debounce!.cancel();
    _debounce = null;
    await _persist();
  }

  /// 購読を外す。保留中の書き込みは飛ばしてから解除する。
  Future<void> dispose() async {
    await flush();
    _state?.removeListener(_onChanged);
    _state = null;
  }
}
