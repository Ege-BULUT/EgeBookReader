import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colorize.dart';
import 'main.dart' show settings;
import 'viewer.dart';

/// Every picture the app has coloured, kept automatically.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return ListenableBuilder(
      listenable: colorizer,
      builder: (context, _) {
        final ids = colorizer.gallery();
        return Scaffold(
          backgroundColor: c.paper,
          appBar: AppBar(
            backgroundColor: c.paper,
            foregroundColor: c.ink,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text('Galeri', style: TextStyle(fontFamily: 'serif', fontSize: 22, color: c.ink)),
          ),
          body: ids.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text('Renklendirilen görseller burada toplanır.', textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 15)),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, crossAxisSpacing: 10, mainAxisSpacing: 16, childAspectRatio: 0.74),
                  itemCount: ids.length,
                  itemBuilder: (context, i) => _Tile(id: ids[i], onOpen: () => _open(ids, i)),
                ),
        );
      },
    );
  }

  void _open(List<String> ids, int i) {
    final items = [
      for (final id in ids)
        ViewerItem(id: id, caption: colorizer.captionOf(id), original: () => colorizer.originalBytes(id)),
    ];
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => PhotoViewer(items: items, initial: i, dim: 1),
    ));
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.id, required this.onOpen});
  final String id;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final showColor = colorizer.showsColor(id);
    final original = colorizer.originalFile(id);
    final file = showColor || !original.existsSync() ? colorizer.fileFor(id) : original;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: GestureDetector(
          onTap: onOpen,
          child: Stack(fit: StackFit.expand, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: Image.file(File(file.path), key: ValueKey(file.path), fit: BoxFit.cover, cacheWidth: 380, width: double.infinity, height: double.infinity),
              ),
            ),
            if (original.existsSync())
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    colorizer.setShowsColor(id, !showColor);
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: Icon(showColor ? Icons.palette : Icons.palette_outlined, color: Colors.white, size: 17),
                  ),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Text(colorizer.captionOf(id), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 12, height: 1.25)),
    ]);
  }
}
