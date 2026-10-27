import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sessao.dart';
import '../models/movimento_estoque.dart';
import '../models/produto.dart';

/// Toda alteração de saldo passa por aqui: incrementa o estoque do produto e
/// grava o movimento no histórico, dentro do mesmo WriteBatch da operação.
///
/// O saldo usa FieldValue.increment, que o servidor soma corretamente mesmo
/// quando vários aparelhos operam offline ao mesmo tempo.
class Estoque {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get produtos =>
      _db.collection('produtos');
  static CollectionReference<Map<String, dynamic>> get movimentos =>
      _db.collection('movimentosEstoque');

  static void movimentar(
    WriteBatch batch, {
    required Produto produto,
    required int quantidade,
    required String tipo,
    String? referenciaTipo,
    String? referenciaId,
    String motivo = '',
    DateTime? data,
    Map<String, dynamic> extra = const {},
  }) {
    if (quantidade == 0 && extra.isEmpty) return;
    batch.update(produtos.doc(produto.id), {
      if (quantidade != 0) 'estoque': FieldValue.increment(quantidade),
      ...extra,
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    if (quantidade == 0) return;
    batch.set(movimentos.doc(), {
      'produtoId': produto.id,
      'produtoNome': produto.nome,
      'tipo': tipo,
      'quantidade': quantidade,
      'estoqueAntes': produto.estoque,
      'estoqueDepois': produto.estoque + quantidade,
      'referenciaTipo': referenciaTipo,
      'referenciaId': referenciaId,
      'motivo': motivo,
      'usuario': Sessao.instancia.autor,
      'data': Timestamp.fromDate(data ?? DateTime.now()),
    });
  }

  /// Gera o mapa id → produto a partir de uma lista (para consultar saldo).
  static Map<String, Produto> porId(Iterable<Produto> lista) =>
      {for (final p in lista) p.id: p};

  static Stream<List<MovimentoEstoque>> watchPeriodo(
          DateTime inicio, DateTime fim) =>
      movimentos
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('data', isLessThan: Timestamp.fromDate(fim))
          .orderBy('data', descending: true)
          .limit(2000)
          .snapshots(includeMetadataChanges: true)
          .map((s) => s.docs.map(MovimentoEstoque.fromDoc).toList());
}
