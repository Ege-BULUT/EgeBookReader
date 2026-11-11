import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'backup.dart';
import 'colorize.dart';
import 'fonts.dart';
import 'l10n.dart';
import 'main.dart' show Book, library, settings, themeFor;
import 'motion.dart';
import 'onboarding.dart';
import 'settings.dart';
import 'tts.dart';
import 'zones.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.isPdf, this.book, this.initialTab = 0});
  final bool isPdf;
  final int initialTab;

  /// The open book, for settings kept per book.
  final Book? book;
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late int _tab = widget.initialTab;
  bool _backupBusy = false;
  String? _backupNote;

  Future<void> _backup() async {
    setState(() => _backupBusy = true);
    String note;
    try {
      final file = await writeBackup();
      final saved = await saveBackupAs(file);
      await file.delete();
      note = saved ? 'Yedek kaydedildi.' : 'Yedek kaydedilmedi.';
    } catch (e) {
      note = 'Yedek alınamadı.';
    }
    if (mounted) {
      setState(() {
        _backupBusy = false;
        _backupNote = tr(note);
      });
    }
  }

  Future<void> _restore() async {
    final path = (await FilePicker.pickFiles()).firstOrNull?.path;
    if (path == null) return;
    setState(() => _backupBusy = true);
    String note;
    try {
      final added = await restoreBackup(path);
      note = '${tr('Yedekten eklenen kitap')}: $added';
    } on FormatException catch (e) {
      note = tr(e.message);
    } catch (e) {
      note = tr('Yedek okunamadı.');
    }
    if (mounted) {
      setState(() {
        _backupBusy = false;
        _backupNote = note;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings, colorizer, voices, library]),
      builder: (context, _) {
        final c = settings.palette;
        final motion = motionOn(context, settings);
        final tabs = [_themeTab, _textTab, _pageTab, _imageTab, _voiceTab, _libraryTab];
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
                  options: const {0: 'Tema', 1: 'Yazı', 2: 'Sayfa', 3: 'Görsel', 4: 'Ses', 5: 'Kitaplık'},
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

  List<Widget> _libraryTab() {
    final s = settings;
    return [
      Heading('Kitaplık'),
      Toggle('Kategori ve etiketleri internetten bul', s.onlineLookup, (v) {
        s.update((x) => x.onlineLookup = v);
        if (v) library.fillIn();
      }),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(tr('Yalnızca aranacak metin (kitabın adı ve yazarı) Open Library\'ye gönderilir.'), style: TextStyle(color: s.palette.muted, fontSize: 13, height: 1.35)),
      ),
      Heading('Yedek'),
      Text(tr('Kitaplar, ilerleme, yer imleri, etiketler, listeler ve kapaklar tek dosyada. Geri yüklerken kitaplıkta olanlar olduğu gibi kalır, eksikler eklenir.'),
          style: TextStyle(color: s.palette.muted, fontSize: 13, height: 1.35)),
      const SizedBox(height: 8),
      Row(children: [
        TextButton(onPressed: _backupBusy ? null : _backup, child: Text(tr('Yedek al'))),
        TextButton(onPressed: _backupBusy ? null : _restore, child: Text(tr('Yedekten geri yükle'))),
        if (_backupBusy) SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: s.palette.accent)),
      ]),
      if (_backupNote != null) Text(_backupNote!, style: TextStyle(color: s.palette.ink, fontSize: 13)),
    ];
  }

  List<Widget> _themeTab() {
    final s = settings;
    final c = s.palette;
    final custom = s.custom;
    return [
      Heading('Tema'),
      Row(children: [
        for (final t in PaperTheme.values) ...[
          Expanded(child: ThemeSwatch(theme: t)),
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
              child: Text(tr(custom.image == null ? 'Resim seç' : 'Resmi değiştir')),
            ),
          ),
          if (custom.image != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => s.updateCustom((x) => x.image = null),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: Text(tr('Kaldır')),
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
            child: Text(tr('Yazı okunsun diye arka plan biraz yumuşatıldı.'), style: TextStyle(color: c.muted, fontSize: 13)),
          ),
      ],
      Heading('Gerçek kitap'),
      Toggle(
        s.isEink ? "Gerçek kitap modu (E-ink'te kapalı)" : 'Gerçek kitap modu',
        s.actualBook,
        (v) => s.update((x) => x.actualBook = v),
      ),
      const SizedBox(height: 18),
      TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OnboardingScreen(again: true))),
        style: TextButton.styleFrom(foregroundColor: c.accent, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
        child: Text(tr('Kurulum rehberini aç')),
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
          child: Text(tr('Dokunma alanlarını düzenle')),
        ),
      ],
      if (widget.book case final book? when s.mode != TurnMode.scroll)
        Toggle('Sağdan sola oku (manga)', book.rtl, (v) {
          book.rtl = v;
          library.changed();
        }),
      Toggle('Ses tuşlarıyla çevir', s.volumeKeys, (v) => s.update((x) => x.volumeKeys = v)),
      Toggle('Ses tuşlarını ters çevir', s.invertVolume, (v) => s.update((x) => x.invertVolume = v)),
    ];
  }
}

