import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/disability_type.dart';
import 'vision_filter_snapshot.dart';
import 'vision_filter_state.dart';
import 'vision_layer.dart';

/// [VisionFilterState]（選択フィルタ・payload・強度・プリセット由来）を
/// [SharedPreferences] へ JSON で永続化・復元する（#65）。
///
/// 強度の保存先はここ 1 つ（v2 の `strengthByKey`、#117）。かつて `FilterService` が
/// `settings.intensityByType` に持っていた per-type 強度は、起動時に
/// [migrateLegacyStrengths] が一度だけ取り込んで捨てる。保存の作法は従来の
/// `FilterService` と同じ:
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

  /// かつて `FilterService` が持っていた per-type 強度の保存キー（JSON オブジェクト。
  /// 例: `{"protanomaly":0.6,"protanopia":1.0}`）。[migrateLegacyStrengths] だけが
  /// 読み、取り込みに成功したら消す。
  static const String keyIntensityByType = 'settings.intensityByType';

  /// さらに古い単一 intensity キー（#17、#57 で撤去）。移行せず、残っていれば消すだけ。
  static const String legacyIntensityKey = 'settings.intensity';

  SharedPreferences? _prefs;
  final Duration _debounceDuration;

  VisionFilterState? _state;
  Timer? _debounce;

  /// 実行中の書き込み。[flush] が、タイマー発火後にすでに走っている書き込み
  /// （`_debounce` は発火時に null になる）の完了も待てるよう保持する。
  Future<void>? _writing;

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

  /// 旧 per-type 強度（[keyIntensityByType]）を v2 の `strengthByKey` へ一度だけ取り込む
  /// （#117）。起動時、色覚シードと [restoreAndBind] の**前**に呼ぶ。
  ///
  /// 取り込みの要否は [keyIntensityByType] の有無で決まる:
  ///  * (a) 有り・読める v2 が無い（無い・版 1・壊れている）: 版 1 の強度（-opia 4 種を
  ///    除く）で記憶を初期化し、旧 per-type 強度（有効な色覚型名・0..1 に clamp）を
  ///    上書きで重ねる。版 1 が無い・壊れている・空なら、層は [seedType] の quick 層
  ///    1 つ（none なら層なし）。版 1 に選択があればそれを層にする。結果を v2 として
  ///    [keySnapshot] へ書き、**書き込みに成功してから** [keyIntensityByType] を消す。
  ///  * (b) 有り・読める v2 が有る: v2 に無いキーだけを旧 per-type 強度から足して書き、
  ///    [keyIntensityByType] を消す（v2 の値を優先する）。
  ///  * (c) 無し: 何もしない（null を返す。版 1 だけの保存は [restoreAndBind] の
  ///    [VisionFilterSnapshot.fromJson] が読む）。
  ///
  /// 戻り値は取り込み後の snapshot（(c) は null）。**書き込みが失敗しても**戻り値は
  /// 取り込み済みの内容なので、[restoreAndBind] の `snapshot:` に渡せばメモリへは
  /// 反映される（旧キーは残り、次回起動でもう一度取り込む）。旧単一キー
  /// [legacyIntensityKey] は、常に値を見ず消す。
  Future<VisionFilterSnapshot?> migrateLegacyStrengths({
    required ColorVisionType seedType,
  }) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    try {
      await prefs.remove(legacyIntensityKey);
    } catch (_) {
      // 掃除の失敗は無視する。
    }
    if (!prefs.containsKey(keyIntensityByType)) return null; // (c)

    final legacy = _readLegacyIntensities(prefs);

    VisionFilterSnapshot? stored;
    try {
      final raw = prefs.getString(keySnapshot);
      if (raw != null) stored = VisionFilterSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      stored = null; // 壊れた保存は「読める v2 が無い」扱い。
    }

    final VisionFilterSnapshot result;
    if (stored != null && !stored.fromLegacy) {
      // (b) v2 の値を優先し、無いキーだけ旧 per-type 強度で補う。
      result = VisionFilterSnapshot(
        layers: stored.layers,
        focusedId: stored.focusedId,
        presetId: stored.presetId,
        strengthByKey: {
          ...legacy,
          ...stored.strengthByKey,
        },
        paramsById: stored.paramsById,
      );
    } else {
      // (a) 版 1（あれば）に旧 per-type 強度を重ねる。
      final v1 = stored != null && !stored.isEmpty ? stored : null;
      final seed = v1 == null ? quickColorVisionLayer(seedType) : null;
      result = VisionFilterSnapshot(
        layers: v1?.layers ?? (seed == null ? const [] : [seed]),
        focusedId: v1?.focusedId ?? seed?.id,
        presetId: v1?.presetId,
        strengthByKey: {
          ...?v1?.strengthByKey,
          ...legacy,
        },
        paramsById: v1?.paramsById ?? const {},
      );
    }

    try {
      final json = jsonEncode(result.toJson());
      final written = await prefs.setString(keySnapshot, json);
      if (written) {
        _lastJson = json;
        await prefs.remove(keyIntensityByType);
      }
    } catch (error) {
      // 書けなければ旧キーを残す（次回起動でもう一度取り込む）。
      debugPrint(
          'VisionFilterStore: legacy strength migration not saved: $error');
    }
    return result;
  }

  /// 旧 per-type 強度を `ColorVisionType.name` → 0..1 の写像として読む。壊れた JSON・
  /// 型違い・未知の型名・非有限値は捨てる。
  Map<String, double> _readLegacyIntensities(SharedPreferences prefs) {
    final out = <String, double>{};
    try {
      final raw = prefs.getString(keyIntensityByType);
      if (raw == null) return out;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return out;
      for (final e in decoded.entries) {
        final key = e.key;
        final v = e.value;
        if (key is String &&
            colorVisionTypeByName(key) != null &&
            v is num &&
            v.isFinite) {
          out[key] = v.toDouble().clamp(0.0, 1.0);
        }
      }
    } catch (_) {
      // 壊れた JSON は空として扱う。
    }
    return out;
  }

  /// 保存済みの内容を [state] に復元し、以後の変更を保存するよう購読する。
  ///
  /// [snapshot] を渡すとそれを復元し（[migrateLegacyStrengths] の結果用。書き込みが
  /// 失敗していてもメモリへ反映するため）、渡さなければ [load] で読む。復元できる
  /// snapshot が無い・復元が例外で失敗したときは [state] は変更しない（後者は
  /// [VisionFilterState.restore] が巻き戻す）。購読は復元の成否に関わらず張る。
  /// 空の版 1 は復元しない（何も運んでこない）が、空の v2 は「未選択で終了した」
  /// 状態として復元する。復元済みかどうかを返す。
  Future<bool> restoreAndBind(
    VisionFilterState state, {
    bool Function(String presetId, String catalogId)? isValidPreset,
    VisionFilterSnapshot? snapshot,
  }) async {
    snapshot ??= await load();
    var restored = false;
    // 読める v2 は空でも復元する（「何も選ばずに終了した」が正本で、設定側の色覚
    // シードより優先される）。空なのは版 1 だけ無視する（何も運んでこない）。
    if (snapshot != null && (!snapshot.isEmpty || !snapshot.fromLegacy)) {
      try {
        state.restore(snapshot, isValidPreset: isValidPreset);
        restored = true;
      } catch (error, stack) {
        // 復元中の例外（sensus 呼び出しの失敗など）は起動を止めない。
        // [VisionFilterState.restore] が呼び出し前の状態へ巻き戻すので、
        // 呼び出し側がシードした既定のまま起動し、以後の保存だけ始める。
        debugPrint('VisionFilterStore: restore failed: $error\n$stack');
      }
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
      unawaited(_persistTracked());
    });
  }

  /// [_persist] を実行し、その Future を [_writing] に保持する（完了で解除）。
  Future<void> _persistTracked() {
    final write = _persist();
    _writing = write;
    return write.whenComplete(() {
      if (identical(_writing, write)) _writing = null;
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
  /// すでに走っている書き込みがあればその完了も待つ（タイマー発火直後に終了が
  /// 来ても、書き込み途中でプロセスが終わらない）。保留も実行中も無ければ何もしない。
  Future<void> flush() async {
    // 先に実行中の書き込みを待つ（古い書き込みと新しい書き込みが競合しない）。
    await _writing;
    final pending = _debounce;
    if (pending != null) {
      pending.cancel();
      _debounce = null;
      await _persistTracked();
    }
    // 待っている間にタイマーが発火して始まった書き込みも待つ。
    await _writing;
  }

  /// 購読を外す。保留中の書き込みは飛ばしてから解除する。
  Future<void> dispose() async {
    await flush();
    _state?.removeListener(_onChanged);
    _state = null;
  }
}
