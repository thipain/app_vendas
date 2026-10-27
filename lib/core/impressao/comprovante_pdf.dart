import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/config_loja.dart';
import '../../models/venda.dart';
import '../formatters.dart';

/// Limite do texto editado do comprovante.
const limiteTextoComprovante = 12000;

const _tracos = '--------------------------------';

String _data(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d);

/// Linhas de pagamento como no comprovante ("Crédito 3x", "Troco").
List<(String, String)> linhasPagamentoComprovante(Venda v) {
  if (v.pagamentos.isEmpty) {
    return [('Pagamento', v.formaPagamento)];
  }
  final linhas = <(String, String)>[];
  for (final p in v.pagamentos) {
    final rotulo = p.forma == FormaPagamento.credito
        ? '${p.forma} ${p.parcelas}x'
        : p.forma;
    linhas.add((rotulo, formatarMoeda(p.valor)));
  }
  if (v.troco > 0) linhas.add(('Troco', formatarMoeda(v.troco)));
  return linhas;
}

/// Versão em texto simples do comprovante padrão, usada para preencher o
/// editor de "nota completa".
String textoComprovantePadrao(Venda v, ConfigLoja loja) {
  final b = StringBuffer()..writeln(loja.nomeLoja);
  for (final s in [loja.documento, loja.telefone, loja.endereco]) {
    if (s.trim().isNotEmpty) b.writeln(s.trim());
  }
  b.writeln('COMPROVANTE NÃO FISCAL');
  if (v.isCancelada) b.writeln('VENDA CANCELADA');
  b
    ..writeln(_tracos)
    ..writeln('Venda: #${v.codigo}')
    ..writeln('Data: ${_data(v.data)}')
    ..writeln('Atendente: ${v.vendedorNome}');
  if (v.comandaNome != null) b.writeln('Comanda: ${v.comandaNome}');
  if (v.clienteNome != null) b.writeln('Cliente: ${v.clienteNome}');
  b.writeln(_tracos);
  for (final i in v.itens) {
    b
      ..writeln(i.nome)
      ..writeln(
        '${i.quantidade} x ${formatarMoeda(i.precoUnitario)} = '
        '${formatarMoeda(i.subtotal)}',
      );
  }
  b
    ..writeln(_tracos)
    ..writeln('Subtotal: ${formatarMoeda(v.subtotal)}')
    ..writeln('Desconto: - ${formatarMoeda(v.desconto)}')
    ..writeln('TOTAL: ${formatarMoeda(v.total)}');
  for (final (rotulo, valor) in linhasPagamentoComprovante(v)) {
    b.writeln('$rotulo: $valor');
  }
  if (v.isCancelada) {
    b.writeln(_tracos);
    if (v.canceladaEm != null) {
      b.writeln('Cancelada em ${_data(v.canceladaEm!)}');
    }
    if ((v.motivoCancelamento ?? '').isNotEmpty) {
      b.writeln(v.motivoCancelamento);
    }
  }
  if (loja.mensagemComprovante.trim().isNotEmpty) {
    b
      ..writeln(_tracos)
      ..writeln(loja.mensagemComprovante.trim());
  }
  return b.toString().trimRight();
}

/// As fontes padrão do PDF só têm Latin-1: troca o que estiver fora dele.
String _latin1(String s) {
  const trocas = {
    '—': '-',
    '–': '-',
    '−': '-',
    '•': '*',
    '…': '...',
    '“': '"',
    '”': '"',
    '‘': "'",
    '’': "'",
    ' ': ' ',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (r <= 0xFF) {
      b.write(c);
    } else {
      b.write(trocas[c] ?? '?');
    }
  }
  return b.toString();
}

