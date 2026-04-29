import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import '../services/save_service.dart';

class ScanScreen extends StatefulWidget {
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool loading = false;

  Future<void> scanAndSave() async {
    setState(() => loading = true);

    try {
      final images = await CunningDocumentScanner.getPictures();

      if (images == null || images.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tidak ada hasil scan")),
        );
        return;
      }

      await SaveService().saveImages(images);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Berhasil disimpan ke galeri")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Doc Scanner")),
      body: Center(
        child: loading
            ? CircularProgressIndicator()
            : ElevatedButton(
                onPressed: scanAndSave,
                child: Text("Scan & Simpan"),
              ),
      ),
    );
  }
}
