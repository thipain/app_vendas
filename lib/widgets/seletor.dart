import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../data/dados.dart';
import '../models/produto.dart';
import 'foto_produto.dart';

/// Remove acentos e deixa em minúsculas, para buscas como no sistema original.
String normalizarBusca(String texto) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final t = texto.toLowerCase();
  final sb = StringBuffer();
  for (final r in t.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    sb.write(i >= 0 ? para[i] : c);
  }
  return sb.toString();
}

/// Lista com busca em bottom sheet; retorna o item tocado.
Future<T?> selecionar<T>(
  BuildContext context, {
  required String titulo,
  required List<T> itens,
  required String Function(T) textoBusca,
  required Widget Function(T) itemBuilder,
  bool Function(T)? habilitado,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _Seletor<T>(
      titulo: titulo,
      itens: itens,
      textoBusca: textoBusca,
      itemBuilder: itemBuilder,
      habilitado: habilitado,
    ),
  );
}

/// Seletor de produto (ativos por padrão), mostrando foto, saldo e preço.
Future<Produto?> selecionarProduto(
  BuildContext context, {
  String titulo = 'Buscar produto',
  bool incluirInativos = false,
  bool exigirEstoque = false,
}) {
  final lista =
      incluirInativos ? Dados.produtos.value : Dados.produtosAtivos;
  return selecionar<Produto>(
    context,
    titulo: titulo,
    itens: lista,
    textoBusca: (p) => '${p.nome} ${p.codigo} ${p.categoria}',
    habilitado: exigirEstoque ? (p) => p.estoque > 0 : null,
    itemBuilder: (p) => ListTile(
      leading: FotoProduto(foto: p.foto, nome: p.nome, tamanho: 40),
      title: Text(p.ativo ? p.nome : '${p.nome} — desativado'),
      subtitle: Text(
          '${p.codigo.isEmpty ? '' : '${p.codigo} · '}saldo ${p.estoque} ${p.unidade}'),
      trailing: Text(formatarMoeda(p.preco)),
    ),
  );
}

class _Seletor<T> extends StatefulWidget {
  final String titulo;
  final List<T> itens;
  final String Function(T) textoBusca;
  final Widget Function(T) itemBuilder;
  final bool Function(T)? habilitado;

  const _Seletor({
    required this.titulo,
    required this.itens,
    required this.textoBusca,
    required this.itemBuilder,
    this.habilitado,
  });

  @override
  State<_Seletor<T>> createState() => _SeletorState<T>();
}

class _SeletorState<T> extends State<_Seletor<T>> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final itens = widget.itens
        .where((e) => normalizarBusca(widget.textoBusca(e)).contains(_busca))
        .toList();
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
              ),
              onChanged: (v) => setState(() => _busca = normalizarBusca(v)),
            ),
          ),
          Expanded(
            child: itens.isEmpty
                ? const Center(child: Text('Nada encontrado'))
                : ListView.builder(
                    controller: scroll,
                    itemCount: itens.length,
                    itemBuilder: (context, i) {
                      final ok = widget.habilitado?.call(itens[i]) ?? true;
                      return Opacity(
                        opacity: ok ? 1 : 0.45,
                        child: InkWell(
                          onTap:
                              ok ? () => Navigator.pop(context, itens[i]) : null,
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