/// Gera o PDF do comprovante em bobina de 80 mm. Quando [textoLivre] (ou o
/// texto salvo na venda) não está vazio, imprime somente esse texto.
Future<Uint8List> gerarComprovantePdf(
  Venda v,
  ConfigLoja loja, {
  String? textoLivre,
}) async {
  final livre = (textoLivre ?? v.textoComprovante ?? '').trim();
  final fonte = pw.Font.courier();
  final negrito = pw.Font.courierBold();
  final doc = pw.Document(
    title: 'Venda #${v.codigo}',
    theme: pw.ThemeData.withFont(base: fonte, bold: negrito),
  );
  const tam = 8.5;
  final normal = pw.TextStyle(font: fonte, fontSize: tam);
  final forte = pw.TextStyle(font: negrito, fontSize: tam);
  pw.Widget t(String s, {pw.TextStyle? estilo, pw.TextAlign? alinhar}) =>
      pw.Text(_latin1(s), style: estilo ?? normal, textAlign: alinhar);
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

  final conteudo = <pw.Widget>[];
  if (livre.isNotEmpty) {
    for (final l in livre.split('\n')) {
      conteudo.add(t(l.isEmpty ? ' ' : l));
    }
  } else {
    pw.ImageProvider? logo;
    if (loja.logo.isNotEmpty) {
      try {
        logo = pw.MemoryImage(base64Decode(loja.logo));
      } catch (_) {
        logo = null;
      }
    }
    conteudo.addAll([
      pw.Center(
        child: logo != null
            ? pw.SizedBox(height: 40, child: pw.Image(logo, height: 40))
            : t(
                loja.nomeLoja.isEmpty ? 'A' : loja.nomeLoja[0].toUpperCase(),
                estilo: pw.TextStyle(font: negrito, fontSize: 18),
              ),
      ),
      pw.SizedBox(height: 4),
      t(
        loja.nomeLoja,
        estilo: pw.TextStyle(font: negrito, fontSize: 11),
        alinhar: pw.TextAlign.center,
      ),
      for (final s in [loja.documento, loja.telefone, loja.endereco])
        if (s.trim().isNotEmpty) t(s.trim(), alinhar: pw.TextAlign.center),
      pw.SizedBox(height: 4),
      t('COMPROVANTE NÃO FISCAL', estilo: forte, alinhar: pw.TextAlign.center),
      if (v.isCancelada)
        t(
          'VENDA CANCELADA',
          estilo: pw.TextStyle(
            font: negrito,
            fontSize: 10,
            color: PdfColors.red,
          ),
          alinhar: pw.TextAlign.center,
        ),
      separador(),
      linha('Venda', '#${v.codigo}'),
      linha('Data', _data(v.data)),
      linha('Atendente', v.vendedorNome),
      if (v.comandaNome != null) linha('Comanda', v.comandaNome!),
      if (v.clienteNome != null) linha('Cliente', v.clienteNome!),
      separador(),
      pw.Row(
        children: [
          pw.Expanded(child: t('Item', estilo: forte)),
          pw.SizedBox(width: 28, child: t('Qtd.', estilo: forte)),
          t('Total', estilo: forte),
        ],
      ),
      for (final i in v.itens)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    t(i.nome),
                    t(
                      '${formatarMoeda(i.precoUnitario)} un.',
                      estilo: pw.TextStyle(
                        font: fonte,
                        fontSize: 7.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 28, child: t('${i.quantidade}')),
              t(formatarMoeda(i.subtotal)),
            ],
          ),
        ),
      separador(),
      linha('Subtotal', formatarMoeda(v.subtotal)),
      linha('Desconto', '- ${formatarMoeda(v.desconto)}'),
      linha('Total', formatarMoeda(v.total), destaque: true),
      pw.SizedBox(height: 2),
      for (final (rotulo, valor) in linhasPagamentoComprovante(v))
        linha(rotulo, valor),
      if (v.isCancelada) ...[
        separador(),
        if (v.canceladaEm != null)
          t('Cancelada em ${_data(v.canceladaEm!)}', estilo: forte),
        if ((v.motivoCancelamento ?? '').isNotEmpty) t(v.motivoCancelamento!),
      ],
      if (loja.mensagemComprovante.trim().isNotEmpty) ...[
        separador(),
        t(loja.mensagemComprovante.trim(), alinhar: pw.TextAlign.center),
      ],
    ]);
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: conteudo,
      ),
    ),
  );
  return doc.save();
}

/// Abre a impressão do sistema (Android e Windows).
Future<void> imprimirComprovante(
  Venda v,
  ConfigLoja loja, {
  String? textoLivre,
}) async {
  final bytes = await gerarComprovantePdf(v, loja, textoLivre: textoLivre);
  await Printing.layoutPdf(
    name: 'Venda ${v.codigo}',
    format: PdfPageFormat.roll80,
    onLayout: (_) async => bytes,
  );
}

/// Compartilha o PDF do comprovante (WhatsApp, e-mail, salvar...).
Future<void> compartilharComprovante(Venda v, ConfigLoja loja) async {
  final bytes = await gerarComprovantePdf(v, loja);
  await Printing.sharePdf(bytes: bytes, filename: 'venda_${v.codigo}.pdf');
}
