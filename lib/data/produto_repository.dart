import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/produto.dart';
import 'offline.dart';

class ProdutoRepository {
  final _col = FirebaseFirestore.instance.collection('produtos');

  /// Produtos ativos em ordem alfabética. Funciona offline a partir do cache.
  Stream<List<Produto>> watchAtivos() => _col
      .orderBy('nomeBusca')
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Produto.fromDoc).where((p) => p.ativo).toList());

  void salvar(Produto produto) {
    final ref = produto.id.isEmpty ? _col.doc() : _col.doc(produto.id);
    semAguardar(
      ref.set({
        ...produto.toMap(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'produto ${produto.nome}',
    );
  }

  /// Exclusão lógica: vendas antigas continuam apontando para o produto, e a
  /// baixa de estoque de uma venda feita offline não falha ao sincronizar.
  void excluir(String id) {
    semAguardar(
      _col.doc(id).update({
        'ativo': false,
        'atualizadoEm': FieldValue.serverTimestamp(),
      }),
      'exclusão do produto $id',
    );
  }
}
