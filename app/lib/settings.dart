import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fonts.dart';
import 'sources.dart';
import 'zones.dart';

enum PaperTheme { paper, parchment, oled, eink, custom }

enum TurnMode { flip, tap, scroll }

enum ColorizeMode { off, onDemand, auto }

enum VoiceSource { system, model, api }

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

/// The user's own background: a colour or a picture, with a tinted overlay, brightness and blur.
class CustomPaper {
  CustomPaper(this.color);
  Color color;
  String? image;
  Color overlay = Colors.black;
  double overlayAlpha = 0;
  double brightness = 1;
  double blur = 0;

  // Worked out by measuring the result, so text stays readable on any picture.
  Color paper = Colors.white, ink = Colors.black;
  double scrim = 0;

  /// Changes when the composed background would look different.
  String get key => '${color.toARGB32()}|$image|${overlay.toARGB32()}|$overlayAlpha|$brightness|$blur|$scrim';

  Map<String, dynamic> toJson() => {
        'color': color.toARGB32(), 'image': image, 'overlay': overlay.toARGB32(), 'overlayAlpha': overlayAlpha,
        'brightness': brightness, 'blur': blur, 'paper': paper.toARGB32(), 'ink': ink.toARGB32(), 'scrim': scrim,
      };

  void readJson(Map<String, dynamic> j) {
    color = Color(j['color'] as int);
    image = j['image'] as String?;
    overlay = Color(j['overlay'] as int);
    overlayAlpha = (j['overlayAlpha'] as num).toDouble();
    brightness = (j['brightness'] as num).toDouble();
    blur = (j['blur'] as num).toDouble();
    paper = Color(j['paper'] as int);
    ink = Color(j['ink'] as int);
    scrim = (j['scrim'] as num).toDouble();
  }
}

/// Bakes the custom background into one image, so reading costs nothing per frame.
Future<ui.Image> composeCustomPaper(CustomPaper c, int w, int h, double blurScale) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  final b = c.brightness;
  final dim = ColorFilter.matrix(<double>[b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0]);
  canvas.drawRect(rect, Paint()..color = c.color..colorFilter = dim);
  final path = c.image;
  if (path != null && File(path).existsSync()) {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(), targetHeight: h);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final img = frame.image;
    final size = Size(img.width.toDouble(), img.height.toDouble());
    final fit = applyBoxFit(BoxFit.cover, size, rect.size);
    final src = Alignment.center.inscribe(fit.source, Offset.zero & size);
    final sigma = c.blur * blurScale;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawImageRect(
      img,
      src,
      sigma > 0 ? rect.inflate(sigma * 3) : rect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = dim
        ..imageFilter = sigma > 0 ? ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp) : null,
    );
    canvas.restore();
    img.dispose();
  }
  canvas.drawRect(rect, Paint()..color = c.overlay.withValues(alpha: c.overlayAlpha));
  if (c.scrim > 0) {
    final light = c.ink.computeLuminance() < 0.5;
    canvas.drawRect(rect, Paint()..color = (light ? Colors.white : Colors.black).withValues(alpha: c.scrim));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}

/// Picks the text colour with the better worst case over the background, and if even that stays under
/// 4.5:1, fades the background toward the opposite of the text until it passes.
Future<void> measureCustomPaper(CustomPaper c) async {
  c.scrim = 0;
  for (var attempt = 0; attempt < 7; attempt++) {
    final image = await composeCustomPaper(c, 64, 64, 0.1);
    final data = await image.toByteData();
    image.dispose();
    final px = data!.buffer.asUint8List();
    final lum = <double>[];
    var r = 0, g = 0, b = 0;
    for (var i = 0; i < px.length; i += 4) {
      r += px[i];
      g += px[i + 1];
      b += px[i + 2];
      lum.add(Color.fromARGB(255, px[i], px[i + 1], px[i + 2]).computeLuminance());
    }
    lum.sort();
    final low = lum[(lum.length * 0.05).floor()], high = lum[(lum.length * 0.95).floor()];
    final n = px.length ~/ 4;
    c.paper = Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
    final darkInk = (low + 0.05) / (0.008 + 0.05);
    final lightInk = (0.88 + 0.05) / (high + 0.05);
    if (attempt == 0) c.ink = darkInk >= lightInk ? const Color(0xFF141414) : const Color(0xFFF2F2F2);
    final usesDark = c.ink.computeLuminance() < 0.5;
    if ((usesDark ? darkInk : lightInk) >= 4.5) return;
    c.scrim += 0.12;
  }
}

class Settings extends ChangeNotifier {
  PaperTheme theme = PaperTheme.paper;
  bool dark = false;
  TurnMode mode = TurnMode.flip;
  double scrollGap = 2;
  double fontSize = 18;
  double lineHeight = 1.5;
  double margin = 26;
  bool justify = true;
  String fontFamily = 'serif';
  Color? inkOverride;
  bool bold = false, italic = false;
  bool volumeKeys = true, invertVolume = false;
  bool reflow = false;
  bool actualBook = false;
  bool menuHintSeen = false;
  double imageSaturation = 1, imageContrast = 1, imageSharpen = 0;
  bool imageUpscale = false;
  ColorizeMode colorizeMode = ColorizeMode.onDemand;
  int autoColorizePages = 3;
  String colorModelId = 'manga';
  bool onboarded = false;
  String uiLanguage = 'system';
  bool ttsEnabled = true;
  bool onlineLookup = true;
  bool groupByCategory = false;
  VoiceSource voiceSource = VoiceSource.system;
  String? ttsModelId;
  int ttsVoice = 0;
  double ttsSpeed = 1;
  String apiBase = '', apiKey = '', apiModel = '', apiVoice = '';
  final customLight = CustomPaper(const Color(0xFFE9EEF0));
  final customDark = CustomPaper(const Color(0xFF12202A))
    ..paper = const Color(0xFF12202A)
    ..ink = const Color(0xFFF2F2F2);
  TapLayout zones = TapLayout.standard();

