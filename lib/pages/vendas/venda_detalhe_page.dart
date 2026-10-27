import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/permissoes.dart';
import '../../core/sessao.dart';
import '../../data/dados.dart';
import '../../data/venda_repository.dart';
import '../../models/venda.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pendente_icon.dart';
import 'comprovante_page.dart';

/// Quem pode ver a venda e o comprovante: quem tem acesso ao histórico ou o
/// próprio vendedor.
bool podeVerVenda(Venda v) =>
    Sessao.instancia.pode(Permissao.historico) ||
    v.vendedorId == Sessao.instancia.atual.id;

/// Pede o motivo e cancela/estorna a venda (devolve estoque e, se houve
/// dinheiro, registra o estorno no caixa aberto).
Future<void> estornarVenda(BuildContext context, Venda venda) async {
  final motivo = await pedirTexto(
    context,
    titulo: 'Cancelar e estornar venda #${venda.codigo}',
    rotulo: 'Motivo obrigatório',
    confirmar: 'Estornar',
    minimo: 5,
    maximo: 255,
    linhas: 3,
    ajuda:
        'Os itens voltam ao estoque. Valores em dinheiro saem do caixa '
        'aberto.',
  );
  if (motivo == null || !context.mounted) return;
  executar(
    context,
    () => VendaRepository().cancelar(
      venda,
      motivo,
      caixaAberto: Dados.caixaAberto.value,
      produtos: Dados.produtosPorId,
    ),
    sucesso: 'Venda #${venda.codigo} cancelada e estoque devolvido.',
  );
}

/// Itens (com venda e custo), pagamentos e cancelamento de uma venda.
class DetalhesVenda extends StatelessWidget {
  final Venda venda;
  const DetalhesVenda({super.key, required this.venda});

  @override
  Widget build(BuildContext context) {
    final v = venda;
    final t = Theme.of(context);
    final pequeno = t.textTheme.bodySmall;
    final negrito = t.textTheme.labelLarge;
    Widget celula(String s, {TextStyle? estilo, bool direita = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Text(
            s,
            style: estilo,
            textAlign: direita ? TextAlign.right : TextAlign.left,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: IntrinsicColumnWidth(),
            2: FlexColumnWidth(1.6),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(1.7),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: t.colorScheme.outlineVariant),
                ),
              ),
              children: [
                celula('Produto', estilo: negrito),
                celula('Qtd.', estilo: negrito, direita: true),
                celula('Venda', estilo: negrito, direita: true),
                celula('Custo', estilo: negrito, direita: true),
                celula('Total', estilo: negrito, direita: true),
              ],
            ),
            for (final i in v.itens)
              TableRow(
                children: [
                  celula(i.nome),
                  celula('${i.quantidade}', direita: true),
                  celula(formatarMoeda(i.precoUnitario), direita: true),
                  celula(
                    formatarMoeda(i.custoUnitario),
                    estilo: pequeno,
                    direita: true,
                  ),
                  celula(formatarMoeda(i.subtotal), direita: true),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        _linha('Subtotal', formatarMoeda(v.subtotal)),
        if (v.desconto > 0)
          _linha(
            v.descontoPercentual
                ? 'Desconto (${NumberFormat('#,##0.##', 'pt_BR').format(v.descontoInformado)}%)'
                : 'Desconto',
            '- ${formatarMoeda(v.desconto)}',
          ),
        _linha(
          'Total',
          formatarMoeda(v.total),
          estilo: t.textTheme.titleMedium,
        ),
        _linha('Custo total', formatarMoeda(v.custoTotal), estilo: pequeno),
        const SizedBox(height: 12),
        Text('Pagamento', style: negrito),
        const SizedBox(height: 4),
        if (v.pagamentos.isEmpty)
          Text(v.formaPagamento)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in v.pagamentos)
                Chip(
                  label: Text(
                    [
                      '${p.forma} ${formatarMoeda(p.valor)}',
                      if (p.forma == FormaPagamento.credito) '${p.parcelas}x',
                      if (p.troco > 0) 'troco ${formatarMoeda(p.troco)}',
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        if (v.clienteNome != null) ...[
          const SizedBox(height: 8),
          Text('Cliente: ${v.clienteNome}'),
        ],
        if (v.isCancelada) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              [
                'Cancelada'
                    '${v.canceladaPorNome == null ? '' : ' por ${v.canceladaPorNome}'}'
                    '${v.canceladaEm == null ? '' : ' em ${formatarDataHora(v.canceladaEm!)}'}',
                if ((v.motivoCancelamento ?? '').isNotEmpty)
                  v.motivoCancelamento!,
              ].join('\n'),
              style: TextStyle(color: t.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ],
    );
  }

  Widget _linha(String rotulo, String valor, {TextStyle? estilo}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(rotulo, style: estilo),
        Text(valor, style: estilo),
      ],
    ),
  );
}

