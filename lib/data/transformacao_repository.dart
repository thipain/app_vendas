import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/movimento_estoque.dart';
import '../models/produto.dart';
import '../models/transformacao.dart';
import 'auditoria_repository.dart';
import 'estoque.dart';
import 'offline.dart';

/// Montagem e desmanche de produtos.
class TransformacaoRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _receitas =>
      _db.collection('receitas');
  CollectionReference<Map<String, dynamic>> get _operacoes =>
      _db.collection('operacoesEstoque');

  Stream<List<Receita>> watchReceitas() => _receitas
      .orderBy('nomeBusca')
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Receita.fromDoc).toList());

  Stream<List<OperacaoEstoque>> watchOperacoes({int limite = 100}) => _operacoes
      .orderBy('data', descending: true)
      .limit(limite)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(OperacaoEstoque.fromDoc).toList());

  static void validar(String tipo, List<ItemReceita> entradas,
      List<ItemReceita> saidas) {
    if (entradas.isEmpty || saidas.isEmpty) {
      throw const RegraException('Informe ao menos uma entrada e uma saída.');
    }
    for (final i in [...entradas, ...saidas]) {
      if (i.produtoId.isEmpty || i.quantidade <= 0 || i.quantidade > 1000000) {
        throw const RegraException(
            'Selecione o produto e informe uma quantidade maior que zero.');
      }
    }
    if (tipo == Receita.composicao && saidas.length != 1) {
      throw const RegraException(
          'Uma montagem deve gerar exatamente um produto final.');
    }
    if (tipo == Receita.decomposicao && entradas.length != 1) {
      throw const RegraException(
          'Um desmanche deve consumir exatamente um item agrupado.');
    }
    final idsEntrada = entradas.map((i) => i.produtoId).toList();
    final idsSaida = saidas.map((i) => i.produtoId).toList();
    if (idsEntrada.toSet().length != idsEntrada.length ||
        idsSaida.toSet().length != idsSaida.length) {
      throw const RegraException(
          'O mesmo produto foi informado mais de uma vez na operação.');
    }
    if (idsEntrada.any(idsSaida.contains)) {
      throw const RegraException(
          'Um produto não pode ser entrada e saída na mesma operação.');
    }
  }

  void salvarReceita(Receita receita, Map<String, Produto> produtos,
      {Receita? antiga}) {
    final nome = receita.nome.trim();
    if (nome.isEmpty || nome.length > 160) {
      throw const RegraException(
          'Informe um nome de até 160 caracteres para a operação.');
    }
    validar(receita.tipo, receita.entradas, receita.saidas);
    for (final i in [...receita.entradas, ...receita.saidas]) {
      final p = produtos[i.produtoId];
      if (p == null || !p.ativo) {
        throw const RegraException('Use somente produtos ativos na operação.');
      }
    }
    final ref = antiga == null ? _receitas.doc() : _receitas.doc(antiga.id);
    final batch = _db.batch();
    batch.set(ref, {
      ...receita.toMap(),
      'atualizadoEm': FieldValue.serverTimestamp(),
      if (antiga == null) 'criadoPor': Sessao.instancia.autor,
    }, SetOptions(merge: true));
    AuditoriaRepository.noBatch(
        batch,
        antiga == null ? 'recipe.create' : 'recipe.update',
        antiga == null
            ? 'Operação de estoque criada'
            : 'Operação de estoque atualizada',
        entidade: 'receita',
        entidadeId: ref.id,
        antes: antiga?.toMap(),
        depois: receita.toMap());
    semAguardar(batch.commit(), 'receita $nome');
  }

  void definirAtivo(Receita receita, bool ativo) {
    final batch = _db.batch();
    batch.update(_receitas.doc(receita.id), {'ativo': ativo});
    AuditoriaRepository.noBatch(
        batch,
        'recipe.toggle',
        ativo
            ? 'Operação de estoque reativada'
            : 'Operação de estoque desativada',
        entidade: 'receita',
        entidadeId: receita.id,
        depois: {'ativo': ativo});
    semAguardar(batch.commit(), 'receita ${receita.nome}');
  }

  /// Executa [lotes] vezes a receita. Se faltar qualquer item de entrada, nada
  /// é alterado. Quando há um único produto gerado, o custo dele passa a ser
  /// a média ponderada entre o saldo atual e o custo dos itens consumidos.
  String executar(Receita receita, int lotes, String observacao,
      Map<String, Produto> produtos) {
    if (lotes < 1 || lotes > 100000) {
      throw const RegraException(
          'Informe uma quantidade de lotes entre 1 e 100.000.');
    }
    if (!receita.ativo) {
      throw const RegraException('Operação não encontrada ou desativada.');
    }
    validar(receita.tipo, receita.entradas, receita.saidas);
    for (final i in [...receita.entradas, ...receita.saidas]) {
      final p = produtos[i.produtoId];
      if (p == null || !p.ativo) {
        throw const RegraException(
            'A operação contém um produto desativado. Edite a configuração antes de continuar.');
      }
    }
    for (final i in receita.entradas) {
      final p = produtos[i.produtoId]!;
      final necessario = i.quantidade * lotes;
      if (p.estoque < necessario) {
        throw RegraException(
            '${p.nome}: são necessários $necessario, mas existem apenas ${p.estoque} no estoque.');
      }
    }

    double? custoDerivado;
    if (receita.saidas.length == 1) {
      final custoEntradas = receita.entradas.fold<double>(
          0, (s, i) => s + produtos[i.produtoId]!.custo * i.quantidade * lotes);
      final gerado = receita.saidas.first.quantidade * lotes;
      if (gerado > 0 && custoEntradas > 0) custoDerivado = custoEntradas / gerado;
    }

    final ref = _operacoes.doc();
    final batch = _db.batch();
    final tipoMov = receita.isComposicao
        ? MovimentoEstoque.composicao
        : MovimentoEstoque.decomposicao;
    final itens = <ItemOperacao>[];
    void mover(ItemReceita i, String direcao) {
      final p = produtos[i.produtoId]!;
      final qtd = i.quantidade * lotes;
      final mudanca = direcao == 'entrada' ? -qtd : qtd;
      final depois = p.estoque + mudanca;
      Map<String, dynamic> extra = const {};
      if (direcao == 'saida' && custoDerivado != null) {
        final custo = depois > 0
            ? ((p.estoque * p.custo) + (qtd * custoDerivado)) / depois
            : custoDerivado;
        extra = {'custo': (custo * 10000).roundToDouble() / 10000};
      }
      Estoque.movimentar(batch,
          produto: p,
          quantidade: mudanca,
          tipo: tipoMov,
          referenciaTipo: 'operacao_estoque',
          referenciaId: ref.id,
          motivo: receita.nome,
          extra: extra);
      itens.add(ItemOperacao(
        produtoId: p.id,
        produtoNome: p.nome,
        direcao: direcao,
        quantidade: qtd,
        estoqueAntes: p.estoque,
        estoqueDepois: depois,
      ));
    }

    for (final i in receita.entradas) {
      mover(i, 'entrada');
    }
    for (final i in receita.saidas) {
      mover(i, 'saida');
    }
    batch.set(ref, {
      'receitaId': receita.id,
      'receitaNome': receita.nome,
      'tipo': receita.tipo,
      'lotes': lotes,
      'observacao': observacao.trim(),
      'itens': itens.map((i) => i.toMap()).toList(),
      'usuario': Sessao.instancia.autor,
      'data': Timestamp.now(),
    });
    AuditoriaRepository.noBatch(
        batch, 'recipe.execute', 'Operação de estoque executada',
        entidade: 'operacao_estoque',
        entidadeId: ref.id,
        depois: {
          'receitaId': receita.id,
          'lotes': lotes,
          'observacao': observacao.trim(),
        });
    semAguardar(batch.commit(), 'operação ${receita.nome}');
    return ref.id;
  }
}
