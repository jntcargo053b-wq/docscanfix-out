import 'package:docscan/screens/Scan/scan_controller.dart';
import 'package:docscan/screens/Scan/widgets/scan_ocr_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSection({
    required bool isRunning,
    String? extractedText,
    List<OcrPageStatus> pageStatuses = const <OcrPageStatus>[],
    double progress = 0,
    ValueChanged<int>? onRetryPage,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ScanOcrSection(
          isRunning: isRunning,
          extractedText: extractedText,
          onRerun: () {},
          pageStatuses: pageStatuses,
          progress: progress,
          onRetryPage: onRetryPage ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('shows page progress while OCR is running', (tester) async {
    await tester.pumpWidget(
      buildSection(
        isRunning: true,
        pageStatuses: const [
          OcrPageStatus.success,
          OcrPageStatus.running,
        ],
        progress: 0.5,
      ),
    );

    expect(find.text('Mengenali 1/2 halaman • 50%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows completion message when no text is detected', (tester) async {
    await tester.pumpWidget(
      buildSection(
        isRunning: false,
        extractedText: '',
        pageStatuses: const [
          OcrPageStatus.success,
          OcrPageStatus.success,
        ],
        progress: 1,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('OCR selesai, tetapi tidak ada teks yang terdeteksi.'),
      findsOneWidget,
    );
    expect(find.text('Hal 1 • OK'), findsOneWidget);
    expect(find.text('Hal 2 • OK'), findsOneWidget);
  });

  testWidgets('allows retry for failed OCR pages', (tester) async {
    int? retriedPage;

    await tester.pumpWidget(
      buildSection(
        isRunning: false,
        extractedText: 'Teks halaman pertama',
        pageStatuses: const [
          OcrPageStatus.success,
          OcrPageStatus.failed,
        ],
        onRetryPage: (index) => retriedPage = index,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Hal 1 • OK'), findsOneWidget);
    expect(find.text('Hal 2 • ulang'), findsOneWidget);

    await tester.tap(find.text('Hal 2 • ulang'));
    expect(retriedPage, 1);
  });
}
