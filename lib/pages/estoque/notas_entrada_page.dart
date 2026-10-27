import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/impressao/nota_entrada_pdf.dart';
import '../../data/nota_entrada_repository.dart';
import '../../models/nota_entrada.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/pendente_icon.dart';
import 'estoque_widgets.dart';
import 'nota_entrada_detalhe_page.dart';
import 'nota_entrada_form_page.dart';

/// Notas de entrada de mercadorias (controle interno).
class NotasEntradaPage extends StatefulWidget {
  const NotasEntradaPage({super.key});

  @override
  State<NotasEntradaPage> createState() => _NotasEntradaPageState();
}

class _NotasEntradaPageState extends State<NotasEntradaPage> {
  static const _porPagina = 30;
  static final _dia = DateFormat('dd/MM/yyyy');

  final _repo = NotaEntradaRepository();
  Periodo _periodo = Periodo.mesAtual();
  late Stream<List<NotaEntrada>> _stream = _abrir();
  int _pagina = 0;

  Stream<List<NotaEntrada>> _abrir() =>
      _repo.watchPeriodo(_periodo.inicio, _periodo.fim);

  void _nova() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const NotaEntradaFormPage()),
  );

  void _abrirNota(NotaEntrada n) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => NotaEntradaDetalhePage(id: n.id)),
  );

  void _editar(NotaEntrada n) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => NotaEntradaFormPage(nota: n)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nova,
        icon: const Icon(Icons.add),
        label: const Text('Nova nota'),
      ),
      body: LarguraMaxima(
        largura: 1000,
        child: StreamBuilder<List<NotaEntrada>>(
          stream: _stream,
          builder: (context, snap) {
            final lista = snap.data ?? const <NotaEntrada>[];
            final paginas = (lista.length / _porPagina).ceil();
            final pagina = paginas == 0 ? 0 : _pagina.clamp(0, paginas - 1);
            final itens = lista
                .skip(pagina * _porPagina)
                .take(_porPagina)
                .toList();
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _cabecalho(lista.length)),
                if (snap.hasError)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Erro ao carregar: ${snap.error}'),
                    ),
                  )
                else if (!snap.hasData)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (lista.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EstadoVazio(
                      icone: Icons.local_shipping_outlined,
                      titulo: 'Nenhuma nota no período',
                      mensagem: 'Registre uma nota para dar entrada de mercadorias no estoque.',
                    ),
                  )
                else ...[
                  SliverList.builder(
                    itemCount: itens.length,
                    itemBuilder: (_, i) => _card(itens[i]),
                  ),
                  SliverToBoxAdapter(
                    child: Paginacao(
                      pagina: pagina,
                      totalPaginas: paginas,
                      registros: lista.length,
                      onChanged: (p) => setState(() => _pagina = p),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cabecalho(int total) {
    final cores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cores.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: cores.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Documento de controle interno: registra as mercadorias '
                    'recebidas, soma as quantidades ao estoque e atualiza o '
                    'custo dos produtos. Não é NF-e e não substitui documento '
                    'fiscal.',
                    style: TextStyle(color: cores.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FiltroPeriodo(
                periodo: _periodo,
                onChanged: (p) => setState(() {
                  _periodo = p;
                  _pagina = 0;
                  _stream = _abrir();
                }),
              ),
              Text('$total documento(s) no histórico'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(NotaEntrada n) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '#${numeroNotaEntrada(n)} · '
                              '${n.numero.isEmpty ? 'Sem número' : 'Nota ${n.numero}'}',
                              style: t.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 4),
                          PendenteIcon(pendente: n.pendente),
                        ],
                      ),
                      Text(
                        n.fornecedor.isEmpty
                            ? 'Fornecedor não informado'
                            : n.fornecedor,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatarMoeda(n.total),
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(_dia.format(n.dataEntrada)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${n.itens.length} produto(s) · ${n.quantidadeTotal} unidade(s)',
            ),
            Text(
              [
                'Criada ${formatarDataHora(n.criadoEm)}',
                if (n.criadoPorNome.isNotEmpty) 'por ${n.criadoPorNome}',
                if (n.editadoPorNome != null)
                  '· Editada por ${n.editadoPorNome}',
              ].join(' '),
              style: t.bodySmall,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _editar(n),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _abrirNota(n),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Abrir / imprimir'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
