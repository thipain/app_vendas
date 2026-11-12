import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dinheiro.dart';
import '../../core/formatters.dart';
import '../../core/regra_exception.dart';
import '../../data/cliente_repository.dart';
import '../../data/config_repository.dart';
import '../../data/pedido_repository.dart';
import '../../data/venda_repository.dart';
import '../../models/cliente.dart';
import '../../models/pedido.dart';
import '../../models/produto.dart';
import '../../models/venda.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/seletor.dart';
import '../inicio/comum.dart';
import 'delivery_comum.dart';

/// Registra um pedido de delivery (com os itens) ou edita cliente, endereço,
/// taxa e pagamento de um pedido existente. Ao criar, devolve o id.
class PedidoFormPage extends StatefulWidget {
  final Pedido? pedido;
  const PedidoFormPage({super.key, this.pedido});

  @override
  State<PedidoFormPage> createState() => _PedidoFormPageState();
}

class _PedidoFormPageState extends State<PedidoFormPage> {
  final _config = ConfigRepository.atual.value;
  late final Pedido? _p = widget.pedido;
  bool get _editando => _p != null;

  late final _nome = TextEditingController(text: _p?.clienteNome);
  late final _telefone = TextEditingController(text: _p?.telefone);
  late final _endereco = TextEditingController(text: _p?.endereco);
  late final _bairro = TextEditingController(text: _p?.bairro);
  late final _referencia = TextEditingController(text: _p?.referencia);
  late final _observacao = TextEditingController(text: _p?.observacao);
  late final _taxa = TextEditingController(
    text: valorParaCampo(_p?.taxaEntrega ?? _config.taxaEntrega),
  );
  late final _trocoPara = TextEditingController(
    text: _p?.trocoPara == null ? '' : valorParaCampo(_p!.trocoPara!),
  );
  late String? _clienteId = _p?.clienteId;
  late String? _forma = _p?.formaPagamento;
  late bool _precisaTroco = _p?.trocoPara != null;

  /// Itens do pedido novo, por id do produto.
  final _itens = <String, ItemCarrinho>{};

