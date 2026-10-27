import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dinheiro.dart';
import '../../core/formatters.dart';
import '../../core/regra_exception.dart';
import '../../data/comanda_repository.dart';
import '../../data/dados.dart';
import '../../data/venda_repository.dart';
import '../../models/comanda.dart';
import '../../models/venda.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pagamento_form.dart';
import '../../widgets/pendente_icon.dart';
import '../shell/app_shell.dart';
import '../vendas/comprovante_page.dart';
import '../vendas/pdv_page.dart';

/// Comandas abertas: o consumo sai do estoque quando é lançado e o
/// pagamento acontece no fechamento, que gera a venda.
class ComandasPage extends StatefulWidget {
  const ComandasPage({super.key});

  @override
  State<ComandasPage> createState() => _ComandasPageState();
}

class _ComandasPageState extends State<ComandasPage> {
  final _repo = ComandaRepository();
  late final _stream = _repo.watchAbertas();

  static final _hora = DateFormat('HH:mm');

  Future<void> _nova() async {
    final nome = TextEditingController();
    final pessoas = TextEditingController(text: '1');
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        void criar() {
          final ok = executar(
            ctx,
            () =>
                _repo.criar(nome.text, int.tryParse(pessoas.text.trim()) ?? 1),
            sucesso: 'Comanda aberta.',
          );
          if (ok) Navigator.pop(ctx);
        }

        return AlertDialog(
          title: const Text('Nova comanda'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nome,
                  autofocus: true,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    hintText: 'Ex.: João ou Mesa 4',
                  ),
                  onSubmitted: (_) => criar(),
                ),
                TextField(
                  controller: pessoas,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Pessoas'),
                  onSubmitted: (_) => criar(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Voltar'),
            ),
            FilledButton(onPressed: criar, child: const Text('Abrir comanda')),
          ],
        );
      },
    );
  }

  Future<void> _renomear(Comanda c) async {
    final nome = await pedirTexto(
      context,
      titulo: 'Renomear comanda',
      rotulo: 'Nome',
      inicial: c.nome,
      confirmar: 'Salvar',
      minimo: 1,
      maximo: 100,
    );
    if (nome == null || !mounted) return;
    executar(
      context,
      () => _repo.renomear(c, nome),
      sucesso: 'Comanda renomeada.',
    );
  }

  Future<void> _cancelar(Comanda c) async {
    final ok = await confirmar(
      context,
      titulo: 'Cancelar comanda',
      mensagem: 'Cancelar a comanda e devolver todos os itens ao estoque?',
      confirmarTexto: 'Cancelar comanda',
    );
    if (!ok || !mounted) return;
    executar(
      context,
      () => _repo.cancelar(c, Dados.produtosPorId),
      sucesso: 'Comanda cancelada e estoque devolvido.',
    );
  }

  void _alterar(Comanda c, ItemComanda item, int quantidade) {
    executar(
      context,
      () => _repo.alterarQuantidade(
        c,
        item,
        quantidade < 1 ? 1 : quantidade,
        Dados.produtosPorId[item.produtoId],
      ),
      sucesso: 'Quantidade atualizada.',
    );
  }

  Future<void> _digitarQuantidade(Comanda c, ItemComanda item) async {
    final texto = await pedirTexto(
      context,
      titulo: item.nome,
      rotulo: 'Quantidade',
      inicial: '${item.quantidade}',
      confirmar: 'Atualizar',
      minimo: 1,
      maximo: 6,
    );
    if (texto == null || !mounted) return;
    final q = int.tryParse(texto);
    if (q == null) {
      mostrarErro(context, StateError('Quantidade inválida.'));
      return;
    }
    _alterar(c, item, q);
  }

  Future<void> _remover(Comanda c, ItemComanda item) async {
    final ok = await confirmar(
      context,
      titulo: 'Remover item',
      mensagem: 'Remover este item e devolver ao estoque?',
      confirmarTexto: 'Remover',
    );
    if (!ok || !mounted) return;
    executar(
      context,
      () => _repo.alterarQuantidade(
        c,
        item,
        0,
        Dados.produtosPorId[item.produtoId],
      ),
      sucesso: 'Item removido e estoque devolvido.',
    );
  }

  Future<void> _adicionarItens(Comanda c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Adicionar itens à ${c.nome}')),
          body: PdvPage(comandaId: c.id),
        ),
      ),
    );
  }

  Future<void> _fechar(Comanda c) async {
    final venda = await showDialog<Venda>(
      context: context,
      builder: (_) => _FecharComandaDialog(comanda: c),
    );
    if (venda == null || !mounted) return;
    avisar(context, 'Comanda fechada.');
    final shell = context;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComprovantePage(
          vendaId: venda.id,
          abrirModulo: (m) => AppShell.abrir(shell, m),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nova comanda'),
        onPressed: _nova,
      ),
      body: StreamBuilder<List<Comanda>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erro ao carregar: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lista = snap.data!;
          if (lista.isEmpty) {
            return const EstadoVazio(
              icone: Icons.receipt_long_outlined,
              titulo: 'Nenhuma comanda aberta',
              mensagem: 'Toque em "Nova comanda" para abrir uma.',
            );
          }
          final total = lista.fold<int>(0, (s, c) => s + c.totalCentavos);
          return LayoutBuilder(
            builder: (context, box) {
              const espaco = 12.0;
              final largura = box.maxWidth - 32;
              final colunas = (largura / 400).floor().clamp(1, 4);
              final larguraCard = (largura - espaco * (colunas - 1)) / colunas;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Text(
                    '${lista.length} ${lista.length == 1 ? 'comanda aberta' : 'comandas abertas'}'
                    ' · consumo ${formatarMoeda(deCentavos(total))}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: espaco,
                    runSpacing: espaco,
                    children: [
                      for (final c in lista)
                        SizedBox(width: larguraCard, child: _card(c)),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _card(Comanda c) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${c.codigo}', style: t.textTheme.labelSmall),
                      Text(
                        c.nome,
                        style: t.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PendenteIcon(pendente: c.pendente),
                const SizedBox(width: 6),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Aberta'),
                  backgroundColor: t.colorScheme.secondaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_outline, size: 16),
                    const SizedBox(width: 2),
                    Text(
                      '${c.pessoas} ${c.pessoas == 1 ? 'pessoa' : 'pessoas'}',
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule, size: 16),
                    const SizedBox(width: 2),
                    Text('desde ${_hora.format(c.abertaEm)}'),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            if (c.itens.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nenhum item lançado.',
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall,
                ),
              ),
            for (final i in c.itens) _itemLinha(c, i),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${c.quantidadeItens} ${c.quantidadeItens == 1 ? 'item' : 'itens'}',
                  ),
                ),
                Text(formatarMoeda(c.total), style: t.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar itens'),
                  onPressed: () => _adicionarItens(c),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Renomear'),
                  onPressed: () => _renomear(c),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Fechar'),
                  onPressed: c.itens.isEmpty ? null : () => _fechar(c),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: t.colorScheme.error,
                  ),
                  onPressed: () => _cancelar(c),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemLinha(Comanda c, ItemComanda i) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.nome, overflow: TextOverflow.ellipsis),
                Text(
                  '${i.codigo.isEmpty ? '' : '${i.codigo} · '}${formatarMoeda(i.precoUnitario)}',
                  style: t.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Diminuir',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: i.quantidade <= 1
                ? null
                : () => _alterar(c, i, i.quantidade - 1),
          ),
          InkWell(
            onTap: () => _digitarQuantidade(c, i),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              constraints: const BoxConstraints(minWidth: 32),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: t.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${i.quantidade}', textAlign: TextAlign.center),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Aumentar',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _alterar(c, i, i.quantidade + 1),
          ),
          SizedBox(
            width: 84,
            child: Text(formatarMoeda(i.total), textAlign: TextAlign.right),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remover',
            icon: Icon(Icons.close, color: t.colorScheme.error),
            onPressed: () => _remover(c, i),
          ),
        ],
      ),
    );
  }
}

