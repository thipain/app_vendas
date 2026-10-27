import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/caixa.dart';
import 'auditoria_repository.dart';
import 'offline.dart';
import 'banco.dart';

/// Abertura e fechamento de caixa, suprimentos e sangrias. Somente dinheiro
/// movimenta o caixa; Pix, cartões e VR não passam pela gaveta.
class CaixaRepository {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get caixas =>
      Banco.col('caixas');
  static CollectionReference<Map<String, dynamic>> get movimentos =>
      Banco.col('movimentosCaixa');

  /// Caixa aberto no momento (ou null).
  Stream<Caixa?> watchAberto() => caixas
      .where('status', isEqualTo: Caixa.aberto)
      .snapshots(includeMetadataChanges: true)
      .map((s) {
        final lista = s.docs.map(Caixa.fromDoc).toList()
          ..sort((a, b) => b.abertoEm.compareTo(a.abertoEm));
        return lista.isEmpty ? null : lista.first;
      });

  Stream<List<Caixa>> watchUltimos({int limite = 30}) => caixas
      .orderBy('abertoEm', descending: true)
      .limit(limite)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Caixa.fromDoc).toList());

  Stream<List<MovimentoCaixa>> watchMovimentos(String caixaId) => movimentos
      .where('caixaId', isEqualTo: caixaId)
      .snapshots(includeMetadataChanges: true)
      .map(
        (s) =>
            s.docs.map(MovimentoCaixa.fromDoc).toList()
              ..sort((a, b) => b.data.compareTo(a.data)),
      );

  /// Inclui um movimento do caixa no batch de outra operação (venda, estorno).
  static void movimentoNoBatch(
    WriteBatch batch, {
    required String caixaId,
    required String tipo,
    required double valor,
    required String descricao,
    String? vendaId,
  }) {
    batch.set(movimentos.doc(), {
      'caixaId': caixaId,
      'tipo': tipo,
      'valor': valor,
      'descricao': descricao,
      'vendaId': vendaId,
      'usuario': Sessao.instancia.autor,
      'data': Timestamp.now(),
    });
  }

  String abrir({Caixa? atual, required double valor, String observacao = ''}) {
    if (atual != null) throw const RegraException('Já existe um caixa aberto.');
    if (valor < 0) throw const RegraException('Informe um valor válido.');
    final ref = caixas.doc();
    final batch = _db.batch();
    batch.set(ref, {
      'status': Caixa.aberto,
      'valorAbertura': valor,
      'observacao': observacao.trim(),
      'abertoPor': Sessao.instancia.autor,
      'abertoEm': Timestamp.now(),
    });
    movimentoNoBatch(
      batch,
      caixaId: ref.id,
      tipo: MovimentoCaixa.abertura,
      valor: valor,
      descricao: 'Abertura de caixa',
    );
    AuditoriaRepository.noBatch(
      batch,
      'cash.open',
      'Caixa aberto',
      entidade: 'caixa',
      entidadeId: ref.id,
      depois: {'valorAbertura': valor},
    );
    semAguardar(batch.commit(), 'abertura de caixa');
    return ref.id;
  }

  /// Suprimento (entrada de dinheiro) ou sangria (retirada da gaveta).
  void movimentar({
    required Caixa? caixa,
    required bool sangria,
    required double valor,
    required String motivo,
    required double saldoAtual,
  }) {
    if (caixa == null) throw const RegraException('Não há caixa aberto.');
    if (valor <= 0) throw const RegraException('Informe um valor válido.');
    if (motivo.trim().isEmpty) {
      throw const RegraException('Informe o motivo da movimentação.');
    }
    if (sangria && (valor * 100).round() > (saldoAtual * 100).round()) {
      throw const RegraException(
        'A sangria é maior que o saldo disponível no caixa.',
      );
    }
    final batch = _db.batch();
    movimentoNoBatch(
      batch,
      caixaId: caixa.id,
      tipo: sangria ? MovimentoCaixa.sangria : MovimentoCaixa.suprimento,
      valor: valor,
      descricao: motivo.trim(),
    );
    AuditoriaRepository.noBatch(
      batch,
      sangria ? 'cash.withdrawal' : 'cash.supply',
      sangria ? 'Sangria registrada' : 'Suprimento registrado',
      entidade: 'caixa',
      entidadeId: caixa.id,
      depois: {'valor': valor, 'descricao': motivo.trim()},
    );
    semAguardar(batch.commit(), 'movimento de caixa');
  }

  /// Fecha o caixa e retorna a diferença entre o contado e o esperado.
  double fechar(
    Caixa caixa, {
    required double contado,
    required double esperado,
  }) {
    if (contado < 0) throw const RegraException('Informe um valor válido.');
    final diferenca = ((contado - esperado) * 100).round() / 100;
    final batch = _db.batch();
    batch.update(caixas.doc(caixa.id), {
      'status': Caixa.fechado,
      'valorFechamento': contado,
      'valorEsperado': esperado,
      'diferenca': diferenca,
      'fechadoPor': Sessao.instancia.autor,
      'fechadoEm': Timestamp.now(),
    });
    movimentoNoBatch(
      batch,
      caixaId: caixa.id,
      tipo: MovimentoCaixa.fechamento,
      valor: contado,
      descricao: 'Fechamento de caixa',
    );
    AuditoriaRepository.noBatch(
      batch,
      'cash.close',
      'Caixa fechado',
      entidade: 'caixa',
      entidadeId: caixa.id,
      depois: {
        'contado': contado,
        'esperado': esperado,
        'diferenca': diferenca,
      },
    );
    semAguardar(batch.commit(), 'fechamento de caixa');
    return diferenca;
  }
}
