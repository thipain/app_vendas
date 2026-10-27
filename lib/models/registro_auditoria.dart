import 'package:cloud_firestore/cloud_firestore.dart';

class RegistroAuditoria {
  final String id;
  final String acao;
  final String descricao;
  final String? entidade;
  final String? entidadeId;
  final Object? antes;
  final Object? depois;
  final String usuarioNome;
  final String plataforma;
  final DateTime data;

  const RegistroAuditoria({
    required this.id,
    required this.acao,
    required this.descricao,
    this.entidade,
    this.entidadeId,
    this.antes,
    this.depois,
    required this.usuarioNome,
    required this.plataforma,
    required this.data,
  });

  factory RegistroAuditoria.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return RegistroAuditoria(
      id: doc.id,
      acao: d['acao'] as String? ?? '',
      descricao: d['descricao'] as String? ?? '',
      entidade: d['entidade'] as String?,
      entidadeId: d['entidadeId'] as String?,
      antes: d['antes'],
      depois: d['depois'],
      usuarioNome: (d['usuario'] as Map?)?['nome'] as String? ?? '',
      plataforma: d['plataforma'] as String? ?? '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
