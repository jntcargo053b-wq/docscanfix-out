import 'dart:io';

import 'package:flutter/material.dart';

class DocumentPageViewerScreen extends StatefulWidget {
  const DocumentPageViewerScreen({
    super.key,
    required this.imagePaths,
    required this.initialIndex,
    required this.documentTitle,
  });

  final List<String> imagePaths;
  final int initialIndex;
  final String documentTitle;

  @override
  State<DocumentPageViewerScreen> createState() => _DocumentPageViewerScreenState();
}

class _DocumentPageViewerScreenState extends State<DocumentPageViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  int _quarterTurns = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imagePaths.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.documentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            Text('Halaman ${_currentIndex + 1} dari ${widget.imagePaths.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Putar 90°',
            onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
            icon: const Icon(Icons.rotate_right),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imagePaths.length,
        onPageChanged: (index) => setState(() {
          _currentIndex = index;
          _quarterTurns = 0;
        }),
        itemBuilder: (context, index) => Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: RotatedBox(
              quarterTurns: _quarterTurns,
              child: Image.file(
                File(widget.imagePaths[index]),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Halaman tidak dapat dibuka.',
                      style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