  CustomPaper get custom => dark ? customDark : customLight;

  Palette paletteFor(PaperTheme t, bool isDark) {
    if (t != PaperTheme.custom) return palettes[(t, isDark)]!;
    final c = isDark ? customDark : customLight;
    return Palette(c.paper, c.ink, Color.lerp(c.ink, c.paper, 0.32)!, 0);
  }

  Palette get palette => paletteFor(theme, dark);
  bool get isEink => theme == PaperTheme.eink;

  /// E-ink panels get no filters at all, whatever else is on.
  bool get bookFilters => actualBook && !isEink;

  PageStyle get pageStyle => PageStyle(
        paper: palette.paper,
        ink: inkOverride ?? palette.ink,
        fontSize: fontSize,
        lineHeight: lineHeight,
        fontFamily: fontFamily,
        fontFallback: fonts.fallbacksOf(fontFamily),
        bold: bold || isEink,
        italic: italic,
        margin: margin,
        justify: justify,
        grain: isEink || theme == PaperTheme.custom ? 0 : (palette.grain + (actualBook ? 0.35 : 0)).clamp(0, 1),
        actualBook: bookFilters,
        backgroundKey: theme == PaperTheme.custom ? custom.key : null,
        imageSaturation: imageSaturation,
        imageContrast: imageContrast,
        imageSharpen: imageSharpen,
        imageUpscale: imageUpscale,
      );

  late final File _file;
  late final Directory dir;

  Future<void> load() async {
    dir = await getApplicationDocumentsDirectory();
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
      menuHintSeen = j['menuHintSeen'] as bool? ?? false;
      margin = (j['margin'] as num?)?.toDouble() ?? margin;
      justify = j['justify'] as bool? ?? justify;
      final ink = j['inkOverride'] as int?;
      inkOverride = ink == null ? null : Color(ink);
      if (j['customLight'] != null) customLight.readJson(j['customLight'] as Map<String, dynamic>);
      if (j['customDark'] != null) customDark.readJson(j['customDark'] as Map<String, dynamic>);
      imageSaturation = (j['imageSaturation'] as num?)?.toDouble() ?? 1;
      imageContrast = (j['imageContrast'] as num?)?.toDouble() ?? 1;
      imageSharpen = (j['imageSharpen'] as num?)?.toDouble() ?? 0;
      imageUpscale = j['imageUpscale'] as bool? ?? false;
      colorizeMode = ColorizeMode.values.byName(j['colorizeMode'] as String? ?? 'onDemand');
      autoColorizePages = j['autoColorizePages'] as int? ?? 3;
      colorModelId = j['colorModelId'] as String? ?? 'manga';
      onboarded = j['onboarded'] as bool? ?? false;
      uiLanguage = j['uiLanguage'] as String? ?? 'system';
      ttsEnabled = j['ttsEnabled'] as bool? ?? true;
      onlineLookup = j['onlineLookup'] as bool? ?? true;
      groupByCategory = j['groupByCategory'] as bool? ?? false;
      voiceSource = VoiceSource.values.byName(j['voiceSource'] as String? ?? 'system');
      ttsModelId = j['ttsModelId'] as String?;
      ttsVoice = j['ttsVoice'] as int? ?? 0;
      ttsSpeed = (j['ttsSpeed'] as num?)?.toDouble() ?? 1;
      apiBase = j['apiBase'] as String? ?? '';
      apiKey = j['apiKey'] as String? ?? '';
      apiModel = j['apiModel'] as String? ?? '';
      apiVoice = j['apiVoice'] as String? ?? '';
      if (j['zones'] != null) zones = TapLayout.fromJson(j['zones'] as Map<String, dynamic>);
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
      'menuHintSeen': menuHintSeen,
      'margin': margin,
      'justify': justify,
      'inkOverride': inkOverride?.toARGB32(),
      'customLight': customLight.toJson(),
      'customDark': customDark.toJson(),
      'zones': zones.toJson(),
      'imageSaturation': imageSaturation,
      'imageContrast': imageContrast,
      'imageSharpen': imageSharpen,
      'imageUpscale': imageUpscale,
      'colorizeMode': colorizeMode.name,
      'autoColorizePages': autoColorizePages,
      'colorModelId': colorModelId,
      'onboarded': onboarded,
      'uiLanguage': uiLanguage,
      'ttsEnabled': ttsEnabled,
      'onlineLookup': onlineLookup,
      'groupByCategory': groupByCategory,
      'voiceSource': voiceSource.name,
      'ttsModelId': ttsModelId,
      'ttsVoice': ttsVoice,
      'ttsSpeed': ttsSpeed,
      'apiBase': apiBase,
      'apiKey': apiKey,
      'apiModel': apiModel,
      'apiVoice': apiVoice,
    }));
  }

  /// Changes the custom background and measures the result before anything draws with it.
  Future<void> updateCustom(void Function(CustomPaper) change) async {
    change(custom);
    await measureCustomPaper(custom);
    update((_) {});
  }
}
