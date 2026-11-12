import 'dart:convert';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/loja_online_repository.dart';
import '../../models/config_loja.dart';
import 'comprovante_pdf.dart';

/// Cartaz A4 com o QR Code do link da loja online, para colar no balcão,
/// na geladeira ou mandar junto com as entregas.
Future<void> imprimirQrLoja(ConfigLoja loja) async {
  final link = LojaOnlineRepository.linkDaLoja(loja.slug);
  final negrito = pw.Font.helveticaBold();
  final normal = pw.Font.helvetica();
  pw.ImageProvider? logo;
  if (loja.logo.isNotEmpty) {
    try {
      logo = pw.MemoryImage(base64Decode(loja.logo));
    } catch (_) {
      logo = null;
    }
  }
  final doc = pw.Document(title: 'QR Code ${loja.nomeLoja}');
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Center(
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            if (logo != null) pw.Image(logo, height: 80),
            pw.SizedBox(height: 12),
            pw.Text(
              latin1Pdf(loja.nomeLoja),
              style: pw.TextStyle(font: negrito, fontSize: 30),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              latin1Pdf('Peça pelo celular e receba em casa'),
              style: pw.TextStyle(font: normal, fontSize: 20),
            ),
            pw.SizedBox(height: 28),
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: link,
              width: 300,
              height: 300,
            ),
            pw.SizedBox(height: 20),
            pw.Text(link, style: pw.TextStyle(font: negrito, fontSize: 16)),
            if (loja.horarioAtendimento.trim().isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                latin1Pdf(loja.horarioAtendimento.trim()),
                style: pw.TextStyle(font: normal, fontSize: 16),
              ),
            ],
            pw.SizedBox(height: 24),
            pw.Text(
              latin1Pdf(
                'Venda de bebidas alcoólicas proibida para menores de 18 anos.',
              ),
              style: pw.TextStyle(font: normal, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
  final bytes = await doc.save();
  await Printing.layoutPdf(
    name: 'QR Code ${loja.nomeLoja}',
    onLayout: (_) async => bytes,
  );
}
