import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/config_loja.dart';
import '../../models/nota_entrada.dart';
import '../../models/produto.dart';
import '../formatters.dart';

final _dia = DateFormat('dd/MM/yyyy');
final _diaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Número curto exibido como "#ABC123" (o id do Firestore é longo).
String numeroNotaEntrada(NotaEntrada n) =>
    n.id.length > 8 ? n.id.substring(0, 8).toUpperCase() : n.id.toUpperCase();

/// As fontes padrão do PDF só têm Latin-1; troca o resto por equivalentes.
String _t(String s) {
  final sb = StringBuffer();
  for (final r in s.runes) {
    if (r <= 0xFF) {
      sb.writeCharCode(r);
    } else if (r == 0x2014 || r == 0x2013 || r == 0x2212) {
      sb.write('-');
    } else if (r == 0x2192) {
      sb.write('->');
    } else if (r == 0x2018 || r == 0x2019) {
      sb.write("'");
    } else if (r == 0x201C || r == 0x201D) {
      sb.write('"');
    } else {
      sb.write('?');
    }
  }
  return sb.toString();
}

String _custo(double v) {
  var t = v.toStringAsFixed(4);
  while (t.endsWith('0') && t.split('.').last.length > 2) {
    t = t.substring(0, t.length - 1);
  }
  final partes = t.split('.');
  final inteiro = NumberFormat.decimalPattern('pt_BR')
      .format(int.parse(partes.first));
  return 'R\$ $inteiro,${partes.last}';
}