  @override
  void initState() {
    super.initState();
    for (final c in [_taxa, _trocoPara]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nome,
      _telefone,
      _endereco,
      _bairro,
      _referencia,
      _observacao,
      _taxa,
      _trocoPara,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _formas {
    final f = [..._config.formasDelivery];
    if (f.isEmpty) f.addAll(FormaPagamento.todas);
    if (_forma != null && !f.contains(_forma)) f.add(_forma!);
    return f;
  }

  int get _subtotalCentavos => _editando
      ? _p!.subtotalCentavos
      : _itens.values.fold(
          0,
          (s, i) => s + centavos(i.produto.preco) * i.quantidade,
        );

  int get _taxaCentavos => centavos(lerValor(_taxa.text) ?? 0);
  int get _totalCentavos =>
      _subtotalCentavos - (_p?.descontoCentavos ?? 0) + _taxaCentavos;

  Future<void> _buscarCliente() async {
    List<Cliente> clientes;
    try {
      clientes = await ClienteRepository().watchTodos().first;
    } catch (e) {
      if (mounted) mostrarErro(context, e);
      return;
    }
    if (!mounted) return;
    final c = await selecionar<Cliente>(
      context,
      titulo: 'Buscar cliente (nome ou telefone)',
      itens: clientes,
      textoBusca: (c) =>
          '${c.nome} ${c.telefone} ${c.telefone.replaceAll(RegExp(r'\D'), '')}',
      itemBuilder: (c) => ListTile(
        leading: CircleAvatar(child: Text(iniciais(c.nome))),
        title: Text(c.nome),
        subtitle: Text(
          [c.telefone, c.endereco].where((s) => s.isNotEmpty).join(' · '),
        ),
      ),
    );
    if (c == null) return;
    setState(() {
      _clienteId = c.id;
      _nome.text = c.nome;
      if (c.telefone.isNotEmpty) _telefone.text = c.telefone;
      if (c.endereco.isNotEmpty) _endereco.text = c.endereco;
    });
  }

  Future<void> _adicionarProduto() async {
    final p = await selecionarProduto(
      context,
      titulo: 'Adicionar produto',
      exigirEstoque: true,
    );
    if (p == null) return;
    setState(() {
      final atual = _itens[p.id]?.quantidade ?? 0;
      if (atual < p.estoque) _itens[p.id] = ItemCarrinho(p, atual + 1);
    });
  }

  void _alterar(Produto p, int qtd) {
    setState(() {
      if (qtd <= 0) {
        _itens.remove(p.id);
      } else {
        _itens[p.id] = ItemCarrinho(p, qtd > p.estoque ? p.estoque : qtd);
      }
    });
  }

  void _salvar() {
    try {
      final forma = _forma;
      if (forma == null) {
        throw const RegraException('Escolha a forma de pagamento.');
      }
      final taxa = lerValor(_taxa.text) ?? 0;
      double? troco;
      if (forma == FormaPagamento.dinheiro && _precisaTroco) {
        troco = lerValor(_trocoPara.text);
        if (troco == null) {
          throw const RegraException(
            'Informe para quanto o cliente precisa de troco.',
          );
        }
      }
      final dados = DadosPedido(
        clienteId: _clienteId,
        clienteNome: _nome.text,
        telefone: _telefone.text,
        endereco: _endereco.text,
        bairro: _bairro.text,
        referencia: _referencia.text,
        observacao: _observacao.text,
        taxaEntrega: taxa,
        formaPagamento: forma,
        trocoPara: troco,
      );
      final repo = PedidoRepository();
      if (_editando) {
        repo.editarDados(_p!, dados);
        Navigator.pop(context);
      } else {
        final id = repo.criar(dados, _itens.values.toList());
        Navigator.pop(context, id);
      }
    } catch (e) {
      mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editando ? 'Editar pedido #${_p!.codigo}' : 'Novo pedido delivery',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LarguraMaxima(
            largura: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TituloSecao('Cliente'),
                _cartao([
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_search_outlined),
                      label: const Text('Buscar cliente cadastrado'),
                      onPressed: _buscarCliente,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _campo(_nome, 'Nome do cliente *', 100),
                  _campo(
                    _telefone,
                    'Telefone / WhatsApp *',
                    30,
                    teclado: TextInputType.phone,
                  ),
                ]),
                const TituloSecao('Endereço de entrega'),
                _cartao([
                  _campo(_endereco, 'Rua e número *', 200),
                  _campo(_bairro, 'Bairro', 80),
                  _campo(_referencia, 'Complemento / ponto de referência', 200),
                ]),
                if (!_editando) ...[
                  const TituloSecao('Itens'),
                  _cartao([
                    if (_itens.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Nenhum produto adicionado.'),
                      ),
                    for (final i in _itens.values)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(i.produto.nome),
                        subtitle: Text(
                          '${formatarMoeda(i.produto.preco)} un. · '
                          'saldo ${i.produto.estoque}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () =>
                                  _alterar(i.produto, i.quantidade - 1),
                            ),
                            Text(
                              '${i.quantidade}',
                              style: t.textTheme.titleMedium,
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: i.quantidade >= i.produto.estoque
                                  ? null
                                  : () => _alterar(i.produto, i.quantidade + 1),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar produto'),
                        onPressed: _adicionarProduto,
                      ),
                    ),
                  ]),
                ],
                const TituloSecao('Pagamento'),
                _cartao([
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in _formas)
                        ChoiceChip(
                          avatar: Icon(iconeForma(f), size: 18),
                          label: Text(f),
                          selected: _forma == f,
                          onSelected: (_) => setState(() => _forma = f),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._detalhePagamento(t),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _taxa,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Taxa de entrega (R\$)',
                      helperText: 'Valor padrão definido em Configurações.',
                    ),
                  ),
                ]),
                const TituloSecao('Observação'),
                _cartao([
                  _campo(
                    _observacao,
                    'Observação para a loja e o entregador',
                    300,
                    linhas: 2,
                  ),
                ]),
                const SizedBox(height: 16),
                _resumo(t),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(
                    _editando ? 'Salvar alterações' : 'Registrar pedido',
                  ),
                  onPressed: _salvar,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _detalhePagamento(ThemeData t) {
    switch (_forma) {
      case FormaPagamento.dinheiro:
        final troco = lerValor(_trocoPara.text);
        final levar = troco == null ? 0 : centavos(troco) - _totalCentavos;
        return [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cliente precisa de troco?'),
            value: _precisaTroco,
            onChanged: (v) => setState(() => _precisaTroco = v),
          ),
          if (_precisaTroco)
            TextField(
              controller: _trocoPara,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Troco para quanto? (R\$)',
                helperText: levar > 0
                    ? 'O entregador leva ${formatarMoeda(deCentavos(levar))} de troco.'
                    : 'Valor da nota que o cliente vai usar.',
              ),
            ),
        ];
      case FormaPagamento.pix:
        return [
          if (_config.chavePix.isEmpty)
            Text(
              'Cadastre a chave Pix da loja em Configurações para enviar ao '
              'cliente.',
              style: t.textTheme.bodySmall,
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.pix),
              title: Text(_config.chavePix),
              subtitle: const Text('Chave Pix da loja'),
              trailing: IconButton(
                tooltip: 'Copiar chave',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _config.chavePix),
                  );
                  if (mounted) avisar(context, 'Chave Pix copiada.');
                },
              ),
            ),
          Text(
            'Depois de registrar, anexe o comprovante que o cliente enviar e '
            'confirme o recebimento na tela do pedido.',
            style: t.textTheme.bodySmall,
          ),
        ];
      case FormaPagamento.debito || FormaPagamento.credito || FormaPagamento.vr:
        return [
          Row(
            children: [
              const Icon(Icons.point_of_sale),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O entregador precisa levar a maquininha ($_forma).',
                  style: t.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _resumo(ThemeData t) {
    Widget linha(String a, int c, {bool destaque = false}) => Row(
      children: [
        Expanded(
          child: Text(a, style: destaque ? t.textTheme.titleMedium : null),
        ),
        Text(
          formatarMoeda(deCentavos(c)),
          style: destaque ? t.textTheme.titleMedium : null,
        ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      color: t.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            linha('Produtos', _subtotalCentavos),
            if ((_p?.descontoCentavos ?? 0) > 0)
              linha('Cupom ${_p!.cupom ?? ''}', -_p.descontoCentavos),
            linha('Taxa de entrega', _taxaCentavos),
            const Divider(),
            linha('Total', _totalCentavos, destaque: true),
          ],
        ),
      ),
    );
  }

  Widget _cartao(List<Widget> filhos) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: filhos,
      ),
    ),
  );

  Widget _campo(
    TextEditingController c,
    String rotulo,
    int maximo, {
    int linhas = 1,
    TextInputType? teclado,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: TextField(
      controller: c,
      maxLength: maximo,
      minLines: linhas,
      maxLines: linhas == 1 ? 1 : linhas + 3,
      keyboardType: linhas > 1 ? TextInputType.multiline : teclado,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: rotulo),
    ),
  );
}
