import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/formatters.dart';
import '../../data/config_repository.dart';

/// Gera um relatório A4 simples (cabeçalho com a loja, título, período e
/// blocos de conteúdo) e abre a janela de impressão do sistema.
///
/// A fonte padrão do PDF cobre apenas caracteres latinos; evite travessões
/// e setas nos textos enviados para cá.
Future<void> imprimirRelatorio({
  required String titulo,
  required String subtitulo,
  required List<pw.Widget> Function() conteudo,
}) async {
  final loja = ConfigRepository.atual.value;
  final doc = pw.Document(title: titulo, author: loja.nomeLoja);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    loja.nomeLoja,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    titulo,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(subtitulo, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.Text(
              'Emitido em ${formatarDataHora(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => conteudo(),
    ),
  );
  await Printing.layoutPdf(
    name: titulo,
    format: PdfPageFormat.a4,
    onLayout: (_) async => doc.save(),
  );
}

/// Linha de indicadores (rótulo em cima, valor embaixo).
pw.Widget pdfIndicadores(List<(String, String)> itens) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 12),
  child: pw.Row(
    children: [
      for (final (rotulo, valor) in itens)
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 6),
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.5, color: PdfColors.grey),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(rotulo, style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 2),
                pw.Text(
                  valor,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  ),
);

pw.Widget pdfTituloSecao(String texto) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 8, bottom: 6),
  child: pw.Text(
    texto,
    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
  ),
);

/// Tabela com cabeçalho; [direita] lista os índices de colunas numéricas.
pw.Widget pdfTabela(
  List<String> cabecalho,
  List<List<String>> linhas, {
  Set<int> direita = const {},
}) => pw.TableHelper.fromTextArray(
  headers: cabecalho,
  data: linhas,
  headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
  cellStyle: const pw.TextStyle(fontSize: 9),
  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
  border: const pw.TableBorder(
    horizontalInside: pw.BorderSide(width: 0.3, color: PdfColors.grey),
    bottom: pw.BorderSide(width: 0.3, color: PdfColors.grey),
  ),
  cellAlignments: {
    for (var i = 0; i < cabecalho.length; i++)
      i: direita.contains(i)
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
  },
  headerAlignments: {
    for (var i = 0; i < cabecalho.length; i++)
      i: direita.contains(i)
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
  },
);
