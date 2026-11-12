import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/regra_exception.dart';
import '../models/cupom.dart';
import 'auditoria_repository.dart';
import 'banco.dart';
import 'loja_online_repository.dart';
import 'offline.dart';

/// Cupons de desconto: cadastro em `lojas/{loja}/cupons` (equipe) e uma cópia
/// em `lojasPublicas/{loja}/cupons`, que a página do cliente consulta pelo
/// código (sem poder listar os cupons).
class CupomRepository {
  final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get colecao =>
      Banco.col('cupons');
  CollectionReference<Map<String, dynamic>> get _publicos =>
      LojaOnlineRepository.publica.collection('cupons');

  Stream<List<Cupom>> watchTodos() => colecao.snapshots().map(
    (s) => s.docs.map(Cupom.fromDoc).toList()
      ..sort((a, b) {
        if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
        return a.codigo.compareTo(b.codigo);
      }),
  );

  /// Cadastra ou altera. [novo] impede sobrescrever um código existente.
  void salvar(Cupom c, {required bool novo, required List<Cupom> todos}) {
    final codigo = Cupom.normalizarCodigo(c.codigo);
    if (!Cupom.codigoValido(codigo)) {
      throw const RegraException(
        'O código deve ter de 3 a 20 letras e números, sem espaços '
        '(ex.: BEMVINDO10).',
      );
    }
    if (novo && todos.any((o) => o.codigo == codigo)) {
      throw const RegraException('Já existe um cupom com este código.');
    }
    if (c.isPercentual && (c.quantia <= 0 || c.quantia > 100)) {
      throw const RegraException('O percentual deve ser de 1 a 100.');
    }
    if (!c.isPercentual && (c.quantia <= 0 || c.quantia > 1000)) {
      throw const RegraException('Informe um valor de desconto válido.');
    }
    if (c.minimo < 0 || c.minimo > 10000) {
      throw const RegraException('Pedido mínimo do cupom inválido.');
    }
    if (c.descricao.trim().length > 120) {
      throw const RegraException('A descrição pode ter até 120 caracteres.');
    }
    final cupom = Cupom(
      codigo: codigo,
      tipo: c.tipo,
      quantia: c.quantia,
      minimo: c.minimo,
      validoAte: c.validoAte,
      ativo: c.ativo,
      descricao: c.descricao.trim(),
    );
    final batch = _db.batch();
    batch.set(colecao.doc(codigo), cupom.toMap(), SetOptions(merge: true));
    batch.set(_publicos.doc(codigo), cupom.toPublico());
    AuditoriaRepository.noBatch(
      batch,
      novo ? 'coupon.create' : 'coupon.update',
      novo ? 'Cupom criado' : 'Cupom alterado',
      entidade: 'cupom',
      entidadeId: codigo,
      depois: {
        'tipo': cupom.tipo,
        'valor': cupom.quantia,
        'minimo': cupom.minimo,
        'ativo': cupom.ativo,
      },
    );
    semAguardar(batch.commit(), 'cupom $codigo');
  }

  void excluir(Cupom c) {
    final batch = _db.batch();
    batch.delete(colecao.doc(c.codigo));
    batch.delete(_publicos.doc(c.codigo));
    AuditoriaRepository.noBatch(
      batch,
      'coupon.delete',
      'Cupom excluído',
      entidade: 'cupom',
      entidadeId: c.codigo,
    );
    semAguardar(batch.commit(), 'exclusão do cupom ${c.codigo}');
  }

  /// Soma um uso no cupom (dentro do batch que aceita o pedido).
  static void registrarUso(WriteBatch batch, String codigo) {
    batch.set(colecao.doc(codigo), {
      'usos': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }
}
