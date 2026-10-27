import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/impressao/nota_entrada_pdf.dart';
import '../../data/config_repository.dart';
import '../../data/dados.dart';
import '../../data/nota_entrada_repository.dart';
import '../../models/nota_entrada.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pendente_icon.dart';
import 'nota_entrada_form_page.dart';

/// Nota de entrada em A4, pronta para imprimir ou compartilhar.
class NotaEntradaDetalhePage extends StatefulWidget {
  final String id;
  const NotaEntradaDetalhePage({super.key, required this.id});

  @override
  State<NotaEntradaDetalhePage> createState() => _NotaEntradaDetalhePageState();
}

class _NotaEntradaDetalhePageState extends State<NotaEntradaDetalhePage> {
  late final _stream = NotaEntradaRepository().watch(widget.id);

  Future<void> _imprimir(NotaEntrada n) async {
    try {
      await imprimirNotaEntrada(
        n,
        loja: ConfigRepository.atual.value,
        produtos: Dados.produtosPorId,
      );
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  Future<void> _compartilhar(NotaEntrada n) async {
    try {
      await compartilharNotaEntrada(
        n,
        loja: ConfigRepository.atual.value,
        produtos: Dados.produtosPorId,
      );
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  void _editar(NotaEntrada n) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NotaEntradaFormPage(nota: n, abrirNotaAoSalvar: false),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NotaEntrada?>(
      stream: _stream,
      builder: (context, snap) {
        final nota = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    nota == null
                        ? 'Nota de entrada'
                        : 'Nota de entrada #${numeroNotaEntrada(nota)}',
                  ),
                ),
                const SizedBox(width: 6),
                PendenteIcon(pendente: nota?.pendente ?? false),
              ],
            ),
            actions: nota == null
                ? null
                : [
                    IconButton(
                      tooltip: 'Editar antes de imprimir',
                      onPressed: () => _editar(nota),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Compartilhar PDF',
                      onPressed: () => _compartilhar(nota),
                      icon: const Icon(Icons.share_outlined),
                    ),
                    IconButton(
                      tooltip: 'Imprimir nota',
                      onPressed: () => _imprimir(nota),
                      icon: const Icon(Icons.print_outlined),
                    ),
                  ],
          ),
          body: _corpo(snap, nota),
          bottomNavigationBar: nota == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Voltar às notas'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _editar(nota),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar antes de imprimir'),
                        ),
                        FilledButton.icon(
                          onPressed: () => _imprimir(nota),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Imprimir nota'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _corpo(AsyncSnapshot<NotaEntrada?> snap, NotaEntrada? nota) {
    if (snap.hasError) {
      return Center(child: Text('Erro ao carregar: ${snap.error}'));
    }
    if (snap.connectionState == ConnectionState.waiting && nota == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (nota == null) {
      return const EstadoVazio(
        icone: Icons.search_off,
        titulo: 'Nota não encontrada',
      );
    }
    final loja = ConfigRepository.atual.value;
    final produtos = Dados.produtosPorId;
    return PdfPreview(
      build: (formato) =>
          gerarNotaEntradaPdf(nota, loja: loja, produtos: produtos),
      initialPageFormat: PdfPageFormat.a4,
      allowPrinting: false,
      allowSharing: false,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      maxPageWidth: 820,
      pdfFileName: 'nota-entrada-${numeroNotaEntrada(nota)}.pdf',
    );
  }
}