/// Nota de entrada interna em A4 (não é documento fiscal).
/// [produtos] é usado para mostrar o SKU e a unidade atuais de cada item.
Future<Uint8List> gerarNotaEntradaPdf(
  NotaEntrada nota, {
  required ConfigLoja loja,
  required Map<String, Produto> produtos,
  PdfPageFormat formato = PdfPageFormat.a4,
}) async {
  final cor = PdfColor.fromInt(loja.corPrimaria.toARGB32());
  final cinza = PdfColors.grey700;
  final doc = pw.Document(
    title: 'Nota de entrada #${numeroNotaEntrada(nota)}',
    author: loja.nomeLoja,
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    ),
  );

  pw.Widget marca() {
    if (loja.logo.isNotEmpty) {
      try {
        return pw.Container(
          width: 52,
          height: 52,
          child: pw.Image(
            pw.MemoryImage(base64Decode(loja.logo)),
            fit: pw.BoxFit.contain,
          ),
        );
      } catch (_) {}
    }
    final inicial = loja.nomeLoja.trim().isEmpty
        ? 'A'
        : loja.nomeLoja.trim().substring(0, 1).toUpperCase();
    return pw.Container(
      width: 52,
      height: 52,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: cor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        _t(inicial),
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 24,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget rotulo(String texto) => pw.Text(
    texto,
    style: pw.TextStyle(
      fontSize: 7.5,
      color: cinza,
      fontWeight: pw.FontWeight.bold,
    ),
  );

  pw.Widget meta(String titulo, String valor) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          rotulo(titulo),
          pw.SizedBox(height: 3),
          pw.Text(_t(valor), style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );

  final contato = [
    if (loja.documento.isNotEmpty) loja.documento,
    if (loja.telefone.isNotEmpty) loja.telefone,
  ].join(' · ');

  final linhas = [
    for (final i in nota.itens)
      [
        _t(produtos[i.produtoId]?.codigo ?? ''),
        _t(i.produtoNome),
        _t(produtos[i.produtoId]?.unidade ?? ''),
        '${i.quantidade}',
        _custo(i.custoUnitario),
        _t(formatarMoeda(i.custoTotal)),
      ],
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: formato,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        // Cabeçalho
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            marca(),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _t(loja.nomeLoja),
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (loja.endereco.isNotEmpty)
                    pw.Text(
                      _t(loja.endereco),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (contato.isNotEmpty)
                    pw.Text(
                      _t(contato),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: cor, width: 1.2),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'NOTA DE ENTRADA INTERNA',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '#${numeroNotaEntrada(nota)}',
                    style: pw.TextStyle(
                      fontSize: 16,
                      color: cor,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _t(
                      nota.numero.isEmpty
                          ? 'Sem número externo'
                          : 'Documento ${nota.numero}',
                    ),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        // Aviso
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.amber50,
            border: pw.Border.all(color: PdfColors.amber700, width: 0.8),
          ),
          child: pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 8.5),
              children: [
                pw.TextSpan(
                  text: 'CONTROLE INTERNO - ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(
                  text: _t(
                    'Este documento não é NF-e, NFC-e ou NFS-e e não '
                    'substitui documento fiscal autorizado pela SEFAZ.',
                  ),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 12),
        // Metadados
        pw.Row(
          children: [
            meta(
              'FORNECEDOR',
              nota.fornecedor.isEmpty ? 'Não informado' : nota.fornecedor,
            ),
            meta('DATA DA ENTRADA', _dia.format(nota.dataEntrada)),
            meta(
              'REGISTRADA POR',
              nota.criadoPorNome.isEmpty ? '-' : nota.criadoPorNome,
            ),
            meta('CRIADA EM', _diaHora.format(nota.criadoEm)),
          ],
        ),
        pw.SizedBox(height: 14),
        // Itens
        pw.TableHelper.fromTextArray(
          headers: [
            'SKU',
            'Produto',
            'Unidade',
            'Qtd.',
            'Custo unitário',
            'Total',
          ].map(_t).toList(),
          data: linhas,
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: pw.BoxDecoration(color: cor),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(3.6),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(0.8),
            4: const pw.FlexColumnWidth(1.5),
            5: const pw.FlexColumnWidth(1.5),
          },
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        ),
        pw.SizedBox(height: 14),
        // Rodapé
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    rotulo(_t('OBSERVAÇÕES')),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _t(
                        nota.observacao.isEmpty
                            ? 'Nenhuma observação registrada.'
                            : nota.observacao,
                      ),
                      style: const pw.TextStyle(fontSize: 9.5),
                    ),
                    if (nota.editadoEm != null) ...[
                      pw.SizedBox(height: 6),
                      pw.Text(
                        _t(
                          'Última edição: ${_diaHora.format(nota.editadoEm!)}'
                          ' por ${nota.editadoPorNome ?? '-'}',
                        ),
                        style: pw.TextStyle(fontSize: 8, color: cinza),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              flex: 2,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: cor, width: 1),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    rotulo('VALOR TOTAL DA NOTA'),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _t(formatarMoeda(nota.total)),
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '${nota.itens.length} tipo(s) de produto',
                      style: pw.TextStyle(fontSize: 8, color: cinza),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 56),
        // Assinaturas
        pw.Row(
          children: [
            for (final (i, texto) in [
              'Conferido por',
              'Responsável pelo recebimento',
            ].indexed) ...[
              if (i > 0) pw.SizedBox(width: 40),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Divider(color: PdfColors.grey800, thickness: 0.8),
                    pw.Text(_t(texto), style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Abre a janela de impressão do sistema com a nota em A4.
Future<void> imprimirNotaEntrada(
  NotaEntrada nota, {
  required ConfigLoja loja,
  required Map<String, Produto> produtos,
}) => Printing.layoutPdf(
  name: 'nota-entrada-${numeroNotaEntrada(nota)}',
  format: PdfPageFormat.a4,
  onLayout: (formato) => gerarNotaEntradaPdf(
    nota,
    loja: loja,
    produtos: produtos,
    formato: formato,
  ),
);

/// Compartilha o PDF (WhatsApp, e-mail, salvar arquivo...).
Future<void> compartilharNotaEntrada(
  NotaEntrada nota, {
  required ConfigLoja loja,
  required Map<String, Produto> produtos,
}) async {
  final bytes = await gerarNotaEntradaPdf(nota, loja: loja, produtos: produtos);
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'nota-entrada-${numeroNotaEntrada(nota)}.pdf',
  );
}
