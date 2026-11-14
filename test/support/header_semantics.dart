// プレビューの見出し行は廃止し、見えない `Semantics(header)` だけが残る（#183）。
// その見出しを探す finder。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Finder headerSemantics(String label) => find.byWidgetPredicate((w) =>
    w is Semantics &&
    w.properties.header == true &&
    w.properties.label == label);
