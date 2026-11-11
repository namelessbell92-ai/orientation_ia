import 'dart:io';
import 'dart:typed_data';

Future<String> triggerPdfDownload({
  required Uint8List pdfBytes,
  required String pdfDirectUrl,
  String filename = 'fiche_orientation.pdf',
}) async {
  try {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(pdfBytes, flush: true);
    return file.path;
  } catch (_) {
    return pdfDirectUrl;
  }
}