extension on _SettingsSheetState {
  List<Widget> _voiceTab() {
    final s = settings;
    final c = s.palette;
    return [
      Heading('Sesli okuma'),
      Toggle('Sesli okuma düğmesini göster', s.ttsEnabled, (v) => s.update((x) => x.ttsEnabled = v)),
      const SizedBox(height: 12),
      Segmented<VoiceSource>(
        value: s.voiceSource,
        options: const {VoiceSource.system: 'Sistem', VoiceSource.model: 'İndirilen', VoiceSource.api: 'API'},
        onChanged: (v) => s.update((x) => x.voiceSource = v),
      ),
      if (s.voiceSource == VoiceSource.system)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(tr('Telefonun kendi ses motoru kullanılır. Kitabın diline göre ses seçilir.'), style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
        ),
      if (s.voiceSource == VoiceSource.model) ...[
        Heading('Telefona kurulan sesler'),
        for (final m in voiceCatalog) Padding(padding: const EdgeInsets.only(bottom: 10), child: _voiceCard(m)),
        if (voices.error != null) Text(voices.error!, style: TextStyle(color: c.accent, fontSize: 13)),
      ],
      if (s.voiceSource == VoiceSource.api) ...[
        Heading('API anahtarı'),
        Text(tr('OpenAI uyumlu /audio/speech ucu olan her servis çalışır. Metin bu servise gönderilir. Anahtar sadece bu telefonda saklanır.'),
            style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 10),
        _field('Adres', s.apiBase, 'https://…/v1', (v) => s.update((x) => x.apiBase = v)),
        _field('API anahtarı', s.apiKey, '', (v) => s.update((x) => x.apiKey = v), secret: true),
        _field('Model', s.apiModel, '', (v) => s.update((x) => x.apiModel = v)),
        _field('Ses', s.apiVoice, '', (v) => s.update((x) => x.apiVoice = v)),
      ],
      _SettledSlider(label: 'Konuşma hızı', value: s.ttsSpeed, min: 0.5, max: 3, divisions: 25, decimals: 1, suffix: 'x', onEnd: (v) => s.update((x) => x.ttsSpeed = (v * 10).round() / 10)),
    ];
  }

