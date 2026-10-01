import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vision_filter_catalog.dart';
import 'vision_filter_snapshot.dart';
import 'vision_filter_state.dart';
import 'vision_layer.dart';

/// [VisionFilterState]（選択フィルタ・payload・強度・プリセット由来）を
/// [SharedPreferences] へ JSON で永続化・復元する（#65）。
///
/// 選択状態の保存先はここ 1 つ（v2 の `settings.visionFilter`、#117, #124）。かつて
/// 色覚専用の選択サービス / `SettingsService` が持っていた `settings.filterType`（最後に選んだ
/// 色覚）と `settings.intensityByType`（per-type 強度）、版 1 の `settings.visionFilter`
/// は、起動時に [migrateLegacySettings] が一度だけ v2 へ取り込んで捨てる。保存の作法:
///  * 変更は 300ms デバウンスで書く（スライダーのドラッグ中に毎フレーム書かない）。
///  * 終了シーケンスは [flush] で保留分を確定させる。
///  * 書き込み失敗は握りつぶす（次回起動は既定値に戻るだけ）。
///
/// 復元は失敗しても起動を止めない: 壊れた JSON・未知の版・カタログに無い id・
/// 範囲外の値は [VisionFilterSnapshot.fromJson] が補正するか捨て、何も復元
/// できなければ state は触らない（呼び出し側が先に入れた初回起動の層のまま）。
class VisionFilterStore {
  VisionFilterStore({
    SharedPreferences? prefs,
    Duration debounce = const Duration(milliseconds: 300),
  })  : _prefs = prefs,
        _debounceDuration = debounce;

  /// 永続化キー。値はスキーマ版つきの JSON 文字列。
  static const String keySnapshot = 'settings.visionFilter';

  /// かつて `SettingsService` が持っていた「最後に選んだ色覚」の保存キー（旧 enum の名前の
  /// 文字列。`none` は「何も選んでいない」）。[migrateLegacySettings] だけが読み、取り込みに
  /// 成功したら消す。
  static const String keyLegacyFilterType = 'settings.filterType';

  /// かつて色覚専用の選択サービスが持っていた per-type 強度の保存キー（JSON オブジェクト。
  /// 例: `{"protanomaly":0.6,"protanopia":1.0}`）。[migrateLegacySettings] だけが
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

  /// 旧い保存（`settings.filterType`・`settings.intensityByType`・版 1 の
  /// `settings.visionFilter`）を v2 の [keySnapshot] へ一度だけ取り込む（#117, #124）。
  /// 起動時、初回起動の層（[VisionFilterState.seedInitialLayers]）の**後**・
  /// [restoreAndBind] の**前**に呼ぶ。
  ///
  /// 取り込みの要否は、旧キーが残っているか（[keyLegacyFilterType]・[keyIntensityByType]）と、
  /// [keySnapshot] が版 1 か、で決まる。どれも無ければ何もしない（null を返す）。
  ///  * 読める v2 が有る: v2 を正本とし、v2 に無い強度のキーだけを旧 per-type 強度から足す
  ///    （v2 の値を優先する）。[keyLegacyFilterType] は読まずに捨てる。
  ///  * 読める v2 が無い（無い・版 1・壊れている）: 版 1 に選択があればそれを層にし、旧
  ///    per-type 強度（有効な色覚キー・0..1 に clamp）を重ねる。版 1 が無い・壊れている・
  ///    空なら、層は旧 [keyLegacyFilterType] の色覚 1 つ（`none` なら層なし。キーが
  ///    無いときは初回起動の層と同じ [kInitialVisionFilterKey]）。
  ///
  /// 結果を v2 として [keySnapshot] へ書き、**書き込みに成功してから**旧キーを消す。
  /// 失敗しても起動は止めない: 書き込みの失敗なら旧キーを残し（次回起動でもう一度取り込む）
  /// 取り込み済みの内容を返す。それ以外の例外は null を返す。その後の [restoreAndBind] が
  /// [load] し直すので、ディスク上に読める保存があればそれが復元され、なければ呼び出し側が
  /// 先に入れた既定の層のまま起動する。
  ///
  /// 戻り値は取り込み後の snapshot。[restoreAndBind] の `snapshot:` に渡せばメモリへ反映される。
  /// 旧単一キー [legacyIntensityKey] は、常に値を見ず消す。
  Future<VisionFilterSnapshot?> migrateLegacySettings() async {
    try {
      return await _migrateLegacySettings();
    } catch (error, stack) {
      debugPrint(
        'VisionFilterStore: legacy settings migration failed: '
        '$error\n$stack',
      );
      return null;
    }
  }

