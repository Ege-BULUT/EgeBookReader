import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'colorize.dart';
import 'fonts.dart';
import 'main.dart' show settings, themeFor;
import 'motion.dart';
import 'settings.dart';
import 'zones.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.isPdf});
  final bool isPdf;
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings, colorizer]),
      builder: (context, _) {
        final c = settings.palette;
        final motion = motionOn(context, settings);
        final tabs = [_themeTab, _textTab, _pageTab, _imageTab];
        return Theme(
          data: themeFor(c),
          child: AnimatedContainer(
            duration: Duration(milliseconds: motion ? 200 : 1),
            color: c.paper,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                child: Segmented<int>(
                  value: _tab,
                  options: const {0: 'Tema', 1: 'Yazı', 2: 'Sayfa', 3: 'Görsel'},
                  onChanged: (v) => setState(() => _tab = v),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: motion ? 220 : 1),
                  switchInCurve: easeEnter,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: ListView(
                    key: ValueKey(_tab),
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
                    children: [
                      for (final (i, item) in tabs[_tab]().indexed) Rise(index: i, enabled: motion, child: item),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _themeTab() {
    final s = settings;
    final c = s.palette;
    final custom = s.custom;
    return [
      Heading('Tema'),
      Row(children: [
        for (final t in PaperTheme.values) ...[
          Expanded(child: _ThemeSwatch(theme: t)),
          if (t != PaperTheme.values.last) const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 12),
      Segmented<bool>(
        value: s.dark,
        options: const {false: 'Açık', true: 'Koyu'},
        onChanged: (v) => s.update((x) => x.dark = v),
      ),
      if (s.theme == PaperTheme.custom) ...[
        Heading('Özel arka plan'),
        _SubLabel('Renk'),
        ColorDots(value: custom.color, onChanged: (v) => s.updateCustom((x) => x.color = v!)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _pickBackground,
              style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line)),
              child: Text(custom.image == null ? 'Resim seç' : 'Resmi değiştir'),
            ),
          ),
          if (custom.image != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => s.updateCustom((x) => x.image = null),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: const Text('Kaldır'),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        _SubLabel('Üst renk'),
        ColorDots(value: custom.overlay, onChanged: (v) => s.updateCustom((x) => x.overlay = v!)),
        _SettledSlider(label: 'Saydamlık', value: custom.overlayAlpha, min: 0, max: 0.9, percent: true, onEnd: (v) => s.updateCustom((x) => x.overlayAlpha = v)),
        _SettledSlider(label: 'Parlaklık', value: custom.brightness, min: 0.2, max: 1.4, percent: true, onEnd: (v) => s.updateCustom((x) => x.brightness = v)),
        _SettledSlider(label: 'Bulanıklık', value: custom.blur, min: 0, max: 30, onEnd: (v) => s.updateCustom((x) => x.blur = v)),
        if (custom.scrim > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Yazı okunsun diye arka plan biraz yumuşatıldı.', style: TextStyle(color: c.muted, fontSize: 13)),
          ),
      ],
      Heading('Gerçek kitap'),
      Toggle(
        s.isEink ? 'Gerçek kitap modu (E-ink\'te kapalı)' : 'Gerçek kitap modu',
        s.actualBook,
        (v) => s.update((x) => x.actualBook = v),
      ),
    ];
  }

  Future<void> _pickBackground() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    final from = picked.firstOrNull?.path;
    if (from == null) return;
    final to = File(p.join(settings.dir.path, 'backgrounds', '${DateTime.now().millisecondsSinceEpoch}${p.extension(from)}'));
    await to.create(recursive: true);
    await File(from).copy(to.path);
    final old = settings.custom.image;
    await settings.updateCustom((x) => x.image = to.path);
    if (old != null) await File(old).delete().catchError((_) => File(old));
  }

  List<Widget> _textTab() {
    final s = settings;
    final c = s.palette;
    return [
      Heading('Font'),
      Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FontBrowser())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Text(fonts.nameOf(s.fontFamily),
                    style: TextStyle(color: c.ink, fontFamily: s.fontFamily, fontFamilyFallback: s.pageStyle.fontFallback, fontSize: 18)),
              ),
              Icon(Icons.chevron_right, color: c.muted, size: 20),
            ]),
          ),
        ),
      ),
      Heading('Boyut'),
      Row(children: [
        _Step(icon: Icons.remove, onTap: () => s.update((x) => x.fontSize = max(12, x.fontSize - 1))),
        Expanded(child: Text('${s.fontSize.round()}', textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 16))),
        _Step(icon: Icons.add, onTap: () => s.update((x) => x.fontSize = min(36, x.fontSize + 1))),
      ]),
      _SettledSlider(label: 'Satır aralığı', value: s.lineHeight, min: 1.1, max: 2.2, decimals: 1, onEnd: (v) => s.update((x) => x.lineHeight = v)),
      _SettledSlider(label: 'Kenar boşluğu', value: s.margin, min: 8, max: 64, onEnd: (v) => s.update((x) => x.margin = v)),
      Heading('Renk'),
      ColorDots(
        value: s.inkOverride,
        includeAuto: true,
        onChanged: (v) => s.update((x) => x.inkOverride = v),
      ),
      Heading('Stil'),
      Toggle('Kalın', s.bold, (v) => s.update((x) => x.bold = v)),
      Toggle('İtalik', s.italic, (v) => s.update((x) => x.italic = v)),
      Toggle('İki yana yasla', s.justify, (v) => s.update((x) => x.justify = v)),
      if (widget.isPdf) Toggle('Reflow (PDF metnini yeniden diz)', s.reflow, (v) => s.update((x) => x.reflow = v)),
    ];
  }

  List<Widget> _pageTab() {
    final s = settings;
    final c = s.palette;
    return [
      Heading('Sayfa çevirme'),
      Segmented<TurnMode>(
        value: s.mode,
        options: const {TurnMode.flip: 'Flip', TurnMode.tap: 'Dokunma', TurnMode.scroll: 'Kaydırma'},
        onChanged: (v) => s.update((x) => x.mode = v),
      ),
      if (s.mode == TurnMode.scroll)
        _SettledSlider(label: 'Sayfalar arası boşluk', value: s.scrollGap, min: 0, max: 40, suffix: ' px', onEnd: (v) => s.update((x) => x.scrollGap = v)),
      if (s.mode != TurnMode.scroll) ...[
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ZoneEditor())),
          style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line)),
          child: const Text('Dokunma alanlarını düzenle'),
        ),
      ],
      Toggle('Ses tuşlarıyla çevir', s.volumeKeys, (v) => s.update((x) => x.volumeKeys = v)),
      Toggle('Ses tuşlarını ters çevir', s.invertVolume, (v) => s.update((x) => x.invertVolume = v)),
    ];
  }
}

