import 'dart:typed_data';
import 'pdf_downloader_stub.dart'
    if (dart.library.html) 'pdf_downloader_web.dart' as impl;

Future<String> downloadOrOpenPdf({
  required Uint8List pdfBytes,
  required String pdfDirectUrl,
  String filename = 'fiche_orientation.pdf',
}) {
  return impl.triggerPdfDownload(
    pdfBytes: pdfBytes,
    pdfDirectUrl: pdfDirectUrl,
    filename: filename,
  );
}
