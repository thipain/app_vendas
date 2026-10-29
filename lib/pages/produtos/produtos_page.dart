import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/permissoes.dart';
import '../../core/sessao.dart';
import '../../data/dados.dart';
import '../../data/produto_repository.dart';
import '../../models/produto.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pendente_icon.dart';
import '../../widgets/seletor.dart';
import '../estoque/estoque_widgets.dart';
import '../estoque/nota_entrada_form_page.dart';
import '../shell/app_shell.dart';
import 'produto_form_page.dart';

/// Produtos e estoque. [filtroInicial]: null (todos), 'baixo', 'zerados' ou
/// 'inativos'.
class ProdutosPage extends StatefulWidget {
  final String? filtroInicial;
  const ProdutosPage({super.key, this.filtroInicial});

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  static const _filtros = {
    'todos': 'Todos',
    'baixo': 'Repor',
    'zerados': 'Zerados',
    'inativos': 'Desativados',
  };
  static const _titulos = {
    'todos': 'Produtos e estoque',
    'baixo': 'Itens para repor',
    'zerados': 'Itens zerados',
    'inativos': 'Produtos desativados',
  };

  final _repo = ProdutoRepository();
  late String _filtro = _filtros.containsKey(widget.filtroInicial)
      ? widget.filtroInicial!
      : 'todos';
  String _busca = '';

  List<Produto> _filtrar(List<Produto> todos) {
    final lista =
        todos.where((p) {
          final ok = switch (_filtro) {
            'baixo' => p.ativo && p.estoque <= p.estoqueMinimo,
            'zerados' => p.ativo && p.estoque <= 0,
            'inativos' => !p.ativo,
            _ => p.ativo,
          };
          if (!ok) return false;
          if (_busca.isEmpty) return true;
          return normalizarBusca('${p.nome} ${p.codigo} ${p.categoria}')
              .contains(_busca);
        }).toList()..sort((a, b) {
          final c = a.estoque.compareTo(b.estoque);
          return c != 0
              ? c
              : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
        });
    return lista;
  }

