import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/config_loja.dart';
import '../../models/pedido.dart';
import '../formatters.dart';
import 'comprovante_pdf.dart';

/// Via do pedido de delivery em bobina de 80 mm: separação dos itens e
/// tudo o que o entregador precisa (endereço, telefone, cobrança e troco).
Future<Uint8List> gerarViaPedidoPdf(Pedido p, ConfigLoja loja) async {
  final fonte = pw.Font.courier();
  final negrito = pw.Font.courierBold();
  final doc = pw.Document(
    title: 'Pedido #${p.codigo}',
    theme: pw.ThemeData.withFont(base: fonte, bold: negrito),
  );
  const tam = 8.5;
  final normal = pw.TextStyle(font: fonte, fontSize: tam);
  final forte = pw.TextStyle(font: negrito, fontSize: tam);
  final grande = pw.TextStyle(font: negrito, fontSize: 11);
  pw.Widget t(String s, {pw.TextStyle? estilo, pw.TextAlign? alinhar}) =>
      pw.Text(latin1Pdf(s), style: estilo ?? normal, textAlign: alinhar);
  pw.Widget linha(String a, String b, {bool destaque = false}) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: t(a, estilo: destaque ? forte : normal)),
      t(b, estilo: destaque ? forte : normal),
    ],
  );
  pw.Widget separador() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Divider(
      height: 1,
      thickness: 0.5,
      borderStyle: pw.BorderStyle.dashed,
    ),
  );
  final hora = DateFormat('dd/MM/yyyy HH:mm');

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          t(loja.nomeLoja, estilo: grande, alinhar: pw.TextAlign.center),
          if (loja.telefone.trim().isNotEmpty)
            t(loja.telefone.trim(), alinhar: pw.TextAlign.center),
          pw.SizedBox(height: 4),
          t(
            'DELIVERY #${p.codigo}',
            estilo: pw.TextStyle(font: negrito, fontSize: 13),
            alinhar: pw.TextAlign.center,
          ),
          t(hora.format(p.criadoEm), alinhar: pw.TextAlign.center),
          separador(),
          t('CLIENTE', estilo: forte),
          t(p.clienteNome, estilo: grande),
          t('Tel.: ${p.telefone}'),
          pw.SizedBox(height: 4),
          t('ENTREGAR EM', estilo: forte),
          t(p.endereco, estilo: grande),
          if (p.bairro.isNotEmpty) t('Bairro: ${p.bairro}', estilo: forte),
          if (p.referencia.isNotEmpty) t('Ref.: ${p.referencia}'),
          if (p.entregadorNome.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            linha('Entregador', p.entregadorNome),
          ],
          separador(),
          pw.Row(
            children: [
              pw.SizedBox(width: 28, child: t('Qtd.', estilo: forte)),
              pw.Expanded(child: t('Item', estilo: forte)),
              t('Total', estilo: forte),
            ],
          ),
          for (final i in p.itens)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 28,
                    child: t('${i.quantidade}', estilo: forte),
                  ),
                  pw.Expanded(child: t(i.nome)),
                  t(formatarMoeda(i.total)),
                ],
              ),
            ),
          separador(),
          linha('Subtotal', formatarMoeda(p.subtotal)),
          linha('Taxa de entrega', formatarMoeda(p.taxaEntrega)),
          linha('TOTAL', formatarMoeda(p.total), destaque: true),
          separador(),
          t('PAGAMENTO', estilo: forte),
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            child: t(p.instrucaoPagamento, estilo: grande),
          ),
          if (p.isDinheiro && p.troco > 0) ...[
            pw.SizedBox(height: 2),
            linha('Cliente paga com', formatarMoeda(p.trocoPara!)),
            linha('Levar de troco', formatarMoeda(p.troco), destaque: true),
          ],
          if (p.observacao.isNotEmpty) ...[
            separador(),
            t('OBSERVAÇÃO', estilo: forte),
            t(p.observacao),
          ],
          separador(),
          t(
            'Venda de bebida alcoólica só para maiores de 18 anos: '
            'confira o documento na entrega.',
            alinhar: pw.TextAlign.center,
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

Future<void> imprimirViaPedido(Pedido p, ConfigLoja loja) async {
  final bytes = await gerarViaPedidoPdf(p, loja);
  await Printing.layoutPdf(
    name: 'Pedido ${p.codigo}',
    format: PdfPageFormat.roll80,
    onLayout: (_) async => bytes,
  );
}

Future<void> compartilharViaPedido(Pedido p, ConfigLoja loja) async {
  final bytes = await gerarViaPedidoPdf(p, loja);
  await Printing.sharePdf(bytes: bytes, filename: 'pedido_${p.codigo}.pdf');
}
