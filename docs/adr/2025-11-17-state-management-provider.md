# ADR: 状態管理に Provider を採用

- **決定日**: 2025-11-17（初期実装時。Provider 依存と `FilterService`（ChangeNotifier）
  はこの時点で導入されている）
- **記録日**: 2026-06-21（ADR 化）
- **ステータス**: Accepted

## 文脈（問題）

ue は Flutter（Dart）アプリで、フィルタの選択状態・強度・有効/無効を UI 全体で
共有する必要がある。フィルタを選択・調整すると、関係するウィジェット
（`FilterSelector` / `IntensitySlider` / `HomeScreen` 等）が再描画される。

このアプリ規模の状態を、どの状態管理手法で持つかを決める必要があった。

## 決定

**状態管理に Provider を採用する**（`pubspec.yaml`: `provider: ^6.1.1`）。

- `FilterService` を `ChangeNotifier` として実装し、選択・強度変更で
  `notifyListeners()` する。
- UI 側は `Consumer<FilterService>` 等で購読し、`notifyListeners()` で再描画する
  （`docs/ARCHITECTURE.md`「状態管理フロー」）。

## 代替案

- **Riverpod** — Provider の後継的存在で、コンパイル時安全・プロバイダの依存解決が強い。
  却下（当面）: 本アプリ規模では Provider で十分で、学習コストが低い。
- **Bloc / Redux 等** — イベント駆動・厳格な単方向データフロー。却下: このアプリの
  状態（選択フィルタ + 強度 + 有効フラグ）に対して過剰で、ボイラープレートが増える。
- **setState のみ（状態管理ライブラリ無し）** — 却下: 複数ウィジェットで共有する
  状態を素の setState で回すと、状態の持ち回り（lifting state up）が煩雑になる。

## 根拠

> 出典は `CLAUDE.md`「設計判断 / Provider選定」の 3 点に接地する。

- **Flutter チーム推奨**の状態管理手法である。
- **シンプルで学習コストが低い**。
- 将来的に **Riverpod へ移行可能**（Provider → Riverpod は移行パスがある）。

## 結果・トレードオフ

- `FilterService`（ChangeNotifier）が状態の単一の持ち場になり、UI は購読するだけの
  純粋な表示に保てる。#13 の sensus 一元化後も `FilterService` は選択状態モデル
  （`currentFilter` / `intensity` / `isActive`）として Provider 経路のまま残っている。
- **トレードオフ**: Provider はコンパイル時の依存解決保証が Riverpod ほど強くない。
  状態が複雑化したら Riverpod 移行を検討する（移行可能性を残す前提で採用している）。

## 関連 Issue・PR・docs

- `CLAUDE.md`「設計判断 / Provider選定」（本 ADR の元記述）
- `docs/ARCHITECTURE.md`「状態管理フロー」「Business Logic Layer」
- `pubspec.yaml`（`provider: ^6.1.1`）／`lib/services/filter_service.dart`