extension on _SettingsSheetState {
  List<Widget> _imageTab() {
    final s = settings;
    final c = s.palette;
    final progress = colorizer.downloadProgress;
    return [
      Heading('Görsel filtreler'),
      _SettledSlider(label: 'Doygunluk', value: s.imageSaturation, min: 0, max: 2, percent: true, onEnd: (v) => s.update((x) => x.imageSaturation = v)),
      _SettledSlider(label: 'Kontrast', value: s.imageContrast, min: 0.6, max: 1.6, percent: true, onEnd: (v) => s.update((x) => x.imageContrast = v)),
      _SettledSlider(label: 'Keskinlik', value: s.imageSharpen, min: 0, max: 1, percent: true, onEnd: (v) => s.update((x) => x.imageSharpen = v)),
      Toggle('Yüksek kaliteli büyütme', s.imageUpscale, (v) => s.update((x) => x.imageUpscale = v)),
      Heading('Renklendirme'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(colorModel.name, style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('Siyah beyaz görselleri telefonun içinde, internetsiz renklendirir. ${colorModel.sizeText}. Lisans: ${colorModel.license}.',
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
          const SizedBox(height: 4),
          SelectableText(colorModel.source, style: TextStyle(color: c.muted, fontSize: 12)),
          const SizedBox(height: 10),
          if (progress != null)
            LinearProgressIndicator(value: progress, minHeight: 3, color: c.accent, backgroundColor: c.line)
          else if (colorizer.modelReady)
            TextButton(
              onPressed: colorizer.removeModel,
              style: TextButton.styleFrom(foregroundColor: c.accent, padding: EdgeInsets.zero),
              child: const Text('Modeli sil'),
            )
          else
            FilledButton(
              onPressed: colorizer.downloadModel,
              style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
              child: const Text('Modeli indir'),
            ),
          if (colorizer.error != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(colorizer.error!, style: TextStyle(color: c.accent, fontSize: 13))),
        ]),
      ),
      const SizedBox(height: 14),
      Segmented<ColorizeMode>(
        value: s.colorizeMode,
        options: const {ColorizeMode.off: 'Kapalı', ColorizeMode.onDemand: 'Talep üzerine', ColorizeMode.auto: 'Otomatik'},
        onChanged: (v) => s.update((x) => x.colorizeMode = v),
      ),
      if (s.colorizeMode == ColorizeMode.auto)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('İlk açılışta hazırlanacak sayfa sayısı', style: TextStyle(color: c.ink, fontSize: 15)),
            const SizedBox(height: 8),
            Row(children: [
              _Step(icon: Icons.remove, onTap: () => s.update((x) => x.autoColorizePages = max(1, x.autoColorizePages - 1))),
              Expanded(child: Text('${s.autoColorizePages}', textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 16))),
              _Step(icon: Icons.add, onTap: () => s.update((x) => x.autoColorizePages = min(30, x.autoColorizePages + 1))),
            ]),
          ]),
        ),
    ];
  }
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 12),
        child: Text(text, style: TextStyle(color: settings.palette.ink, fontFamily: 'serif', fontSize: 19, fontWeight: FontWeight.w500)),
      );
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(color: settings.palette.muted, fontSize: 13)),
      );
}

