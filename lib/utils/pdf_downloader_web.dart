// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<String> triggerPdfDownload({
  required Uint8List pdfBytes,
  required String pdfDirectUrl,
  String filename = 'fiche_orientation.pdf',
}) async {
  try {
    final blob = html.Blob([pdfBytes], 'application/pdf');
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);

    // 1. Ouvre la fiche PDF dans un nouvel onglet pour lecture immédiate
    html.window.open(blobUrl, '_blank');

    // 2. Déclenche simultanément le téléchargement de `fiche_orientation.pdf`
    final anchor = html.AnchorElement(href: blobUrl)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();

    Future.delayed(const Duration(seconds: 30), () {
      html.Url.revokeObjectUrl(blobUrl);
    });
    return filename;
  } catch (_) {
    html.window.open(pdfDirectUrl, '_blank');
    return pdfDirectUrl;
  }
}
