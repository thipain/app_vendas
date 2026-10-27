import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/movimento_estoque.dart';
import '../models/produto.dart';
import 'auditoria_repository.dart';
import 'estoque.dart';
import 'offline.dart';
import 'banco.dart';

class ProdutoRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => Banco.col('produtos');

  /// Todos os produtos (ativos e desativados) em ordem alfabética.
  /// Funciona offline a partir do cache.
  Stream<List<Produto>> watchTodos() => _col
      .orderBy('nomeBusca')
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Produto.fromDoc).toList());

  Stream<List<Produto>> watchAtivos() =>
      watchTodos().map((l) => l.where((p) => p.ativo).toList());

  /// Cadastra um produto novo com o saldo inicial informado.
  String criar(Produto produto, {int estoqueInicial = 0}) {
    final ref = _col.doc();
    final batch = _db.batch();
    batch.set(ref, {
      ...produto.toMap(),
      'estoque': 0,
      'criadoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    final novo = produto.copyWith(id: ref.id, estoque: 0);
    Estoque.movimentar(
      batch,
      produto: novo,
      quantidade: estoqueInicial,
      tipo: MovimentoEstoque.inicial,
      referenciaTipo: 'produto',
      referenciaId: ref.id,
      motivo: 'Estoque inicial do cadastro',
    );
    AuditoriaRepository.noBatch(
      batch,
      'product.create',
      'Produto cadastrado',
      entidade: 'produto',
      entidadeId: ref.id,
      depois: {...produto.resumo(), 'estoqueInicial': estoqueInicial},
    );
    semAguardar(batch.commit(), 'produto ${produto.nome}');
    return ref.id;
  }

  /// Altera os dados cadastrais (o saldo só muda por ajuste ou operações).
  void editar(Produto antes, Produto depois) {
    final batch = _db.batch();
    batch.update(_col.doc(antes.id), {
      ...depois.toMap(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    AuditoriaRepository.noBatch(
      batch,
      'product.update',
      'Produto alterado',
      entidade: 'produto',
      entidadeId: antes.id,
      antes: antes.resumo(),
      depois: depois.resumo(),
    );
    semAguardar(batch.commit(), 'produto ${depois.nome}');
  }

  /// Ajuste manual de saldo, com justificativa obrigatória.
  void ajustarEstoque(
    Produto produto,
    int novoSaldo,
    String motivo, {
    bool perda = false,
  }) {
    final diferenca = novoSaldo - produto.estoque;
    if (diferenca == 0) return;
    final batch = _db.batch();
    Estoque.movimentar(
      batch,
      produto: produto,
      quantidade: diferenca,
      tipo: perda ? MovimentoEstoque.perda : MovimentoEstoque.ajuste,
      referenciaTipo: 'produto',
      referenciaId: produto.id,
      motivo: motivo,
    );
    AuditoriaRepository.noBatch(
      batch,
      'stock.adjust',
      'Ajuste manual de estoque',
      entidade: 'produto',
      entidadeId: produto.id,
      antes: {'estoque': produto.estoque},
      depois: {'estoque': novoSaldo, 'motivo': motivo},
    );
    semAguardar(batch.commit(), 'ajuste de ${produto.nome}');
  }

  /// Exclusão lógica: vendas antigas continuam apontando para o produto, e a
  /// baixa de estoque de uma venda feita offline não falha ao sincronizar.
  void definirAtivo(Produto produto, bool ativo) {
    final batch = _db.batch();
    batch.update(_col.doc(produto.id), {
      'ativo': ativo,
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    AuditoriaRepository.noBatch(
      batch,
      ativo ? 'product.restore' : 'product.delete',
      ativo ? 'Produto restaurado' : 'Produto desativado',
      entidade: 'produto',
      entidadeId: produto.id,
    );
    semAguardar(batch.commit(), 'produto ${produto.nome}');
  }
}