  Widget _field(String label, String value, String hint, ValueChanged<String> onChanged, {bool secret = false}) {
    final c = settings.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        key: ValueKey(label),
        initialValue: value,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: onChanged,
        style: TextStyle(color: c.ink, fontSize: 15),
        decoration: InputDecoration(labelText: tr(label), hintText: hint, isDense: true, labelStyle: TextStyle(color: c.muted), hintStyle: TextStyle(color: c.muted)),
      ),
    );
  }

  Widget _voiceCard(VoiceModel m) {
    final s = settings;
    final c = s.palette;
    final installed = voices.installed(m);
    final selected = s.ttsModelId == m.id && installed;
    final busy = voices.progress.containsKey(m.id);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? c.accent : Colors.transparent, width: 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m.name, style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w500))),
          Text(m.size, style: TextStyle(color: c.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 6),
        Text('${tr('Diller')}: ${m.languages.map((l) => tr(languageNames[l] ?? l)).join(', ')}', style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 4),
        Text('${m.voiceCount} ${tr('ses')}. ${tr('Lisans')}: ${tr(m.license)}.', style: TextStyle(color: c.muted, fontSize: 13)),
        const SizedBox(height: 2),
        SelectableText(m.source, style: TextStyle(color: c.muted, fontSize: 12)),
        const SizedBox(height: 8),
        if (busy)
          LinearProgressIndicator(value: voices.progress[m.id], minHeight: 3, color: c.accent, backgroundColor: c.line)
        else if (!installed)
          FilledButton(
            onPressed: () => voices.download(m),
            style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
            child: Text(tr('İndir')),
          )
        else
          Row(children: [
            TextButton(
              onPressed: () => s.update((x) => x.ttsModelId = m.id),
              style: TextButton.styleFrom(foregroundColor: c.accent, padding: EdgeInsets.zero),
              child: Text(tr(selected ? 'Seçili' : 'Seç')),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: () => voices.remove(m),
              style: TextButton.styleFrom(foregroundColor: c.muted, padding: EdgeInsets.zero),
              child: Text(tr('Sil')),
            ),
            const Spacer(),
            if (selected) ...[
              _Step(icon: Icons.remove, onTap: () => s.update((x) => x.ttsVoice = max(0, x.ttsVoice - 1))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('${tr('Ses')} ${s.ttsVoice + 1}', style: TextStyle(color: c.ink, fontSize: 14))),
              _Step(icon: Icons.add, onTap: () => s.update((x) => x.ttsVoice = min(m.voiceCount - 1, x.ttsVoice + 1))),
            ],
          ]),
      ]),
    );
  }

  List<Widget> _imageTab() {
    final s = settings;
    final c = s.palette;
    return [
      Heading('Görsel filtreler'),
      _SettledSlider(label: 'Doygunluk', value: s.imageSaturation, min: 0, max: 2, percent: true, onEnd: (v) => s.update((x) => x.imageSaturation = v)),
      _SettledSlider(label: 'Kontrast', value: s.imageContrast, min: 0.6, max: 1.6, percent: true, onEnd: (v) => s.update((x) => x.imageContrast = v)),
      _SettledSlider(label: 'Keskinlik', value: s.imageSharpen, min: 0, max: 1, percent: true, onEnd: (v) => s.update((x) => x.imageSharpen = v)),
      Toggle('Yüksek kaliteli büyütme', s.imageUpscale, (v) => s.update((x) => x.imageUpscale = v)),
      Heading('Renklendirme'),
      for (final m in colorModels) Padding(padding: const EdgeInsets.only(bottom: 10), child: ColorModelCard(model: m)),
      if (colorizer.error != null) Text(colorizer.error!, style: TextStyle(color: c.accent, fontSize: 13)),
      Segmented<ColorizeMode>(
        value: s.colorizeMode,
        options: const {ColorizeMode.off: 'Kapalı', ColorizeMode.onDemand: 'Talep üzerine', ColorizeMode.auto: 'Otomatik'},
        onChanged: (v) => s.update((x) => x.colorizeMode = v),
      ),
      if (s.colorizeMode == ColorizeMode.auto)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('İlk açılışta hazırlanacak sayfa sayısı'), style: TextStyle(color: c.ink, fontSize: 15)),
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

/// Download, choose or delete one colorizer.
class ColorModelCard extends StatelessWidget {
  const ColorModelCard({super.key, required this.model});
  final ColorModel model;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final s = settings;
    final c = s.palette;
    final installed = colorizer.isInstalled(m);
    final selected = colorizer.model?.id == m.id;
    final busy = colorizer.downloads.containsKey(m.id);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? c.accent : Colors.transparent, width: 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m.name, style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w500))),
          Text(tr(m.sizeText), style: TextStyle(color: c.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        Text('${tr(m.description)} ${tr('Telefonda, internetsiz çalışır.')} ${tr('Lisans')}: ${m.license}.', style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 2),
        SelectableText(m.source, style: TextStyle(color: c.muted, fontSize: 12)),
        const SizedBox(height: 8),
        if (busy)
          LinearProgressIndicator(value: colorizer.downloads[m.id], minHeight: 3, color: c.accent, backgroundColor: c.line)
        else if (!installed)
          FilledButton(
            onPressed: () => colorizer.downloadModel(m),
            style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
            child: Text(tr('İndir')),
          )
        else
          Row(children: [
            TextButton(
              onPressed: () => s.update((x) => x.colorModelId = m.id),
              style: TextButton.styleFrom(foregroundColor: c.accent, padding: EdgeInsets.zero),
              child: Text(tr(selected ? 'Seçili' : 'Seç')),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: () => colorizer.removeModel(m),
              style: TextButton.styleFrom(foregroundColor: c.muted, padding: EdgeInsets.zero),
              child: Text(tr('Sil')),
            ),
          ]),
      ]),
    );
  }
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 12),
        child: Text(tr(text), style: TextStyle(color: settings.palette.ink, fontFamily: 'serif', fontSize: 19, fontWeight: FontWeight.w500)),
      );
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(tr(text), style: TextStyle(color: settings.palette.muted, fontSize: 13)),
      );
}

/// Slides freely and applies when the finger lifts, because each new value means rendering pages again.
class _SettledSlider extends StatefulWidget {
  const _SettledSlider({required this.label, required this.value, required this.min, required this.max, required this.onEnd, this.percent = false, this.decimals = 0, this.suffix = '', this.divisions});
  final String label, suffix;
  final double value, min, max;
  final bool percent;
  final int decimals;
  final int? divisions;
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
          Expanded(child: Text(tr(widget.label), style: TextStyle(color: c.ink, fontSize: 15))),
          Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        Slider(
          value: v,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
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
          child: label == null ? null : Text(tr(label), style: TextStyle(color: c.ink, fontSize: 11)),
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
        title: Text(tr('Renk kodu'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
        content: TextField(controller: field, autofocus: true, style: TextStyle(color: c.ink), decoration: const InputDecoration(hintText: '#A8492F')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Vazgeç'))),
          TextButton(onPressed: () => Navigator.pop(context, field.text), child: Text(tr('Tamam'))),
        ],
      ),
    );
    final hex = text?.trim().replaceFirst('#', '') ?? '';
    final parsed = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex) ? int.parse(hex, radix: 16) : null;
    if (parsed != null) onChanged(Color(0xFF000000 | parsed));
  }
}

class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({super.key, required this.theme});
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
          FittedBox(child: Text(tr(_names[theme]!), style: TextStyle(color: t.muted, fontSize: 11))),
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(tr(options[k]!), style: TextStyle(color: k == value ? c.ink : c.muted, fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Expanded(child: Text(tr(label), style: TextStyle(color: c.ink, fontSize: 15))),
          Switch(value: value, onChanged: onChanged, activeThumbColor: c.accent),
        ]),
      ),
    );
  }
}
