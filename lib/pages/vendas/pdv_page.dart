import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dinheiro.dart';
import '../../core/formatters.dart';
import '../../core/permissoes.dart';
import '../../core/regra_exception.dart';
import '../../core/sessao.dart';
import '../../data/cliente_repository.dart';
import '../../data/comanda_repository.dart';
import '../../data/dados.dart';
import '../../data/venda_repository.dart';
import '../../models/caixa.dart';
import '../../models/cliente.dart';
import '../../models/comanda.dart';
import '../../models/produto.dart';
import '../../models/venda.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pagamento_form.dart';
import '../../widgets/pendente_icon.dart';
import '../../widgets/seletor.dart';
import '../shell/app_shell.dart';
import 'comprovante_page.dart';

/// Carrinho, cliente e comanda escolhida. Fica num ChangeNotifier para que o
/// painel do carrinho (que no celular abre em outra rota) se atualize junto.
class _PdvEstado extends ChangeNotifier {
  /// produtoId → quantidade, na ordem em que foram adicionados.
  final itens = <String, int>{};
  String? comandaId;
  Cliente? cliente;
  List<Comanda> comandas = const [];

  int get quantidadeTotal => itens.values.fold(0, (s, q) => s + q);

  void definir(String produtoId, int quantidade) {
    if (quantidade <= 0) {
      itens.remove(produtoId);
    } else {
      itens[produtoId] = quantidade;
    }
    notifyListeners();
  }

  void limpar() {
    itens.clear();
    notifyListeners();
  }

  void atualizar() => notifyListeners();
}

/// Nova venda (PDV). Com [comandaId], lança os itens nessa comanda.
class PdvPage extends StatefulWidget {
  final String? comandaId;
  const PdvPage({super.key, this.comandaId});

  @override
  State<PdvPage> createState() => _PdvPageState();
}

class _PdvPageState extends State<PdvPage> {
  final _estado = _PdvEstado();
  final _pag = PagamentoController();
  final _busca = TextEditingController();
  final _buscaFoco = FocusNode();
  String _filtro = '';
  String? _categoria;
  StreamSubscription<List<Comanda>>? _subComandas;
  bool _comandasCarregadas = false;

  bool get _podeComandas => Sessao.instancia.pode(Permissao.comandas);
  bool get _modoComanda => _estado.comandaId != null;

