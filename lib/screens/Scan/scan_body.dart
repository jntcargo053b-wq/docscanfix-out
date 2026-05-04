import 'package:flutter/material.dart';

import '../scan_controller.dart';

class ScanBody extends StatelessWidget {
  final ScanController controller;
  final Future<void> Function() onSave;

  const ScanBody({
    super.key,
    required this.controller,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: onSave,
        child: const Text('Simpan'),
      ),
    );
  }
}