  Future<VisionFilterSnapshot?> _migrateLegacySettings() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    try {
      await prefs.remove(legacyIntensityKey);
    } catch (_) {
      // 掃除の失敗は無視する。
    }

    VisionFilterSnapshot? stored;
    try {
      final raw = prefs.getString(keySnapshot);
      if (raw != null) stored = VisionFilterSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      stored = null; // 壊れた保存は「読める v2 が無い」扱い。
    }

    final hasLegacyType = prefs.containsKey(keyLegacyFilterType);
    final hasLegacyIntensity = prefs.containsKey(keyIntensityByType);
    final storedIsV1 = stored != null && stored.fromLegacy;
    if (!hasLegacyType && !hasLegacyIntensity && !storedIsV1) return null;

    final legacy = _readLegacyIntensities(prefs);

    final VisionFilterSnapshot result;
    if (stored != null && !stored.fromLegacy) {
      // 読める v2 が正本。無い強度のキーだけ旧 per-type 強度で補う。
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
      // 版 1（あれば）に旧 per-type 強度を重ねる。
      final v1 = stored != null && !stored.isEmpty ? stored : null;
      final seed = v1 == null ? _legacyTypeLayer(prefs) : null;
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
        await prefs.remove(keyLegacyFilterType);
        await prefs.remove(keyIntensityByType);
      }
    } catch (error) {
      // 書けなければ旧キーを残す（次回起動でもう一度取り込む）。
      debugPrint('VisionFilterStore: legacy settings not saved: $error');
    }
    return result;
  }

  /// 旧 [keyLegacyFilterType] が指していた色覚の層。`none`・読めない値は層なし（null）。
  /// キー自体が無いときは初回起動の層（[kInitialVisionFilterKey]）。
  VisionLayer? _legacyTypeLayer(SharedPreferences prefs) {
    final String? key;
    if (prefs.containsKey(keyLegacyFilterType)) {
      final raw = prefs.get(keyLegacyFilterType);
      key = raw is String && isColorVisionQuickKey(raw) ? raw : null;
    } else {
      key = kInitialVisionFilterKey;
    }
    if (key == null) return null;
    final target = resolveVisionKey(key)!;
    return VisionLayer(id: target.id, variantId: target.variantId);
  }

  /// 旧 per-type 強度を（別名 id ?? カタログ id）→ 0..1 の写像として読む。壊れた JSON・
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
            isColorVisionQuickKey(key) &&
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
  /// [snapshot] を渡すとそれを復元し（[migrateLegacySettings] の結果用。書き込みが
  /// 失敗していてもメモリへ反映するため）、渡さなければ [load] で読む。復元できる
  /// snapshot が無い・復元が例外で失敗したときは [state] は変更しない（後者は
  /// [VisionFilterState.restore] が巻き戻す）。購読は復元の成否に関わらず張る。
  /// 空の版 1 は復元しない（何も運んでこない）が、空の v2 は「未選択で終了した」
  /// 状態として復元する。例外として、-opia の強度だけを持つ版 1 は変換後には何も
  /// 運ばないが、[VisionFilterSnapshot.legacyHadContent] により非空として復元する
  /// （旧実装の挙動を保つ。先に入れた初回起動の層は解除される）。復元済みかどうかを返す。
  Future<bool> restoreAndBind(
    VisionFilterState state, {
    bool Function(String presetId, String catalogId)? isValidPreset,
    VisionFilterSnapshot? snapshot,
  }) async {
    snapshot ??= await load();
    var restored = false;
    // 読める v2 は空でも復元する（「何も選ばずに終了した」が正本で、初回起動の層より
    // 優先される）。空なのは版 1 だけ無視する（何も運んでこない）。ただし
    // -opia の強度だけの版 1 は legacyHadContent で isEmpty が false になり、復元する。
    if (snapshot != null && (!snapshot.isEmpty || !snapshot.fromLegacy)) {
      try {
        state.restore(snapshot, isValidPreset: isValidPreset);
        restored = true;
      } catch (error, stack) {
        // 復元中の例外（sensus 呼び出しの失敗など）は起動を止めない。
        // [VisionFilterState.restore] が呼び出し前の状態へ巻き戻すので、
        // 呼び出し側が先に入れた初回起動の層のまま起動し、以後の保存だけ始める。
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