  void _abrirForm([Produto? produto]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProdutoFormPage(produto: produto)),
    );
  }

  Future<void> _desativar(Produto p) async {
    final ok = await confirmar(
      context,
      titulo: 'Remover produto',
      mensagem: 'Remover este produto?',
      confirmarTexto: 'Remover',
    );
    if (!ok || !mounted) return;
    if (executar(
      context,
      () => _repo.definirAtivo(p, false),
      sucesso: 'Produto removido do catálogo.',
    )) {
      setState(() => _filtro = 'inativos');
    }
  }

  void _restaurar(Produto p) {
    executar(
      context,
      () => _repo.definirAtivo(p, true),
      sucesso: 'Produto restaurado.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= larguraDesktop;
    return Scaffold(
      floatingActionButton: desktop
          ? null
          : FloatingActionButton(
              onPressed: _abrirForm,
              tooltip: 'Novo produto',
              child: const Icon(Icons.add),
            ),
      body: ValueListenableBuilder<List<Produto>>(
        valueListenable: Dados.produtos,
        builder: (context, todos, _) {
          final lista = _filtrar(todos);
          return LarguraMaxima(
            largura: 1200,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _cabecalho(lista.length, desktop)),
                if (lista.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EstadoVazio(
                      icone: Icons.inventory_2_outlined,
                      titulo: 'Nenhum produto encontrado',
                    ),
                  )
                else if (desktop) ...[
                  SliverToBoxAdapter(child: _cabecalhoTabela(context)),
                  SliverList.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _linhaDesktop(lista[i]),
                  ),
                ] else
                  SliverList.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _linhaMobile(lista[i]),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cabecalho(int quantidade, bool desktop) {
    final t = Theme.of(context).textTheme;
    final sessao = Sessao.instancia;
    final botoes = <Widget>[
      if (sessao.pode(Permissao.transformacoes))
        OutlinedButton.icon(
          onPressed: () => AppShell.abrir(context, 'transformacoes'),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Montar / desmanchar'),
        ),
      if (sessao.pode(Permissao.entradas))
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotaEntradaFormPage()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Nota de entrada'),
        ),
      if (desktop)
        FilledButton.icon(
          onPressed: _abrirForm,
          icon: const Icon(Icons.add),
          label: const Text('Novo produto'),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_titulos[_filtro]!, style: t.titleLarge),
                  Text('$quantidade produtos exibidos', style: t.bodySmall),
                ],
              ),
              Wrap(spacing: 8, runSpacing: 8, children: botoes),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in _filtros.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _filtro == e.key,
                  onSelected: (_) => setState(() => _filtro = e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar no estoque...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) =>
                setState(() => _busca = normalizarBusca(v.trim())),
          ),
        ],
      ),
    );
  }

  Widget _cabecalhoTabela(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelMedium
        ?.copyWith(fontWeight: FontWeight.bold);
    Widget c(String texto, int flex, {TextAlign align = TextAlign.start}) =>
        Expanded(
          flex: flex,
          child: Text(texto, style: estilo, textAlign: align),
        );
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          c('Produto', 5),
          c('Categoria', 2),
          c('Venda / custo', 2, align: TextAlign.end),
          c('Estoque', 1, align: TextAlign.end),
          c('Mínimo', 1, align: TextAlign.end),
          const SizedBox(width: 16),
          c('Status', 2),
          const SizedBox(width: 120),
        ],
      ),
    );
  }

  Widget _acoes(Produto p) {
    if (!p.ativo) {
      return TextButton.icon(
        onPressed: () => _restaurar(p),
        icon: const Icon(Icons.restore),
        label: const Text('Restaurar'),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Editar',
          onPressed: () => _abrirForm(p),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Remover',
          onPressed: () => _desativar(p),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  String _codigoUnidade(Produto p) =>
      [if (p.codigo.isNotEmpty) p.codigo, p.unidade].join(' · ');

  Widget _linhaDesktop(Produto p) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: p.ativo ? () => _abrirForm(p) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  FotoProduto(nome: p.nome, tamanho: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                p.nome,
                                style: t.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            PendenteIcon(pendente: p.pendente),
                          ],
                        ),
                        Text(_codigoUnidade(p), style: t.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 2, child: Text(p.categoria)),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatarMoeda(p.preco)),
                  Text(formatarMoeda(p.custo), style: t.bodySmall),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                '${p.estoque}',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text('${p.estoqueMinimo} un.', textAlign: TextAlign.end),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SeloStatusProduto(p),
              ),
            ),
            SizedBox(
              width: 120,
              child: Align(alignment: Alignment.centerRight, child: _acoes(p)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaMobile(Produto p) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      onTap: p.ativo ? () => _abrirForm(p) : null,
      leading: FotoProduto(nome: p.nome),
      title: Row(
        children: [
          Flexible(child: Text(p.nome, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          PendenteIcon(pendente: p.pendente),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              _codigoUnidade(p),
              if (p.categoria.isNotEmpty) p.categoria,
            ].join(' · '),
          ),
          Text('${formatarMoeda(p.preco)} · custo ${formatarMoeda(p.custo)}'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SeloStatusProduto(p),
              Text(
                'Estoque ${p.estoque} · mín. ${p.estoqueMinimo} un.',
                style: t.bodySmall,
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: _acoesMobile(p),
    );
  }

  Widget _acoesMobile(Produto p) {
    if (!p.ativo) {
      return TextButton(
        onPressed: () => _restaurar(p),
        child: const Text('Restaurar'),
      );
    }
    return PopupMenuButton<String>(
      onSelected: (v) => v == 'editar' ? _abrirForm(p) : _desativar(p),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'editar', child: Text('Editar')),
        PopupMenuItem(value: 'remover', child: Text('Remover')),
      ],
    );
  }
}