  Comanda? get _comandaSelecionada =>
      _estado.comandas.where((c) => c.id == _estado.comandaId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _estado.comandaId = widget.comandaId;
    if (widget.comandaId != null && !_podeComandas) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        mostrarErro(
          context,
          const RegraException('Você não possui permissão para comandas.'),
        );
        _sair();
      });
    }
    if (_podeComandas) {
      _subComandas = ComandaRepository().watchAbertas().listen((lista) {
        if (!mounted) return;
        _estado.comandas = lista;
        final existe = lista.any((c) => c.id == _estado.comandaId);
        if (!_comandasCarregadas) {
          _comandasCarregadas = true;
          if (widget.comandaId != null && !existe) {
            mostrarErro(
              context,
              const RegraException('A comanda informada não está aberta.'),
            );
            _sair();
            return;
          }
        }
        if (widget.comandaId == null && !existe) _estado.comandaId = null;
        _estado.atualizar();
      }, onError: (Object e) => debugPrint('Comandas: $e'));
    }
  }

  @override
  void dispose() {
    _subComandas?.cancel();
    _estado.dispose();
    _pag.dispose();
    _busca.dispose();
    _buscaFoco.dispose();
    super.dispose();
  }

  /// Sai do modo comanda: volta à tela anterior ou abre o módulo Comandas.
  void _sair() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      AppShell.abrir(context, 'comandas');
    }
  }

  // ------------------------------------------------------------- carrinho

  Map<String, Produto> get _porId => Dados.produtosPorId;

  void _adicionar(Produto p) {
    final atual = _estado.itens[p.id] ?? 0;
    if (p.estoque <= 0) {
      mostrarErro(context, const RegraException('Produto sem estoque.'));
      return;
    }
    if (atual + 1 > p.estoque) {
      mostrarErro(
        context,
        RegraException('Limite: apenas ${p.estoque} em estoque.'),
      );
      return;
    }
    _estado.definir(p.id, atual + 1);
  }

  List<ItemCarrinho> _itensCarrinho() {
    final porId = _porId;
    return [
      for (final e in _estado.itens.entries)
        if (porId[e.key] != null) ItemCarrinho(porId[e.key]!, e.value),
    ];
  }

  int _subtotalCentavos() {
    final porId = _porId;
    var s = 0;
    _estado.itens.forEach((id, q) {
      final p = porId[id];
      if (p != null) s += centavos(p.preco) * q;
    });
    return s;
  }

  int _totalCentavos() {
    final sub = _subtotalCentavos();
    return _modoComanda ? sub : _pag.totalCentavos(sub);
  }

  void _lerCodigo(String texto) {
    final codigo = texto.trim().toLowerCase();
    if (codigo.isEmpty) return;
    final achados = Dados.produtosAtivos
        .where((p) => p.codigo.toLowerCase() == codigo)
        .toList();
    if (achados.length == 1) {
      _adicionar(achados.first);
      _busca.clear();
      setState(() => _filtro = '');
    }
    _buscaFoco.requestFocus();
  }

  // ------------------------------------------------------------- finalizar

  /// [ctx] é o contexto do painel; [fecharPainel] quando o painel está numa
  /// rota própria (celular).
  void _finalizar(BuildContext ctx, {required bool fecharPainel}) {
    final itens = _itensCarrinho();
    if (itens.isEmpty) {
      mostrarErro(ctx, const RegraException('Adicione ao menos um produto.'));
      return;
    }
    if (_modoComanda) {
      final comanda = _comandaSelecionada;
      try {
        if (comanda == null) {
          throw const RegraException('A comanda não está mais aberta.');
        }
        VendaRepository().lancarNaComanda(comanda, itens);
      } catch (e) {
        mostrarErro(ctx, e);
        return;
      }
      _estado.limpar();
      if (fecharPainel) Navigator.pop(ctx);
      avisar(
        context,
        'Itens adicionados à ${comanda.nome}. A comanda continua aberta.',
      );
      _sair();
      return;
    }
    final Venda venda;
    try {
      final total = _pag.totalCentavos(_subtotalCentavos());
      final pagamentos = _pag.montar(total);
      venda = VendaRepository().registrar(
        carrinho: itens,
        caixa: Dados.caixaAberto.value,
        descontoPercentual: _pag.descontoPercentual,
        descontoInformado: _pag.descontoInformado,
        pagamentos: pagamentos,
        clienteId: _estado.cliente?.id,
        clienteNome: _estado.cliente?.nome,
      );
    } catch (e) {
      mostrarErro(ctx, e);
      return;
    }
    _estado.cliente = null;
    _estado.limpar();
    _pag.limpar();
    if (fecharPainel) Navigator.pop(ctx);
    _mostrarSucesso(venda);
  }

  Future<void> _mostrarSucesso(Venda v) async {
    void comprovante({bool editar = false, bool imprimir = false}) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ComprovantePage(
            vendaId: v.id,
            editar: editar,
            imprimir: imprimir,
            abrirModulo: (m) => AppShell.abrir(context, m),
          ),
        ),
      );
    }

    final pagamento = v.pagamentos.length == 1
        ? v.pagamentos.first.descricao
        : v.pagamentoResumo;
    final escolha = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final t = Theme.of(ctx);
        Widget linha(String a, String b, {TextStyle? estilo}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(a, style: estilo),
              Text(b, style: estilo),
            ],
          ),
        );
        return AlertDialog(
          icon: Icon(
            Icons.check_circle,
            color: Colors.green.shade600,
            size: 48,
          ),
          title: const Text('Venda concluída'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'O estoque foi atualizado com segurança.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                linha('Venda', '#${v.codigo}'),
                linha(
                  'Total',
                  formatarMoeda(v.total),
                  estilo: t.textTheme.titleMedium,
                ),
                linha('Pagamento', pagamento),
                if (v.troco > 0)
                  linha(
                    'Troco',
                    formatarMoeda(v.troco),
                    estilo: t.textTheme.titleMedium?.copyWith(
                      color: t.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          actionsOverflowDirection: VerticalDirection.up,
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.edit_note),
              label: const Text('Editar nota completa'),
              onPressed: () => Navigator.pop(ctx, 'editar'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir comprovante'),
              onPressed: () => Navigator.pop(ctx, 'imprimir'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Nova venda'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (escolha == 'editar') comprovante(editar: true);
    if (escolha == 'imprimir') comprovante(imprimir: true);
    if (escolha == null) _buscaFoco.requestFocus();
  }

  Future<void> _escolherCliente(BuildContext ctx) async {
    List<Cliente> lista;
    try {
      lista = await ClienteRepository().watchTodos().first.timeout(
        const Duration(seconds: 10),
      );
    } catch (e) {
      if (ctx.mounted) mostrarErro(ctx, e);
      return;
    }
    if (!ctx.mounted) return;
    final c = await selecionar<Cliente>(
      ctx,
      titulo: 'Buscar cliente',
      itens: lista,
      textoBusca: (c) => '${c.nome} ${c.documento} ${c.telefone}',
      itemBuilder: (c) => ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(c.nome),
        subtitle: Text(
          [c.documento, c.telefone].where((s) => s.isNotEmpty).join(' · '),
        ),
      ),
    );
    if (c != null) {
      _estado.cliente = c;
      _estado.atualizar();
    }
  }

  void _abrirCarrinhoCelular() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (rota) => Scaffold(
          appBar: AppBar(
            title: Text(_modoComanda ? 'Itens da comanda' : 'Carrinho'),
          ),
          body: _painel(rota, fecharPainel: true),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final desktop = box.maxWidth >= larguraDesktop;
          if (desktop) {
            return Row(
              children: [
                Expanded(child: _catalogo(desktop: true)),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: box.maxWidth >= 1100 ? 420 : 360,
                  child: Builder(
                    builder: (ctx) => _painel(ctx, fecharPainel: false),
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: _catalogo(desktop: false)),
              _barraCelular(),
            ],
          );
        },
      ),
    );
  }

  Widget _barraCelular() {
    return ListenableBuilder(
      listenable: Listenable.merge([_estado, _pag, Dados.produtos]),
      builder: (context, _) {
        final t = Theme.of(context);
        final n = _estado.quantidadeTotal;
        return Material(
          elevation: 8,
          color: t.colorScheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$n ${n == 1 ? 'item' : 'itens'}',
                          style: t.textTheme.bodySmall,
                        ),
                        Text(
                          formatarMoeda(deCentavos(_totalCentavos())),
                          style: t.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    icon: Badge(
                      isLabelVisible: n > 0,
                      label: Text('$n'),
                      child: const Icon(Icons.shopping_cart_outlined),
                    ),
                    label: Text(_modoComanda ? 'Ver comanda' : 'Ver carrinho'),
                    onPressed: _abrirCarrinhoCelular,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- catálogo

  Widget _catalogo({required bool desktop}) {
    final t = Theme.of(context);
    return ValueListenableBuilder<List<Produto>>(
      valueListenable: Dados.produtos,
      builder: (context, todos, _) {
        final ativos = todos.where((p) => p.ativo).toList();
        final categorias =
            ativos
                .map((p) => p.categoria.trim())
                .where((c) => c.isNotEmpty)
                .toSet()
                .toList()
              ..sort(
                (a, b) => normalizarBusca(a).compareTo(normalizarBusca(b)),
              );
        final categoria = categorias.contains(_categoria) ? _categoria : null;
        final lista = ativos.where((p) {
          if (categoria != null && p.categoria.trim() != categoria) {
            return false;
          }
          if (_filtro.isEmpty) return true;
          return normalizarBusca('${p.nome} ${p.codigo} ${p.categoria}')
              .contains(_filtro);
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _busca,
                      focusNode: _buscaFoco,
                      autofocus: desktop,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Buscar produto ou ler SKU...',
                        suffixIcon: _filtro.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpar busca',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _busca.clear();
                                  setState(() => _filtro = '');
                                },
                              ),
                      ),
                      onChanged: (v) =>
                          setState(() => _filtro = normalizarBusca(v.trim())),
                      onSubmitted: _lerCodigo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CaixaBadge(compacto: !desktop),
                ],
              ),
            ),
            if (categorias.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final c in [null, ...categorias])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(c ?? 'Todos'),
                          selected: c == categoria,
                          onSelected: (_) => setState(() => _categoria = c),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: lista.isEmpty
                  ? EstadoVazio(
                      icone: Icons.inventory_2_outlined,
                      titulo: ativos.isEmpty
                          ? 'Nenhum produto cadastrado'
                          : 'Nenhum produto encontrado',
                    )
                  : ListenableBuilder(
                      listenable: _estado,
                      builder: (context, _) => GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 190,
                              mainAxisExtent: 236,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: lista.length,
                        itemBuilder: (context, i) {
                          final p = lista[i];
                          return _ProdutoCard(
                            produto: p,
                            noCarrinho: _estado.itens[p.id] ?? 0,
                            onTap: () => _adicionar(p),
                          );
                        },
                      ),
                    ),
            ),
            if (!desktop && _modoComanda)
              Container(
                width: double.infinity,
                color: t.colorScheme.secondaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: ListenableBuilder(
                  listenable: _estado,
                  builder: (_, _) =>
                      Text(_textoComanda(), style: t.textTheme.labelMedium),
                ),
              ),
          ],
        );
      },
    );
  }

  String _textoComanda() {
    final c = _comandaSelecionada;
    if (c == null) return 'COMANDA ...';
    return 'COMANDA ${c.nome.toUpperCase()} · CONSUMO ATUAL '
        '${formatarMoeda(c.total)} · ${c.quantidadeItens} '
        '${c.quantidadeItens == 1 ? 'item' : 'itens'}';
  }

  // ------------------------------------------------------------- painel

  Widget _painel(BuildContext ctx, {required bool fecharPainel}) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _estado,
        _pag,
        Dados.produtos,
        Dados.caixaAberto,
      ]),
      builder: (ctx, _) {
        final t = Theme.of(ctx);
        final porId = _porId;
        final n = _estado.quantidadeTotal;
        final subtotal = _subtotalCentavos();
        final desconto = _modoComanda ? 0 : _pag.descontoCentavos(subtotal);
        final total = subtotal - desconto;
        final comanda = _comandaSelecionada;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Text(
                        _modoComanda ? 'Itens' : 'Carrinho',
                        style: t.textTheme.titleMedium,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$n ${n == 1 ? 'item' : 'itens'}',
                        style: t.textTheme.bodySmall,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Limpar'),
                        onPressed: n == 0 ? null : _estado.limpar,
                      ),
                    ],
                  ),
                  if (_podeComandas && widget.comandaId == null) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      key: ValueKey(
                        'comanda-${_estado.comandaId}-${_estado.comandas.length}',
                      ),
                      initialValue: comanda?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Comanda (opcional)',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Venda direta'),
                        ),
                        for (final c in _estado.comandas)
                          DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(
                              '${c.nome} · ${formatarMoeda(c.total)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        _estado.comandaId = id;
                        _estado.atualizar();
                      },
                    ),
                  ],
                  if (_modoComanda) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: t.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _textoComanda(),
                        style: t.textTheme.labelLarge?.copyWith(
                          color: t.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (n == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 40,
                            color: t.colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          const Text('Toque nos produtos para adicionar.'),
                        ],
                      ),
                    ),
                  for (final e in _estado.itens.entries)
                    if (porId[e.key] != null)
                      _LinhaCarrinho(
                        produto: porId[e.key]!,
                        quantidade: e.value,
                        onAlterar: (q) => _estado.definir(e.key, q),
                      ),
                  const Divider(height: 24),
                  if (_modoComanda)
                    Text(
                      'Pagamento no final. O estoque será reservado e o '
                      'consumo ficará nesta comanda.',
                      style: t.textTheme.bodySmall,
                    )
                  else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(
                        _estado.cliente?.nome ?? 'Cliente (opcional)',
                      ),
                      subtitle: Text(
                        _estado.cliente == null
                            ? 'Consumidor final'
                            : 'Toque para trocar',
                      ),
                      trailing: _estado.cliente == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'Remover cliente',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _estado.cliente = null;
                                _estado.atualizar();
                              },
                            ),
                      onTap: () => _escolherCliente(ctx),
                    ),
                    const SizedBox(height: 8),
                    PagamentoForm(controller: _pag, subtotalCentavos: subtotal),
                  ],
                ],
              ),
            ),
            Material(
              elevation: 4,
              color: t.colorScheme.surfaceContainerLow,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_modoComanda) ...[
                        _linhaTotal(
                          'Subtotal',
                          formatarMoeda(deCentavos(subtotal)),
                        ),
                        if (desconto > 0)
                          _linhaTotal(
                            'Desconto',
                            '- ${formatarMoeda(deCentavos(desconto))}',
                          ),
                      ],
                      _linhaTotal(
                        'Total',
                        formatarMoeda(deCentavos(total)),
                        estilo: t.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        icon: Icon(
                          _modoComanda
                              ? Icons.playlist_add
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          _modoComanda
                              ? 'Adicionar à comanda'
                              : 'Finalizar venda',
                        ),
                        onPressed: () =>
                            _finalizar(ctx, fecharPainel: fecharPainel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _linhaTotal(String a, String b, {TextStyle? estilo}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(a, style: estilo),
        Text(b, style: estilo),
      ],
    ),
  );
}

