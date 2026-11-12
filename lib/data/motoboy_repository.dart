import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';
import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/caixa.dart';
import '../models/motoboy.dart';
import '../models/pedido.dart';
import 'auditoria_repository.dart';
import 'banco.dart';
import 'caixa_repository.dart';
import 'offline.dart';
import 'pedido_repository.dart';

class MotoboyRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => Banco.col('motoboys');
  CollectionReference<Map<String, dynamic>> get _fechamentos =>
      Banco.col('fechamentosMotoboys');

  Stream<List<Motoboy>> watchTodos() => _col.snapshots().map(
    (s) => s.docs.map(Motoboy.fromDoc).toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase())),
  );

  /// Cadastra ou altera um motoboy (id vazio = novo).
  void salvar(Motoboy m, List<Motoboy> todos) {
    final nome = m.nome.trim();
    if (nome.isEmpty || nome.length > 60) {
      throw const RegraException('Informe o nome do motoboy (até 60 letras).');
    }
    if (m.telefone.trim().length > 30) {
      throw const RegraException('Telefone inválido.');
    }
    final repetido = todos.any(
      (o) => o.id != m.id && o.nome.trim().toLowerCase() == nome.toLowerCase(),
    );
    if (repetido) {
      throw const RegraException('Já existe um motoboy com este nome.');
    }
    if (m.usuarioId != null &&
        todos.any((o) => o.id != m.id && o.usuarioId == m.usuarioId)) {
      throw const RegraException('Este login já está ligado a outro motoboy.');
    }
    final novo = Motoboy(
      id: m.id,
      nome: nome,
      telefone: m.telefone.trim(),
      ativo: m.ativo,
      usuarioId: m.usuarioId,
    );
    final ref = m.id.isEmpty ? _col.doc() : _col.doc(m.id);
    final batch = _db.batch();
    batch.set(ref, novo.toMap());
    AuditoriaRepository.noBatch(
      batch,
      m.id.isEmpty ? 'courier.create' : 'courier.update',
      m.id.isEmpty ? 'Motoboy cadastrado' : 'Motoboy alterado',
      entidade: 'motoboy',
      entidadeId: ref.id,
      depois: novo.toMap(),
    );
    semAguardar(batch.commit(), 'motoboy $nome');
  }

  /// Último fechamento do dia (null = nenhum ainda).
  Stream<FechamentoMotoboys?> watchUltimoFechamento() => _fechamentos
      .orderBy('fim', descending: true)
      .limit(1)
      .snapshots(includeMetadataChanges: true)
      .map(
        (s) => s.docs.isEmpty ? null : FechamentoMotoboys.fromDoc(s.docs.first),
      );

  Stream<List<FechamentoMotoboys>> watchFechamentos({int limite = 30}) =>
      _fechamentos
          .orderBy('fim', descending: true)
          .limit(limite)
          .snapshots(includeMetadataChanges: true)
          .map((s) => s.docs.map(FechamentoMotoboys.fromDoc).toList());

  /// Pedidos entregues a partir de [inicio] (entregues ou já concluídos).
  Stream<List<Pedido>> watchEntregasDesde(DateTime inicio) => PedidoRepository
      .colecao
      .where('entregueEm', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
      .snapshots(includeMetadataChanges: true)
      .map(
        (s) => s.docs
            .map(Pedido.fromDoc)
            .where(
              (p) =>
                  p.status == Pedido.entregue || p.status == Pedido.concluido,
            )
            .toList(),
      );

  /// Fecha o dia: guarda quanto cada motoboy fez e recebeu, e zera a
  /// contagem (o próximo dia conta a partir de agora). Com [caixa], o
  /// pagamento sai da gaveta como sangria.
  void fecharDia({
    required DateTime inicio,
    required List<LinhaFechamento> linhas,
    Caixa? caixa,
  }) {
    final total = linhas.fold<int>(0, (s, l) => s + centavos(l.total));
    final batch = _db.batch();
    final ref = _fechamentos.doc();
    batch.set(ref, {
      'inicio': Timestamp.fromDate(inicio),
      'fim': Timestamp.now(),
      'linhas': linhas.map((l) => l.toMap()).toList(),
      'total': deCentavos(total),
      'pagoPeloCaixa': caixa != null && total > 0,
      'por': Sessao.instancia.autor,
    });
    if (caixa != null && total > 0) {
      CaixaRepository.movimentoNoBatch(
        batch,
        caixaId: caixa.id,
        tipo: MovimentoCaixa.sangria,
        valor: deCentavos(total),
        descricao: 'Pagamento dos motoboys (diárias e entregas)',
      );
    }
    AuditoriaRepository.noBatch(
      batch,
      'courier.day_close',
      'Dia dos motoboys fechado',
      entidade: 'fechamentoMotoboys',
      entidadeId: ref.id,
      depois: {
        'total': deCentavos(total),
        'linhas': linhas.map((l) => l.toMap()).toList(),
        'pagoPeloCaixa': caixa != null && total > 0,
      },
    );
    semAguardar(batch.commit(), 'fechamento do dia dos motoboys');
  }
}
