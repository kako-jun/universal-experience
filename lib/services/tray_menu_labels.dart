import 'package:flutter/foundation.dart';

import '../models/vision_filter_catalog.dart';

/// トレイから直接ワンクリック切替できる色覚フィルタの一覧。
///
/// 全フィルタ catalogue は設定 UI (#16) とトレイの「高度なフィルタ」サブメニュー
/// (#65) にある。トレイのトップレベルはメニューを短く保つため、よく使う色覚
/// シミュレーションのみを出す。
/// 「フィルタ解除」は専用の項目が担うため、ここには含めない。カタログ id（[kColorVisionQuickCatalogIds]）
/// で返す。
List<String> quickColorVisionFilters() => kColorVisionQuickCatalogIds;

/// トレイメニューの表示文言を 1 つにまとめた値オブジェクト (#18)。
///
/// 純粋データ層 (`buildTrayMenuSpec`) は **文言を自前で持たない**。i18n の解決は
/// UI/副作用層 (`TrayService`) の責務で、起動時ロケールの `AppLocalizations` から
/// 文字列を取り出してここに詰めて渡す（context を持てないトレイ層の作法）。
/// color-vision フィルタのラベルはキー（カタログ id または別名 id）ごとに [filterLabels] で引く。
///
/// このファイルを `tray_service.dart` から分けているのは、`l10n_extensions.dart`
/// （文言の解決）が `tray_service.dart`（統合一覧 `filter_list_selection.dart` 経由で
/// `l10n_extensions.dart` を参照する）を import する循環を避けるため。
@immutable
class TrayMenuLabels {
  const TrayMenuLabels({
    required this.showLoupe,
    required this.hideLoupe,
    required this.clearFilter,
    required this.openSettings,
    required this.quit,
    required this.filterLabels,
    required this.appModeLoupeLabel,
    required this.alwaysOnTopLabel,
    required this.clickThroughLabel,
    required this.advancedFilters,
    this.categoryLabels = const {},
    this.catalogNames = const {},
  });

  /// ルーペ窓を表示する項目のラベル（非表示状態のトグルに使う）。
  final String showLoupe;

  /// ルーペ窓を隠す項目のラベル（表示状態のトグルに使う）。
  final String hideLoupe;

  /// フィルタ解除項目のラベル。
  final String clearFilter;

  /// 起動モード切替項目のラベル（`WindowModePanel` の「ルーペモード」表記を
  /// 再利用、#63）。
  final String appModeLoupeLabel;

  /// 最前面固定切替項目のラベル（`WindowModePanel` と同じ ARB キーを再利用、#63）。
  final String alwaysOnTopLabel;

  /// クリックスルー切替項目のラベル（`WindowModePanel` と同じ ARB キーを再利用、#63）。
  final String clickThroughLabel;

  /// 設定を開く項目のラベル。
  final String openSettings;

  /// 終了項目のラベル。
  final String quit;

  /// 「高度なフィルタ」サブメニュー（カテゴリ別、#65）の見出し。
  final String advancedFilters;

  /// color-vision キー（カタログ id または別名 id）→ 表示ラベル。トップレベルのクイック項目
  /// （[quickColorVisionFilters]）と、サブメニュー内の色覚行（-omaly を含む
  /// 7 種）をカバーする。
  final Map<String, String> filterLabels;

  /// カテゴリ → サブメニュー見出し（#65）。
  final Map<VisionFilterCategory, String> categoryLabels;

  /// advanced カタログ id → 表示名（#65）。色覚クイック選択の行以外の
  /// サブメニュー項目に使う。
  final Map<String, String> catalogNames;

  /// ルーペ窓トグルのラベルを表示状態に応じて返す。
  String toggleLabel({required bool loupeVisible}) =>
      loupeVisible ? hideLoupe : showLoupe;

  /// 指定 color-vision キー（カタログ id または別名 id）のラベル（未登録ならキーをフォールバック表示）。
  String filterLabel(String key) => filterLabels[key] ?? key;

  /// カテゴリのサブメニュー見出し（未登録なら enum 名をフォールバック表示）。
  String categoryLabel(VisionFilterCategory category) =>
      categoryLabels[category] ?? category.name;

  /// 統合フィルタ一覧の 1 行のラベル。色覚クイック選択の行は [filterLabel]
  /// （-omaly を区別）、それ以外は [catalogNames]（未登録なら id）。
  String listEntryLabel({required String catalogId, String? variantId}) =>
      isColorVisionQuickKey(variantId ?? catalogId)
          ? filterLabel(variantId ?? catalogId)
          : (catalogNames[catalogId] ?? catalogId);
}
