import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'colorize.dart';
import 'l10n.dart';
import 'main.dart';
import 'motion.dart';
import 'settings.dart';
import 'settings_sheet.dart';
import 'tts.dart';

const _welcome = "EgeBookReader'a hoş geldin. Kitapların burada seni bekliyor. Sayfaları parmağınla çevir, sana uyan görünümü seç, istediğinde kitabını sesli dinle.";

/// The first run: language, then voices, colorization and the look of the page.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.again = false});

  /// Opened from settings rather than on first run.
  final bool again;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() {
    settings.update((x) => x.onboarded = true);
    if (widget.again) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const LibraryScreen()));
    }
  }

  void _next() {
    if (_page == 3) return _finish();
    _pages.nextPage(duration: Duration(milliseconds: motionOn(context, settings) ? 360 : 1), curve: easeEnter);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final c = settings.palette;
        return Scaffold(
          backgroundColor: c.paper,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 8, 0),
                child: Row(children: [
                  LogoMark(size: 24, ink: c.ink, ribbon: c.accent),
                  const Spacer(),
                  TextButton(onPressed: _finish, style: TextButton.styleFrom(foregroundColor: c.muted), child: Text(tr('Atla'))),
                ]),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: const [_LanguagePage(), _VoicePage(), _ColorPage(), _LookPage()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
                child: Row(children: [
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: easeEnter,
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(color: i == _page ? c.accent : c.line, borderRadius: BorderRadius.circular(4)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
                    child: Text(tr(_page == 3 ? 'Başla' : 'Devam')),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Keeps a page's content scrollable and lets it arrive piece by piece.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final motion = motionOn(context, settings);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
      children: [
        Rise(index: 0, enabled: motion, child: Text(tr(title), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 31, height: 1.15))),
        const SizedBox(height: 14),
        for (final (i, child) in children.indexed) Rise(index: i + 1, enabled: motion, child: child),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, this.detail, required this.selected, required this.onTap, this.trailing});
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? c.accent : Colors.transparent, width: 1.4),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500)),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(detail!, style: TextStyle(color: c.muted, fontSize: 13, height: 1.3)),
              ],
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

class _LanguagePage extends StatelessWidget {
  const _LanguagePage();

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return _Page(title: 'Dilini seç', children: [
      for (final (id, name) in [('system', tr('Telefonun dili')), ('tr', 'Türkçe'), ('en', 'English')])
        _Choice(label: name, selected: s.uiLanguage == id, onTap: () => s.update((x) => x.uiLanguage = id)),
    ]);
  }
}

class _VoicePage extends StatefulWidget {
  const _VoicePage();
  @override
  State<_VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<_VoicePage> with AutomaticKeepAliveClientMixin {
  final _player = AudioPlayer();
  final _system = FlutterTts();
  String? _playing;
  late String _clipLanguage = uiLanguage;

  // Clip name to position in supertonicOrder.
  static const _clips = [('f1', 'Kadın 1', 0), ('f2', 'Kadın 2', 3), ('m1', 'Erkek 1', 2), ('m2', 'Erkek 2', 1)];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
    _system.setCompletionHandler(() {
      if (mounted && _playing == 'system') setState(() => _playing = null);
    });
    voices.addListener(_changed);
  }

  @override
  void dispose() {
    _player.dispose();
    _system.stop();
    voices.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    await _player.stop();
    await _system.stop();
  }

  Future<void> _playClip(String name, int voice) async {
    await _stop();
    setState(() => _playing = name);
    final model = voiceCatalog.first;
    settings.update((x) {
      x.voiceSource = VoiceSource.model;
      x.ttsModelId = model.id;
      x.ttsVoice = voice;
    });
    await _player.play(AssetSource('onboarding/welcome-$_clipLanguage-$name.m4a'));
  }

