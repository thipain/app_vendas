import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/cliente_repository.dart';
import '../../data/produto_repository.dart';
import '../../data/venda_repository.dart';
import '../../models/cliente.dart';
import '../../models/produto.dart';
import '../../models/venda.dart';

class NovaVendaPage extends StatefulWidget {
  const NovaVendaPage({super.key});

  @override
  State<NovaVendaPage> createState() => _NovaVendaPageState();
}

class _NovaVendaPageState extends State<NovaVendaPage> {
  final _itens = <ItemVenda>[];
  final _estoques = <String, int>{};
  final _desconto = TextEditingController();
  Cliente? _cliente;
  String _formaPagamento = formasPagamento.first;

  double get _subtotal => _itens.fold(0, (s, i) => s + i.subtotal);
  double get _valorDesconto => lerValor(_desconto.text) ?? 0;
  double get _total => _subtotal - _valorDesconto;

  @override
  void dispose() {
    _desconto.dispose();
    super.dispose();
  }

  Future<void> _escolherCliente() async {
    final cliente = await showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Seletor<Cliente>(
        titulo: 'Selecionar cliente',
        stream: ClienteRepository().watchTodos(),
        textoBusca: (c) => '${c.nome} ${c.telefone} ${c.documento}',
        itemBuilder: (c) => ListTile(
          title: Text(c.nome),
          subtitle: c.telefone.isEmpty ? null : Text(c.telefone),
        ),
      ),
    );
    if (cliente != null) setState(() => _cliente = cliente);
  }

  Future<void> _adicionarProduto() async {
    final produto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Seletor<Produto>(
        titulo: 'Adicionar produto',
        stream: ProdutoRepository().watchAtivos(),
        textoBusca: (p) => '${p.nome} ${p.codigo}',
        itemBuilder: (p) => ListTile(
          title: Text(p.nome),
          subtitle: Text('Estoque: ${p.estoque}'),
          trailing: Text(formatarMoeda(p.preco)),
        ),
      ),
    );
    if (produto == null) return;
    setState(() {
      _estoques[produto.id] = produto.estoque;
      final i = _itens.indexWhere((it) => it.produtoId == produto.id);
      if (i >= 0) {
        _itens[i] = _itens[i].copyWith(quantidade: _itens[i].quantidade + 1);
      } else {
        _itens.add(ItemVenda(
          produtoId: produto.id,
          nome: produto.nome,
          quantidade: 1,
          precoUnitario: produto.preco,
        ));
      }
    });
  }

  void _alterarQuantidade(int index, int delta) {
    setState(() {
      final nova = _itens[index].quantidade + delta;
      if (nova <= 0) {
        _itens.removeAt(index);
      } else {
        _itens[index] = _itens[index].copyWith(quantidade: nova);
      }
    });
  }

  void _finalizar() {
    if (_itens.isEmpty) return;
    if (_valorDesconto < 0 || _valorDesconto > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Desconto inválido')),
      );
      return;
    }
    VendaRepository().registrar(Venda(
      clienteId: _cliente?.id,
      clienteNome: _cliente?.nome,
      itens: List.of(_itens),
      desconto: _valorDesconto,
      formaPagamento: _formaPagamento,
      vendedorEmail: FirebaseAuth.instance.currentUser?.email ?? '',
      data: DateTime.now(),
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Venda de ${formatarMoeda(_total)} registrada')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nova venda')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(_cliente?.nome ?? 'Consumidor final'),
              subtitle: const Text('Toque para escolher o cliente'),
              trailing: _cliente == null
                  ? null
                  : IconButton(
                      tooltip: 'Remover cliente',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _cliente = null),
                    ),
              onTap: _escolherCliente,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('Itens', style: texto.titleMedium)),
              TextButton.icon(
                onPressed: _adicionarProduto,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar produto'),
              ),
            ],
          ),
          if (_itens.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Nenhum item adicionado')),
            ),
          for (var i = 0; i < _itens.length; i++) _itemTile(i),
          const Divider(height: 32),
          Text('Forma de pagamento', style: texto.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in formasPagamento)
                ChoiceChip(
                  label: Text(f),
                  selected: _formaPagamento == f,
                  onSelected: (_) => setState(() => _formaPagamento = f),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _desconto,
            decoration: const InputDecoration(
              labelText: 'Desconto',
              prefixText: r'R$ ',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: texto.headlineSmall),
              Text(formatarMoeda(_total), style: texto.headlineSmall),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _itens.isEmpty ? null : _finalizar,
            icon: const Icon(Icons.check),
            label: const Text('Finalizar venda'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }

  Widget _itemTile(int i) {
    final item = _itens[i];
    final estoque = _estoques[item.produtoId];
    final semEstoque = estoque != null && item.quantidade > estoque;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(item.nome),
      subtitle: Text(
        '${formatarMoeda(item.precoUnitario)} · '
        'Subtotal ${formatarMoeda(item.subtotal)}'
        '${semEstoque ? '\nEstoque disponível: $estoque' : ''}',
        style: semEstoque ? const TextStyle(color: Colors.orange) : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => _alterarQuantidade(i, -1),
          ),
          Text('${item.quantidade}'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _alterarQuantidade(i, 1),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet genérico com busca para escolher um item de uma lista.
class _Seletor<T> extends StatefulWidget {
  final String titulo;
  final Stream<List<T>> stream;
  final String Function(T) textoBusca;
  final Widget Function(T) itemBuilder;

  const _Seletor({
    required this.titulo,
    required this.stream,
    required this.textoBusca,
    required this.itemBuilder,
  });

  @override
  State<_Seletor<T>> createState() => _SeletorState<T>();
}

class _SeletorState<T> extends State<_Seletor<T>> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.titulo,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _busca = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<T>>(
              stream: widget.stream,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final itens = snap.data!
                    .where((e) =>
                        widget.textoBusca(e).toLowerCase().contains(_busca))
                    .toList();
                if (itens.isEmpty) {
                  return const Center(child: Text('Nada encontrado'));
                }
                return ListView.builder(
                  controller: scroll,
                  itemCount: itens.length,
                  itemBuilder: (context, i) => InkWell(
                    onTap: () => Navigator.pop(context, itens[i]),
                    child: widget.itemBuilder(itens[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
