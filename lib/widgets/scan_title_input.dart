import 'package:flutter/material.dart';

/// Text field for the document title.
class ScanTitleInput extends StatelessWidget {
  const ScanTitleInput({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Nama Dokumen',
        prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
