import 'package:flutter/material.dart' show Rect;
import 'package:window_manager/window_manager.dart';

/// ルーペ矩形の決定元 (#63)。#44（対象アプリのウィンドウに自動追従するモード）で
/// 差し替えられるよう、インターフェースだけをここで切る。#44 自体の実装（自動追従）は
/// この Issue のスコープ外。
abstract class LoupeRectSource {
  /// 現在のルーペ矩形（画面座標、論理ピクセル）。取得できなければ null。
  Future<Rect?> currentRect();
}

/// 既定の実装: ルーペ窓自身の矩形（ユーザーが手動で動かす）。#44 が実装されるまでの
/// 唯一の実装。
class ManualLoupeRectSource implements LoupeRectSource {
  const ManualLoupeRectSource();

  @override
  Future<Rect?> currentRect() async {
    try {
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();
      return position & size;
    } catch (_) {
      return null;
    }
  }
}
