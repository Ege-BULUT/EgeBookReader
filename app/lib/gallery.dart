import 'dart:io';

import 'package:flutter/material.dart';

import 'colorize.dart';
import 'main.dart' show settings;

/// Every picture the app has coloured, kept automatically.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final files = colorizer.gallery();
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Galeri', style: TextStyle(fontFamily: 'serif', fontSize: 22, color: c.ink)),
      ),
      body: files.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('Renklendirilen görseller burada toplanır.',
                    textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 15)),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: files.length,
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _Viewer(file: files[i]))),
                child: Hero(
                  tag: files[i].path,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(files[i], fit: BoxFit.cover, cacheWidth: 360),
                  ),
                ),
              ),
            ),
    );
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
        extendBodyBehindAppBar: true,
        body: InteractiveViewer(
          maxScale: 6,
          child: Center(child: Hero(tag: file.path, child: Image.file(file))),
        ),
      );
}
