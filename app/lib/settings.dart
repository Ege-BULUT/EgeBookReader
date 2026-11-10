import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sources.dart';

enum PaperTheme { paper, parchment, oled, eink }

enum TurnMode { flip, tap, scroll }

/// Colours of one theme in one brightness. Contrast is worked out in memory/research/fonts-design.md.
class Palette {
  const Palette(this.paper, this.ink, this.muted, this.grain);
  final Color paper, ink, muted;
  final double grain;

  bool get isDark => paper.computeLuminance() < 0.2;
  Color get accent => isDark ? const Color(0xFFD98B6A) : const Color(0xFFA8492F);
  Color get surface => Color.lerp(paper, isDark ? Colors.white : Colors.black, isDark ? 0.08 : 0.05)!;
  Color get line => ink.withValues(alpha: 0.14);
}

const palettes = <(PaperTheme, bool), Palette>{
  (PaperTheme.paper, false): Palette(Color(0xFFF7F4EE), Color(0xFF2A2622), Color(0xFF5E574E), 0.25),
  (PaperTheme.paper, true): Palette(Color(0xFF1C1B19), Color(0xFFDAD4C8), Color(0xFFA39C90), 0.25),
  (PaperTheme.parchment, false): Palette(Color(0xFFF0E2C2), Color(0xFF3A2E20), Color(0xFF6B5A43), 0.7),
  (PaperTheme.parchment, true): Palette(Color(0xFF2A2219), Color(0xFFE2D2B2), Color(0xFFAD9C7E), 0.6),
  (PaperTheme.oled, false): Palette(Color(0xFFFFFFFF), Color(0xFF1A1A1A), Color(0xFF5C5C5C), 0),
  (PaperTheme.oled, true): Palette(Color(0xFF000000), Color(0xFFCCCCCC), Color(0xFF8C8C8C), 0),
  (PaperTheme.eink, false): Palette(Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFF000000), 0),
  (PaperTheme.eink, true): Palette(Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFFFFFFF), 0),
};

class Settings extends ChangeNotifier {
  PaperTheme theme = PaperTheme.paper;
  bool dark = false;
  TurnMode mode = TurnMode.flip;
  double scrollGap = 2;
  double fontSize = 18;
  double lineHeight = 1.5;
  String fontFamily = 'serif';
  bool bold = false, italic = false;
  bool volumeKeys = true, invertVolume = false;
  bool reflow = false;
  bool actualBook = false;

  Palette get palette => palettes[(theme, dark)]!;
  bool get isEink => theme == PaperTheme.eink;

  /// E-ink panels get no filters at all, whatever else is on.
  bool get bookFilters => actualBook && !isEink;

  PageStyle get pageStyle => PageStyle(
        paper: palette.paper,
        ink: palette.ink,
        fontSize: fontSize,
        lineHeight: lineHeight,
        fontFamily: fontFamily,
        bold: bold || isEink,
        italic: italic,
        grain: isEink ? 0 : (palette.grain + (actualBook ? 0.35 : 0)).clamp(0, 1),
        actualBook: bookFilters,
      );

  late final File _file;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'settings.json'));
    if (!_file.existsSync()) return;
    try {
      final j = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      theme = PaperTheme.values.byName(j['theme'] as String);
      dark = j['dark'] as bool;
      mode = TurnMode.values.byName(j['mode'] as String);
      scrollGap = (j['scrollGap'] as num).toDouble();
      fontSize = (j['fontSize'] as num).toDouble();
      lineHeight = (j['lineHeight'] as num).toDouble();
      fontFamily = j['fontFamily'] as String;
      bold = j['bold'] as bool;
      italic = j['italic'] as bool;
      volumeKeys = j['volumeKeys'] as bool;
      invertVolume = j['invertVolume'] as bool;
      reflow = j['reflow'] as bool;
      actualBook = j['actualBook'] as bool;
    } catch (_) {
      // A settings file from another version is not worth stopping the app for.
    }
  }

  void update(void Function(Settings) change) {
    change(this);
    notifyListeners();
    _file.writeAsString(jsonEncode({
      'theme': theme.name,
      'dark': dark,
      'mode': mode.name,
      'scrollGap': scrollGap,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'fontFamily': fontFamily,
      'bold': bold,
      'italic': italic,
      'volumeKeys': volumeKeys,
      'invertVolume': invertVolume,
      'reflow': reflow,
      'actualBook': actualBook,
    }));
  }
}
