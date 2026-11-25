import 'package:flutter/gestures.dart' show GestureBinding;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/experience_source.dart';
import '../../services/settings_service.dart'
    show dismissWelcomeBannerOnUserChange;
import '../../services/vision_filter_metadata.dart';
import '../../services/vision_filter_state.dart';
import '../../src/rust/api/sensus_bridge.dart';

// 供給源の seam と検証は services 層にある（main.dart が widget を import せず
// 済むように移した）。既存の import 経路を変えないよう再公開する。
export '../../services/experience_source.dart';

/// 体験プリセットのドロップダウン（[ExperiencePresetPicker]）を指す [Key]。
const Key experiencePresetDropdownKey = ValueKey('experience_preset_dropdown');

/// ドロップダウンを開いたメニューの中の、体験プリセット 1 件の項目を一意に指す [Key]。
///
/// テストが表示名の文字列（ロケール依存）ではなく experience id で安定して項目を
/// 見つけられるようにするための公開ヘルパ（#60）。メニューを開いている間だけ存在する
/// （閉じているときのボタンの表示には付けない）。
Key experienceCardKey(String experienceId) =>
    ValueKey('experience_card_$experienceId');

/// [experience] の escalation を [Experience.vision] から取得する（#76）。
/// Experience 自体は urgency_escalation を持たないため、視覚フィルタの
/// escalation をそのまま使う。vision を持たない体験は現状無いが、無い場合は
/// 空リスト（喚起なし）にする。
List<UrgencyEscalation> _escalationFor(Experience experience) =>
    experience.vision == null
        ? const <UrgencyEscalation>[]
        : visionFilterUrgencyEscalationProvider(experience.vision!);

/// 体験プリセット [experience] の受診喚起。`Experience.urgency`（聴覚症状を含む
/// 体験全体の緊急度）と、視覚フィルタから取得した escalation を
/// [resolveConsultNotice] でまとめる（`FilterParamPanel`・export と共有する
/// 唯一の解決経路）。喚起が無ければ null。
///
/// 右カラムの調整パネル（`AdjustPanel`、#72）が、体験プリセットを選んでいる間の
/// 喚起としてこれを使う（視覚フィルタ単体の緊急度ではなく体験としての緊急度）。
ConsultNotice? experienceConsultNotice(
  AppLocalizations l10n,
  Experience experience,
) =>
    resolveConsultNotice(l10n, experience.urgency, _escalationFor(experience));

/// 選択中の体験プリセット（[VisionFilterState.selectedPresetId]）に対応する
/// [Experience]。プリセット選択中でなければ null。
Experience? selectedExperience(VisionFilterState state) {
  final id = state.selectedPresetId;
  if (id == null) return null;
  for (final exp in availableExperiences()) {
    if (exp.id == id) return exp;
  }
  return null;
}

/// 体験プリセット (#19) の選択欄。左カラム「選ぶ」（`FilterBrowser`）の一番上に置く
/// ドロップダウン（#199）。
///
/// sensus の [experiences]（いまは meniere / bppv / vestibular_neuritis /
/// labyrinthitis の 4 体験）を、選ぶだけで「下のフィルタ・強度・パラメータをまとめて
/// 切り替える」入口にする。**件数は固定しない**: 選択肢は [availableExperiences] を
/// そのまま並べるので、sensus に体験が増えればここにも増える（多いときはメニューが
/// スクロールする。表示名は `experienceName` が ARB から引き、未登録の id は id のまま出す）。
/// 体験が 0 件なら何も出さない。
///
/// - 視覚: `Experience.vision`（bridge の [VisionFilter]）を [visionFilterCatalogId]
///   でカタログ id（snake_case）へ写し、[VisionFilterState.selectPreset] に渡す
///   （層の集合はそのプリセット単体へ置き換わり、強度・パラメータは推奨値になる。一覧の
///   チェック・プレビュー・調整パネル・トレイは [VisionFilterState] の選択だけを見るので、
///   選んだ結果がそのまま下の設定に反映される）。id をハードコードせずカタログを正本に引く。
/// - 選択表示: meniere と labyrinthitis はどちらもカタログ id `vertigo` に写る
///   ため、選択表示はカタログ id ではなく [VisionFilterState.selectedPresetId]
///   （`Experience.id`）で比較する（#60）。プリセットを選んだあとでフィルタを足し引き
///   すると選択は外れ（[VisionFilterState] の仕様）、表示は「プリセットなし」へ戻る。
/// - 説明・受診喚起・聴覚症状の注記は、選んだあと右カラム（`AdjustPanel`）に出す（#72）。
/// - 聴覚: hearing を含む体験（meniere / labyrinthitis）は右カラムの注記に留める。
///   **音声再生は非スコープ**（聴覚モード設計に委ねる）。音は鳴らさない。
///
/// 文言は持たず、id / 分類から i18n で解決する（規律2）。
class ExperiencePresetPicker extends StatefulWidget {
  const ExperiencePresetPicker({super.key, this.onActivated});