/// Fechamento da comanda: desconto e pagamento, gerando a venda.
class _FecharComandaDialog extends StatefulWidget {
  final Comanda comanda;
  const _FecharComandaDialog({required this.comanda});

  @override
  State<_FecharComandaDialog> createState() => _FecharComandaDialogState();
}

class _FecharComandaDialogState extends State<_FecharComandaDialog> {
  final _pag = PagamentoController();
  String? _erro;

  @override
  void dispose() {
    _pag.dispose();
    super.dispose();
  }

  void _confirmar() {
    final c = widget.comanda;
    try {
      final total = _pag.totalCentavos(c.totalCentavos);
      final venda = VendaRepository().fecharComanda(
        comanda: c,
        caixa: Dados.caixaAberto.value,
        produtos: Dados.produtosPorId,
        descontoPercentual: _pag.descontoPercentual,
        descontoInformado: _pag.descontoInformado,
        pagamentos: _pag.montar(total),
      );
      Navigator.pop(context, venda);
    } catch (e) {
      setState(
        () => _erro = switch (e) {
          RegraException(:final mensagem) => mensagem,
          StateError(:final message) => message,
          _ => 'Não foi possível concluir: $e',
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comanda;
    final t = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text('Fechar comanda'),
      content: SizedBox(
        width: 460,
        child: ListenableBuilder(
          listenable: _pag,
          builder: (context, _) {
            final desconto = _pag.descontoCentavos(c.totalCentavos);
            final total = c.totalCentavos - desconto;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${c.nome} · ${formatarMoeda(c.total)}',
                  style: t.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                PagamentoForm(
                  controller: _pag,
                  subtotalCentavos: c.totalCentavos,
                ),
                const Divider(height: 24),
                _linha('Subtotal', formatarMoeda(c.total)),
                if (desconto > 0)
                  _linha(
                    'Desconto',
                    '- ${formatarMoeda(deCentavos(desconto))}',
                  ),
                _linha(
                  'Total',
                  formatarMoeda(deCentavos(total)),
                  estilo: t.textTheme.titleLarge,
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 8),
                  Text(_erro!, style: TextStyle(color: t.colorScheme.error)),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Fechar e gerar venda'),
        ),
      ],
    );
  }

  Widget _linha(String a, String b, {TextStyle? estilo}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(a, style: estilo),
        Text(b, style: estilo),
      ],
    ),
  );
}