  Future<void> _playSystem() async {
    await _stop();
    setState(() => _playing = 'system');
    settings.update((x) => x.voiceSource = VoiceSource.system);
    await _system.setLanguage(_clipLanguage == 'tr' ? 'tr-TR' : 'en-US');
    await _system.speak(_clipLanguage == 'tr' ? _welcome : tr(_welcome));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = settings.palette;
    final s = settings;
    final model = voiceCatalog.first;
    final installed = voices.installed(model);
    final busy = voices.progress.containsKey(model.id);
    Widget mark(String id) => Icon(_playing == id ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, color: c.accent, size: 24);
    return _Page(title: 'Hoş geldin', children: [
      Text(tr(_welcome), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 18, height: 1.5)),
      const SizedBox(height: 20),
      Text(tr('Sesleri dene'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
      const SizedBox(height: 6),
      Text(tr('Hoş geldin metnini farklı seslerle dinle. Hangisini seçersen kitapların o sesle okunur.'), style: TextStyle(color: c.muted, fontSize: 14, height: 1.35)),
      const SizedBox(height: 12),
      Segmented<String>(value: _clipLanguage, options: const {'tr': 'Türkçe', 'en': 'İngilizce'}, onChanged: (v) => setState(() => _clipLanguage = v)),
      const SizedBox(height: 12),
      _Choice(
        label: tr('Sistem sesi'),
        detail: tr('Telefonun sesi, indirme gerektirmez.'),
        selected: s.voiceSource == VoiceSource.system,
        onTap: _playSystem,
        trailing: mark('system'),
      ),
      for (final (name, label, voice) in _clips)
        _Choice(
          label: tr(label),
          selected: s.voiceSource == VoiceSource.model && s.ttsVoice == voice,
          onTap: () => _playClip(name, voice),
          trailing: mark(name),
        ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Kaliteli sesler: Supertonic'), style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(tr('Toplam 10 farklı ses, 31 dil, internetsiz. Dinlediğin dört ses bunların arasında.'), style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          if (busy) ...[
            LinearProgressIndicator(value: voices.progress[model.id], minHeight: 3, color: c.accent, backgroundColor: c.line),
            const SizedBox(height: 6),
            Text(tr('İndiriliyor, devam edebilirsin'), style: TextStyle(color: c.muted, fontSize: 13)),
          ] else if (installed)
            Text(tr('İndirildi'), style: TextStyle(color: c.accent, fontSize: 14, fontWeight: FontWeight.w500))
          else
            FilledButton(
              onPressed: () => voices.download(model),
              style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
              child: Text(tr('Arka planda indir (122 MB)')),
            ),
        ]),
      ),
    ]);
  }
}

class _Compare extends StatefulWidget {
  const _Compare({required this.title, required this.name, required this.credit});
  final String title, name, credit;
  @override
  State<_Compare> createState() => _CompareState();
}

class _CompareState extends State<_Compare> {
  String _shown = 'manga';

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(widget.title), style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: Image.asset('assets/onboarding/compare-${widget.name}-$_shown.jpg', key: ValueKey(_shown), width: double.infinity, fit: BoxFit.fitWidth),
        ),
      ),
      const SizedBox(height: 8),
      Segmented<String>(value: _shown, options: const {'orig': 'Orijinal', 'ddcolor': 'Model 1', 'manga': 'Model 2'}, onChanged: (v) => setState(() => _shown = v)),
      const SizedBox(height: 4),
      Text(widget.credit, style: TextStyle(color: c.muted, fontSize: 11, height: 1.3)),
      const SizedBox(height: 18),
    ]);
  }
}

class _ColorPage extends StatefulWidget {
  const _ColorPage();
  @override
  State<_ColorPage> createState() => _ColorPageState();
}