  /// **ポインタで**選んだ直後に呼ばれる（一覧の行と同じ扱い。画面がショートカットの
  /// 受け口へフォーカスを戻し、続く ←→ で強度を動かせるようにする）。キーボード
  /// （Enter/Space）で選んだときは呼ばれず、フォーカスはドロップダウンに残る
  /// （次の Tab が先頭からやり直しにならないようにする）。
  ///
  /// どちらで選んだかは、**メニューの項目を確定した入力**で決まる（開いたときの入力ではない）:
  /// マウスで開いて ↑↓ Enter で選べばキーボード、Enter で開いてクリックで選べばポインタ。
  final VoidCallback? onActivated;

  @override
  State<ExperiencePresetPicker> createState() => _ExperiencePresetPickerState();
}

class _ExperiencePresetPickerState extends State<ExperiencePresetPicker> {
  /// 直近の入力がポインタ（押下）か。キーを押したら false に戻す。
  ///
  /// 開いたメニューは別のルート（オーバーレイ）に出るので、このウィジェットの子孫の
  /// `Listener` / `Focus` ではメニューの中のクリック・キー操作を拾えない。アプリ全体の入力
  /// （[HardwareKeyboard] のハンドラと、ポインタのグローバルルート）を見て、項目を確定した
  /// 入力の種類を知る。イベントは消費しない（見るだけ）。
  bool _lastInputWasPointer = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointer);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent) _lastInputWasPointer = false;
    return false;
  }

  void _handlePointer(PointerEvent event) {
    if (event is PointerDownEvent) _lastInputWasPointer = true;
  }

  /// 体験の視覚フィルタが写るカタログ id。視覚フィルタが無い・カタログに無いなら null。
  static String? _catalogIdOf(Experience experience) {
    final vision = experience.vision;
    return vision == null ? null : visionFilterCatalogId(vision);
  }

  @override
  Widget build(BuildContext context) {
    final experiences = availableExperiences();
    if (experiences.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = context.watch<VisionFilterState>();
    // #60: カタログ id ではなく experience id で比較する。一覧に無い id（古い保存値など）は
    // 未選択として扱う（DropdownButton は items に無い value を受け付けない）。
    final selectedId = state.selectedPresetId;
    final value =
        experiences.any((e) => e.id == selectedId) ? selectedId : null;
    return KeyedSubtree(
      key: experiencePresetDropdownKey,
      child: _dropdown(context, l10n, theme, experiences, value),
    );
  }

  Widget _dropdown(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    List<Experience> experiences,
    String? value,
  ) {
    return DropdownButtonFormField<String>(
      // 選択は VisionFilterState が正本。外から変わった値（フィルタの足し引きでプリセットが
      // 外れる等）には、DropdownButtonFormField が initialValue の変化を見て追従する
      // （didUpdateWidget で setValue）。値ごとに key を変えて作り直さないこと: 作り直すと
      // ドロップダウンのフォーカスノードが捨てられ、キーボードで選んだ直後にフォーカスが
      // 外へ飛ぶ（次の Tab が先頭からやり直しになる）。
      initialValue: value,
      isExpanded: true,
      // 長い名前（英語）は、メニューの中では折り返して全文を出す。
      itemHeight: null,
      menuMaxHeight: 480,
      decoration: InputDecoration(
        labelText: l10n.experienceSectionTitle,
        helperText: l10n.experiencePresetHelper,
        helperMaxLines: 4,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      hint: Text(
        l10n.experiencePresetNone,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      // 閉じているときの表示は 1 行（入りきらなければ省略）。
      selectedItemBuilder: (context) => [
        for (final exp in experiences)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              experienceName(l10n, exp.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      items: [
        for (final exp in experiences)
          DropdownMenuItem<String>(
            value: exp.id,
            // 視覚フィルタを持つ体験のみ適用可能（いまの 4 体験はすべて vision を持つ）。
            enabled: _catalogIdOf(exp) != null,
            child: Padding(
              key: experienceCardKey(exp.id),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(experienceName(l10n, exp.id)),
            ),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        for (final exp in experiences) {
          if (exp.id != id) continue;
          final catalogId = _catalogIdOf(exp);
          if (catalogId == null) return;
          context.read<VisionFilterState>().selectPreset(exp.id, catalogId);
          dismissWelcomeBannerOnUserChange(context);
          if (_lastInputWasPointer) widget.onActivated?.call();
          return;
        }
      },
    );
  }
}