/// Situação do caixa ("Caixa #X aberto" / "Caixa fechado").
class _CaixaBadge extends StatelessWidget {
  final bool compacto;
  const _CaixaBadge({this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final podeCaixa = Sessao.instancia.pode(Permissao.caixa);
    return ValueListenableBuilder<Caixa?>(
      valueListenable: Dados.caixaAberto,
      builder: (context, caixa, _) {
        final aberto = caixa != null;
        final texto = aberto
            ? (compacto ? 'Aberto' : 'Caixa #${caixa.codigo} aberto')
            : (compacto ? 'Fechado' : 'Caixa fechado');
        final cor = aberto ? Colors.green.shade600 : t.colorScheme.error;
        return Tooltip(
          message: aberto ? 'Caixa #${caixa.codigo} aberto' : 'Caixa fechado',
          child: ActionChip(
            avatar: Icon(Icons.circle, size: 10, color: cor),
            label: Text(
              texto,
              style: TextStyle(color: aberto ? null : t.colorScheme.error),
            ),
            side: aberto ? null : BorderSide(color: t.colorScheme.error),
            onPressed: podeCaixa
                ? () => AppShell.abrir(context, 'caixa')
                : null,
          ),
        );
      },
    );
  }
}

class _ProdutoCard extends StatelessWidget {
  final Produto produto;
  final int noCarrinho;
  final VoidCallback onTap;