class _ColorPageState extends State<_ColorPage> with AutomaticKeepAliveClientMixin {
  bool _details = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = settings;
    final c = s.palette;
    return ListenableBuilder(
      listenable: colorizer,
      builder: (context, _) => _Page(title: 'Siyah beyazı renklendir', children: [
        Text(tr('Kitaptaki siyah beyaz görselleri telefonun içinde, internetsiz renklendirir. İki model var; düğmelerle karşılaştır.'), style: TextStyle(color: c.muted, fontSize: 14, height: 1.35)),
        const SizedBox(height: 16),
        const _Compare(title: 'Kitap görseli', name: 'book', credit: 'Pepper&Carrot, David Revoy, CC BY 4.0'),
        const _Compare(title: 'Manga sayfası', name: 'manga', credit: 'Give My Regards to Black Jack, SHUHO SATO'),
        Text(tr('Model 1 fotoğraflar, Model 2 manga ve çizgi roman için. Model 2 çoğu kitapta daha iyi.'), style: TextStyle(color: c.ink, fontSize: 14, height: 1.35)),
        const SizedBox(height: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _details = !_details),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Text(tr('Detaylar'), style: TextStyle(color: c.accent, fontSize: 15, fontWeight: FontWeight.w500)),
              AnimatedRotation(
                turns: _details ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.expand_more_rounded, color: c.accent, size: 22),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: easeEnter,
          alignment: Alignment.topCenter,
          child: !_details
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final m in colorModels) Padding(padding: const EdgeInsets.only(bottom: 10), child: ColorModelCard(model: m)),
                  Segmented<ColorizeMode>(
                    value: s.colorizeMode,
                    options: const {ColorizeMode.off: 'Kapalı', ColorizeMode.onDemand: 'Talep üzerine', ColorizeMode.auto: 'Otomatik'},
                    onChanged: (v) => s.update((x) => x.colorizeMode = v),
                  ),
                  const SizedBox(height: 8),
                  Text(tr('Kapalı: renklendirme yok. Talep üzerine: görseldeki düğmeyle tek tek. Otomatik: kitap açılınca ilk sayfalar, sonra arka planda sırayla.'), style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
                  if (s.colorizeMode == ColorizeMode.auto)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(children: [
                        Expanded(child: Text(tr('İlk açılışta hazırlanacak sayfa sayısı'), style: TextStyle(color: c.ink, fontSize: 14))),
                        IconButton(onPressed: () => s.update((x) => x.autoColorizePages = max(1, x.autoColorizePages - 1)), icon: Icon(Icons.remove, color: c.ink, size: 20)),
                        Text('${s.autoColorizePages}', style: TextStyle(color: c.ink, fontSize: 15)),
                        IconButton(onPressed: () => s.update((x) => x.autoColorizePages = min(30, x.autoColorizePages + 1)), icon: Icon(Icons.add, color: c.ink, size: 20)),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class _LookPage extends StatelessWidget {
  const _LookPage();

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final c = s.palette;
    final ink = s.pageStyle.ink;
    Widget mode(TurnMode m, String name, String detail) => _Choice(label: tr(name), detail: tr(detail), selected: s.mode == m, onTap: () => s.update((x) => x.mode = m));
    return _Page(title: 'Sayfanı ayarla', children: [
      Text(tr('Bunların hepsini okurken menüden değiştirebilirsin.'), style: TextStyle(color: c.muted, fontSize: 14, height: 1.35)),
      const SizedBox(height: 14),
      AnimatedContainer(
        duration: Duration(milliseconds: s.isEink ? 1 : 260),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Örnek sayfa'), style: TextStyle(color: ink, fontFamily: s.fontFamily, fontSize: s.fontSize * 1.2, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(tr('Bir kitabın ilk cümlesi burada böyle görünür. Tema ve yazı boyutu değiştikçe bu sayfa da değişir.'), style: TextStyle(color: ink, fontFamily: s.fontFamily, fontSize: s.fontSize, height: s.lineHeight)),
        ]),
      ),
      const Heading('Tema'),
      Row(children: [
        for (final t in PaperTheme.values.where((t) => t != PaperTheme.custom)) ...[
          Expanded(child: ThemeSwatch(theme: t)),
          if (t != PaperTheme.eink) const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 10),
      Segmented<bool>(value: s.dark, options: const {false: 'Açık', true: 'Koyu'}, onChanged: (v) => s.update((x) => x.dark = v)),
      const Heading('Yazı boyutu'),
      Slider(value: s.fontSize, min: 12, max: 36, divisions: 24, onChanged: (v) => s.update((x) => x.fontSize = v)),
      const Heading('Sayfa çevirme'),
      mode(TurnMode.flip, 'Flip', 'Parmağınla çevirdiğin gerçek sayfa animasyonu.'),
      mode(TurnMode.tap, 'Dokunma', 'Sayfa animasyonsuz, kenarlara dokununca değişir.'),
      mode(TurnMode.scroll, 'Kaydırma', 'Sayfalar alt alta, kesintisiz kaydırılır.'),
      const SizedBox(height: 6),
      _Choice(
        label: s.isEink ? tr("Gerçek kitap modu (E-ink'te kapalı)") : tr('Gerçek kitap modu'),
        detail: tr('Kağıt dokusu, cilt gölgesi, yan sayfalar ve masadaki gölge.'),
        selected: s.bookFilters,
        onTap: () => s.update((x) => x.actualBook = !x.actualBook),
      ),
    ]);
  }
}
