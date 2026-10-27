import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';
import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/movimento_estoque.dart';
import '../models/produto.dart';
import '../models/retirada.dart';
import '../models/usuario.dart';
import 'auditoria_repository.dart';
import 'estoque.dart';
import 'offline.dart';
import 'venda_repository.dart';

class RetiradaRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('retiradas');

  Stream<List<Retirada>> watchPeriodo(DateTime inicio, DateTime fim) => _col
      .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
      .where('data', isLessThan: Timestamp.fromDate(fim))
      .orderBy('data', descending: true)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Retirada.fromDoc).toList());

  String registrar(Usuario funcionario, List<ItemCarrinho> itens,
      String observacao) {
    if (itens.isEmpty) {
      throw const RegraException('Adicione ao menos um produto à retirada.');
    }
    if (!funcionario.ativo) {
      throw const RegraException('Funcionário não encontrado ou bloqueado.');
    }
    final vistos = <String>{};
    for (final i in itens) {
      if (!vistos.add(i.produto.id)) {
        throw const RegraException(
            'O mesmo produto foi informado mais de uma vez na operação.');
      }
      if (i.quantidade < 1) {
        throw const RegraException(
            'Selecione o produto e informe uma quantidade maior que zero.');
      }
      if (!i.produto.ativo) {
        throw RegraException('${i.produto.nome} está desativado.');
      }
      if (i.produto.estoque < i.quantidade) {
        throw RegraException(
            '${i.produto.nome}: há somente ${i.produto.estoque} no estoque.');
      }
    }
    final ref = _col.doc();
    final batch = _db.batch();
    final linhas = [
      for (final i in itens)
        ItemRetirada(
          produtoId: i.produto.id,
          produtoNome: i.produto.nome,
          quantidade: i.quantidade,
          custoUnitario: i.produto.custo,
          precoUnitario: i.produto.preco,
        ),
    ];
    final totalCusto =
        deCentavos(centavos(linhas.fold<double>(0, (s, l) => s + l.totalCusto)));
    final totalVenda =
        deCentavos(centavos(linhas.fold<double>(0, (s, l) => s + l.totalVenda)));
    final obs = observacao.trim();
    batch.set(ref, {
      'funcionario': {'uid': funcionario.id, 'nome': funcionario.nome},
      'funcionarioId': funcionario.id,
      'registradoPor': Sessao.instancia.autor,
      'observacao': obs.length > 255 ? obs.substring(0, 255) : obs,
      'itens': linhas.map((l) => l.toMap()).toList(),
      'totalCusto': totalCusto,
      'totalVenda': totalVenda,
      'status': Retirada.ativa,
      'data': Timestamp.now(),
    });
    for (final i in itens) {
      Estoque.movimentar(batch,
          produto: i.produto,
          quantidade: -i.quantidade,
          tipo: MovimentoEstoque.retirada,
          referenciaTipo: 'retirada',
          referenciaId: ref.id,
          motivo: 'Consumo de ${funcionario.nome}');
    }
    AuditoriaRepository.noBatch(
        batch, 'employee_withdrawal.create', 'Retirada de funcionário registrada',
        entidade: 'retirada',
        entidadeId: ref.id,
        depois: {
          'funcionario': funcionario.nome,
          'itens': linhas.map((l) => l.toMap()).toList(),
          'observacao': obs,
        });
    semAguardar(batch.commit(), 'retirada ${ref.id}');
    return ref.id;
  }

  void cancelar(Retirada retirada, String motivo, Map<String, Produto> produtos) {
    final m = motivo.trim();
    if (m.length < 5) {
      throw const RegraException(
          'Informe um motivo com pelo menos 5 caracteres.');
    }
    if (!retirada.isAtiva) {
      throw const RegraException('Retirada não encontrada ou já cancelada.');
    }
    final motivoFinal = m.length > 255 ? m.substring(0, 255) : m;
    final batch = _db.batch();
    for (final i in retirada.itens) {
      Estoque.movimentar(batch,
          produto: produtos[i.produtoId] ??
              Produto(id: i.produtoId, nome: i.produtoNome, preco: i.precoUnitario),
          quantidade: i.quantidade,
          tipo: MovimentoEstoque.retiradaDevolucao,
          referenciaTipo: 'retirada',
          referenciaId: retirada.id,
          motivo: 'Cancelamento: $motivoFinal');
    }
    batch.update(_col.doc(retirada.id), {
      'status': Retirada.cancelada,
      'cancelamento': {
        'em': Timestamp.now(),
        'por': Sessao.instancia.autor,
        'motivo': motivoFinal,
      },
    });
    AuditoriaRepository.noBatch(batch, 'employee_withdrawal.cancel',
        'Retirada de funcionário cancelada e estoque devolvido',
        entidade: 'retirada',
        entidadeId: retirada.id,
        depois: {'motivo': motivoFinal});
    semAguardar(batch.commit(), 'cancelamento da retirada ${retirada.id}');
  }
}
