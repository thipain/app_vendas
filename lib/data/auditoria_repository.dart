import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sessao.dart';
import '../models/registro_auditoria.dart';
import 'offline.dart';

/// Registro de acessos e operações sensíveis. Nunca é alterado nem apagado.
class AuditoriaRepository {
  static final _col = FirebaseFirestore.instance.collection('auditoria');

  static Map<String, dynamic> _dados(
    String acao,
    String descricao, {
    String? entidade,
    String? entidadeId,
    Object? antes,
    Object? depois,
  }) =>
      {
        'acao': acao,
        'descricao': descricao,
        'entidade': entidade,
        'entidadeId': entidadeId,
        'antes': antes,
        'depois': depois,
        'usuario': Sessao.instancia.autor,
        'plataforma': Platform.operatingSystem,
        'data': Timestamp.now(),
      };

  /// Inclui o registro na mesma gravação atômica da operação.
  static void noBatch(
    WriteBatch batch,
    String acao,
    String descricao, {
    String? entidade,
    String? entidadeId,
    Object? antes,
    Object? depois,
  }) {
    batch.set(
      _col.doc(),
      _dados(acao, descricao,
          entidade: entidade,
          entidadeId: entidadeId,
          antes: antes,
          depois: depois),
    );
  }

  static void registrar(
    String acao,
    String descricao, {
    String? entidade,
    String? entidadeId,
    Object? antes,
    Object? depois,
  }) {
    semAguardar(
      _col.doc().set(_dados(acao, descricao,
          entidade: entidade,
          entidadeId: entidadeId,
          antes: antes,
          depois: depois)),
      'auditoria $acao',
    );
  }

  Stream<List<RegistroAuditoria>> watchPeriodo(DateTime inicio, DateTime fim) =>
      _col
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('data', isLessThan: Timestamp.fromDate(fim))
          .orderBy('data', descending: true)
          .limit(1000)
          .snapshots()
          .map((s) => s.docs.map(RegistroAuditoria.fromDoc).toList());
}