/// Botões de ação de uma venda (comprovante, edição e estorno).
class AcoesVenda extends StatelessWidget {
  final Venda venda;

  /// Repassado ao comprovante para os botões "Nova venda", "Histórico"...
  final void Function(String modulo)? abrirModulo;

  const AcoesVenda({super.key, required this.venda, this.abrirModulo});

  @override
  Widget build(BuildContext context) {
    void abrir({bool editar = false, bool imprimir = false}) =>
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ComprovantePage(
              vendaId: venda.id,
              editar: editar,
              imprimir: imprimir,
              abrirModulo: abrirModulo,
            ),
          ),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_note),
          label: const Text('Editar nota completa'),
          onPressed: () => abrir(editar: true),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.print_outlined),
          label: const Text('Reimprimir'),
          onPressed: () => abrir(imprimir: true),
        ),
        if (!venda.isCancelada &&
            Sessao.instancia.pode(Permissao.cancelarVendas))
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            icon: const Icon(Icons.undo),
            label: const Text('Estornar'),
            onPressed: () => estornarVenda(context, venda),
          ),
      ],
    );
  }
}

/// Página com os detalhes de uma venda.
class VendaDetalhePage extends StatefulWidget {
  final String vendaId;
  const VendaDetalhePage({super.key, required this.vendaId});

  @override
  State<VendaDetalhePage> createState() => _VendaDetalhePageState();
}

class _VendaDetalhePageState extends State<VendaDetalhePage> {
  late final _stream = VendaRepository().watch(widget.vendaId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Venda?>(
      stream: _stream,
      builder: (context, snap) {
        final v = snap.data;
        final cores = Theme.of(context).colorScheme;
        Widget corpo;
        if (snap.hasError) {
          corpo = Center(child: Text('Erro ao carregar: ${snap.error}'));
        } else if (snap.connectionState == ConnectionState.waiting) {
          corpo = const Center(child: CircularProgressIndicator());
        } else if (v == null || !podeVerVenda(v)) {
          corpo = const EstadoVazio(
            icone: Icons.search_off,
            titulo: 'Venda não encontrada.',
          );
        } else {
          corpo = LarguraMaxima(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (v.isCancelada)
                  Card(
                    color: cores.error,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'VENDA CANCELADA',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cores.onError),
                      ),
                    ),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    v.comandaNome == null
                        ? 'Venda direta'
                        : 'Comanda ${v.comandaNome}',
                  ),
                  subtitle: Text(
                    '${formatarDataHora(v.data)}\n'
                    'Atendente: ${v.vendedorNome}',
                  ),
                  isThreeLine: true,
                ),
                const Divider(),
                DetalhesVenda(venda: v),
                const SizedBox(height: 16),
                AcoesVenda(venda: v),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(v == null ? 'Venda' : 'Venda #${v.codigo}'),
            actions: [
              if (v != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: PendenteIcon(pendente: v.pendente),
                ),
            ],
          ),
          body: corpo,
        );
      },
    );
  }
}