/// Slides freely and applies when the finger lifts, because each new value means rendering pages again.
class _SettledSlider extends StatefulWidget {
  const _SettledSlider({required this.label, required this.value, required this.min, required this.max, required this.onEnd, this.percent = false, this.decimals = 0, this.suffix = ''});
  final String label, suffix;
  final double value, min, max;
  final bool percent;
  final int decimals;
  final ValueChanged<double> onEnd;
  @override
  State<_SettledSlider> createState() => _SettledSliderState();
}

class _SettledSliderState extends State<_SettledSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final v = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    final text = widget.percent ? '%${(v * 100).round()}' : '${v.toStringAsFixed(widget.decimals)}${widget.suffix}';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(widget.label, style: TextStyle(color: c.ink, fontSize: 15))),
          Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        Slider(
          value: v,
          min: widget.min,
          max: widget.max,
          onChanged: (x) => setState(() => _dragging = x),
          onChangeEnd: (x) {
            setState(() => _dragging = null);
            widget.onEnd(x);
          },
        ),
      ]),
    );
  }
}

class ColorDots extends StatelessWidget {
  const ColorDots({super.key, required this.value, required this.onChanged, this.includeAuto = false});
  final Color? value;
  final ValueChanged<Color?> onChanged;
  final bool includeAuto;

  static const _colors = [
    Color(0xFFFFFFFF), Color(0xFFF7F4EE), Color(0xFFF0E2C2), Color(0xFFE3EAE3), Color(0xFFDDE6F0), Color(0xFFF2DEDE),
    Color(0xFF8A8F98), Color(0xFF5B4636), Color(0xFF7A2E20), Color(0xFF2F4A3A), Color(0xFF1F3550), Color(0xFF12202A),
    Color(0xFF2A2622), Color(0xFF000000),
  ];

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    Widget dot(Color? color, String? label) {
      final selected = value == color;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(color);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color ?? c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? c.accent : c.line, width: selected ? 2.4 : 1),
          ),
          child: label == null ? null : Text(label, style: TextStyle(color: c.ink, fontSize: 11)),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (includeAuto) dot(null, 'Oto'),
      for (final color in _colors) dot(color, null),
      GestureDetector(
        onTap: () => _askHex(context),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle, border: Border.all(color: c.line)),
          child: Text('#', style: TextStyle(color: c.ink, fontSize: 15)),
        ),
      ),
    ]);
  }

  Future<void> _askHex(BuildContext context) async {
    final c = settings.palette;
    final field = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.paper,
        title: Text('Renk kodu', style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
        content: TextField(controller: field, autofocus: true, style: TextStyle(color: c.ink), decoration: const InputDecoration(hintText: '#A8492F')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('Tamam')),
        ],
      ),
    );
    final hex = text?.trim().replaceFirst('#', '') ?? '';
    final parsed = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex) ? int.parse(hex, radix: 16) : null;
    if (parsed != null) onChanged(Color(0xFF000000 | parsed));
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});
  final PaperTheme theme;
  static const _names = {
    PaperTheme.paper: 'Kağıt',
    PaperTheme.parchment: 'Parşömen',
    PaperTheme.oled: 'OLED',
    PaperTheme.eink: 'E-ink',
    PaperTheme.custom: 'Özel',
  };

  @override
  Widget build(BuildContext context) {
    final t = settings.paletteFor(theme, settings.dark);
    final selected = settings.theme == theme;
    final c = settings.palette;
    return GestureDetector(
      onTap: () => settings.update((x) => x.theme = theme),
      child: AnimatedContainer(
        duration: Duration(milliseconds: settings.isEink ? 1 : 160),
        height: 74,
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? c.accent : c.line, width: selected ? 1.6 : 1),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Aa', style: TextStyle(color: t.ink, fontFamily: 'serif', fontSize: 20)),
          const SizedBox(height: 2),
          FittedBox(child: Text(_names[theme]!, style: TextStyle(color: t.muted, fontSize: 11))),
        ]),
      ),
    );
  }
}

class Segmented<T> extends StatelessWidget {
  const Segmented({required this.value, required this.options, required this.onChanged, super.key});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final keys = options.keys.toList();
    final index = keys.indexOf(value);
    return Container(
      height: 40,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / keys.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: Duration(milliseconds: settings.isEink ? 1 : 240),
            curve: easeEnter,
            left: index * w + 3,
            top: 3,
            bottom: 3,
            width: w - 6,
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(4), border: Border.all(color: c.line)),
            ),
          ),
          Row(children: [
            for (final k in keys)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(k),
                  child: Center(
                    child: Text(options[k]!, style: TextStyle(color: k == value ? c.ink : c.muted, fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(width: 54, height: 40, child: Icon(icon, color: c.ink, size: 20)),
      ),
    );
  }
}

class Toggle extends StatelessWidget {
  const Toggle(this.label, this.value, this.onChanged, {super.key});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: c.ink, fontSize: 15))),
        Switch(value: value, onChanged: onChanged, activeThumbColor: c.accent),
      ]),
    );
  }
}
