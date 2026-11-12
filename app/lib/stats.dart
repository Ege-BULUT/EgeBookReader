import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'library_sheets.dart' show readingState;
import 'main.dart' show library, settings, writeWhole;

final stats = ReadingStats();

/// Time spent reading and pages turned, day by day, kept only on this device.
class ReadingStats extends ChangeNotifier {
  /// Seconds read and pages turned, keyed by day (2026-11-12).
  final seconds = <String, int>{}, pages = <String, int>{};
  int goalMinutes = 20;
  File? _file;
  Timer? _saving;

  static String dayOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    _file = File(p.join((await getApplicationDocumentsDirectory()).path, 'stats.json'));
    if (!_file!.existsSync()) return;
    try {
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      seconds.addAll((j['seconds'] as Map<String, dynamic>).cast<String, int>());
      pages.addAll((j['pages'] as Map<String, dynamic>).cast<String, int>());
      goalMinutes = j['goal'] as int? ?? goalMinutes;
    } on FormatException {
      // a half-written file; start again rather than not open
    }
  }

  void addTime(int s, [DateTime? now]) => _add(seconds, s, now);
  void addPage([DateTime? now]) => _add(pages, 1, now);

  void setGoal(int minutes) {
    goalMinutes = minutes;
    _changed();
  }

  void _add(Map<String, int> to, int n, DateTime? now) {
    final day = dayOf(now ?? DateTime.now());
    to[day] = (to[day] ?? 0) + n;
    _changed();
  }

  void _changed() {
    notifyListeners();
    _saving?.cancel();
    _saving = Timer(const Duration(seconds: 2), flush);
  }

  Future<void> flush() async {
    _saving?.cancel();
    if (_file != null) writeWhole(_file!, jsonEncode({'seconds': seconds, 'pages': pages, 'goal': goalMinutes}));
  }

  int minutesOn(DateTime d) => (seconds[dayOf(d)] ?? 0) ~/ 60;

  /// Days in a row with at least a minute of reading, ending today, or yesterday if today has none yet.
  int streak([DateTime? today]) {
    var d = today ?? DateTime.now();
    if (minutesOn(d) == 0) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (minutesOn(d) > 0) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  /// Minutes over the [days] days up to and including [today].
  int minutesOver(int days, [DateTime? today]) {
    final t = today ?? DateTime.now();
    return [for (var i = 0; i < days; i++) minutesOn(DateTime(t.year, t.month, t.day - i))].fold(0, (a, b) => a + b);
  }
}

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return ListenableBuilder(
      listenable: stats,
      builder: (context, _) {
        final now = DateTime.now();
        final today = stats.minutesOn(now), goal = stats.goalMinutes;
        final days = [for (var i = 13; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
        final most = max(goal, days.map(stats.minutesOn).fold(1, max));
        final finished = library.books.where((b) => readingState(b) == 'Bitti').length;
        final allMinutes = stats.seconds.values.fold(0, (a, b) => a + b) ~/ 60;
        Widget figure(String value, String label) => Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 24)),
                Text(tr(label), style: TextStyle(color: c.muted, fontSize: 12)),
              ]),
            );
        return Scaffold(
          backgroundColor: c.paper,
          appBar: AppBar(
            backgroundColor: c.paper,
            foregroundColor: c.ink,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(tr('Okuma istatistikleri'), style: TextStyle(fontFamily: 'serif', fontSize: 22, color: c.ink)),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), children: [
            Row(children: [
              SizedBox.square(
                dimension: 96,
                child: Stack(fit: StackFit.expand, children: [
                  CircularProgressIndicator(value: goal == 0 ? 1 : min(1, today / goal), strokeWidth: 7, color: c.accent, backgroundColor: c.line),
                  Center(
                    child: Text('$today\n${tr('dk')}',
                        textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 18, height: 1.1, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(today >= goal ? tr('Bugünün hedefi tamam') : '${tr('Bugün hedefe')} ${goal - today} ${tr('dk kaldı')}',
                      style: TextStyle(color: c.ink, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.local_fire_department_outlined, color: c.accent, size: 20),
                    const SizedBox(width: 6),
                    Text('${stats.streak()} ${stats.streak() == 1 && uiLanguage != 'tr' ? 'day in a row' : tr('gün üst üste')}', style: TextStyle(color: c.muted, fontSize: 14)),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 28),
            Text(tr('Son 14 gün'), style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 10),
            SizedBox(
              height: 120,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final d in days)
                  Expanded(
                    child: Tooltip(
                      message: '${d.day}.${d.month} · ${stats.minutesOn(d)} ${tr('dk')}',
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          height: max(2, 96 * stats.minutesOn(d) / most),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: stats.minutesOn(d) >= goal ? c.accent : c.accent.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${d.day}', style: TextStyle(color: d.day == now.day ? c.ink : c.muted, fontSize: 10)),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 28),
            Row(children: [
              figure('${stats.minutesOver(7)}', 'dk, son 7 gün'),
              figure('${stats.minutesOver(30)}', 'dk, son 30 gün'),
              figure((allMinutes / 60).toStringAsFixed(allMinutes < 600 ? 1 : 0), 'saat, toplam'),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              figure('${stats.pages.values.fold(0, (a, b) => a + b)}', 'sayfa çevrildi'),
              figure('$finished', 'kitap bitti'),
              const Expanded(child: SizedBox()),
            ]),
            const SizedBox(height: 30),
            Text(tr('Günlük hedef'), style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final m in const [10, 20, 30, 45, 60])
                ChoiceChip(
                  selected: goal == m,
                  showCheckmark: false,
                  label: Text('$m ${tr('dk')}'),
                  labelStyle: TextStyle(color: goal == m ? c.paper : c.ink, fontSize: 13),
                  selectedColor: c.accent,
                  backgroundColor: c.surface,
                  side: BorderSide(color: goal == m ? c.accent : c.line),
                  onSelected: (_) => stats.setGoal(m),
                ),
            ]),
            const SizedBox(height: 24),
            Text(tr('Okurken ya da dinlerken geçen süre sayılır; beş dakika dokunulmazsa durur. Yalnızca bu cihazda tutulur.'),
                style: TextStyle(color: c.muted, fontSize: 12, height: 1.4)),
          ]),
        );
      },
    );
  }
}
