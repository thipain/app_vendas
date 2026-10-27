import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cliente.dart';
import 'offline.dart';
import 'banco.dart';

class ClienteRepository {
  CollectionReference<Map<String, dynamic>> get _col => Banco.col('clientes');

  Stream<List<Cliente>> watchTodos() => _col
      .orderBy('nomeBusca')
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Cliente.fromDoc).toList());

  void salvar(Cliente cliente) {
    final ref = cliente.id.isEmpty ? _col.doc() : _col.doc(cliente.id);
    semAguardar(
      ref.set({
        ...cliente.toMap(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'cliente ${cliente.nome}',
    );
  }

  void excluir(String id) {
    semAguardar(_col.doc(id).delete(), 'exclusão do cliente $id');
  }
}
