import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/venda.dart';
import 'offline.dart';

class VendaRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _vendas =>
      _db.collection('vendas');
  CollectionReference<Map<String, dynamic>> get _produtos =>
      _db.collection('produtos');

  Stream<List<Venda>> watchRecentes({int limite = 200}) => _vendas
      .orderBy('data', descending: true)
      .limit(limite)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Venda.fromDoc).toList());

  Stream<Venda?> watch(String id) => _vendas
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? Venda.fromDoc(d) : null);

  /// Registra a venda e dá baixa no estoque numa única gravação atômica.
  ///
  /// Usa WriteBatch + FieldValue.increment porque transactions não funcionam
  /// offline. O increment é aplicado no servidor, então vendas feitas offline
  /// por aparelhos diferentes somam corretamente ao sincronizar.
  String registrar(Venda venda) {
    final batch = _db.batch();
    final ref = _vendas.doc();
    batch.set(ref, {
      ...venda.toMap(),
      'criadoEm': FieldValue.serverTimestamp(),
    });
    for (final item in venda.itens) {
      batch.update(_produtos.doc(item.produtoId), {
        'estoque': FieldValue.increment(-item.quantidade),
      });
    }
    semAguardar(batch.commit(), 'venda ${ref.id}');
    return ref.id;
  }

  /// Cancela a venda e devolve os itens ao estoque.
  void cancelar(Venda venda) {
    final batch = _db.batch();
    batch.update(_vendas.doc(venda.id), {
      'status': Venda.cancelada,
      'canceladaEm': FieldValue.serverTimestamp(),
    });
    for (final item in venda.itens) {
      batch.update(_produtos.doc(item.produtoId), {
        'estoque': FieldValue.increment(item.quantidade),
      });
    }
    semAguardar(batch.commit(), 'cancelamento da venda ${venda.id}');
  }
}