  const _ProdutoCard({
    required this.produto,
    required this.noCarrinho,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = produto;
    final t = Theme.of(context);
    final zerado = p.estoque <= 0;
    final baixo = p.estoque <= p.estoqueMinimo;
    final corEstoque = zerado
        ? t.colorScheme.error
        : baixo
        ? Colors.orange.shade800
        : t.colorScheme.onSurfaceVariant;
    return Opacity(
      opacity: zerado ? 0.5 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: noCarrinho > 0
                ? t.colorScheme.primary
                : t.colorScheme.outlineVariant,
            width: noCarrinho > 0 ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: zerado ? null : onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Container(
                    height: 104,
                    color: t.colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: FotoProduto(nome: p.nome, tamanho: 92, raio: 10),
                  ),
                  if (noCarrinho > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: t.colorScheme.primary,
                        child: Text(
                          '$noCarrinho',
                          style: TextStyle(
                            fontSize: 12,
                            color: t.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (p.pendente)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: PendenteIcon(pendente: true),
                    ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (p.codigo.isNotEmpty) p.codigo,
                          p.unidade,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.labelSmall?.copyWith(
                          color: t.colorScheme.outline,
                        ),
                      ),
                      Text(
                        p.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatarMoeda(p.preco),
                        style: t.textTheme.titleMedium,
                      ),
                      Text(
                        zerado ? 'Sem estoque' : '${p.estoque} disponíveis',
                        style: t.textTheme.labelSmall?.copyWith(
                          color: corEstoque,
                          fontWeight: baixo ? FontWeight.bold : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinhaCarrinho extends StatelessWidget {
  final Produto produto;
  final int quantidade;
  final ValueChanged<int> onAlterar;

  const _LinhaCarrinho({
    required this.produto,
    required this.quantidade,
    required this.onAlterar,
  });

  @override
  Widget build(BuildContext context) {
    final p = produto;
    final t = Theme.of(context);
    final excedeu = quantidade > p.estoque;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          FotoProduto(nome: p.nome, tamanho: 36),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  '${formatarMoeda(p.preco)} cada · máx. ${p.estoque}',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: excedeu ? t.colorScheme.error : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Diminuir',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => onAlterar(quantidade - 1),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$quantidade',
              textAlign: TextAlign.center,
              style: t.textTheme.titleSmall,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Aumentar',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: quantidade >= p.estoque
                ? null
                : () => onAlterar(quantidade + 1),
          ),
          SizedBox(
            width: 78,
            child: Text(
              formatarMoeda(deCentavos(centavos(p.preco) * quantidade)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
