import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/movimento_estoque.dart';
import '../models/nota_entrada.dart';
import '../models/produto.dart';
import 'auditoria_repository.dart';
import 'estoque.dart';
import 'offline.dart';

class NotaEntradaRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('notasEntrada');

  Stream<List<NotaEntrada>> watchPeriodo(DateTime inicio, DateTime fim) => _col
      .where('dataEntrada', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
      .where('dataEntrada', isLessThan: Timestamp.fromDate(fim))
      .orderBy('dataEntrada', descending: true)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(NotaEntrada.fromDoc).toList());

  Stream<NotaEntrada?> watch(String id) => _col
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? NotaEntrada.fromDoc(d) : null);

  /// Cria ou edita uma nota. Na edição, compara os itens antigos com os novos
  /// e movimenta no estoque somente as diferenças. O custo dos produtos da
  /// nota passa a ser o custo unitário informado.
  String salvar({
    NotaEntrada? antiga,
    required DateTime dataEntrada,
    required String numero,
    required String fornecedor,
    required double totalInformado,
    required String observacao,
    required List<ItemNotaEntrada> itens,
    required Map<String, Produto> produtos,
  }) {
    if (itens.isEmpty) {
      throw const RegraException('Adicione ao menos um produto à nota.');
    }
    final vistos = <String>{};
    for (final i in itens) {
      if (i.quantidade <= 0 || i.quantidade > 1000000) {
        throw const RegraException(
            'Selecione o produto e informe uma quantidade maior que zero.');
      }
      if (!vistos.add(i.produtoId)) {
        throw const RegraException(
            'O mesmo produto foi informado mais de uma vez na nota.');
      }
      if (i.custoUnitario < 0) {
        throw const RegraException('O custo unitário não pode ser negativo.');
      }
    }

    final antigos = {for (final i in antiga?.itens ?? <ItemNotaEntrada>[]) i.produtoId: i};
    final novos = <String, ItemNotaEntrada>{};
    for (final i in itens) {
      final p = produtos[i.produtoId];
      if (p == null) throw const RegraException('Um dos produtos não existe mais.');
      if (!p.ativo && !antigos.containsKey(i.produtoId)) {
        throw RegraException(
            '${p.nome}: produtos desativados não podem ser adicionados a uma nota.');
      }
      final custo = i.custoUnitario > 0
          ? i.custoUnitario
          : (antigos[i.produtoId]?.custoUnitario ?? p.custo);
      novos[i.produtoId] = ItemNotaEntrada(
        produtoId: p.id,
        produtoNome: p.nome,
        quantidade: i.quantidade,
        custoUnitario: custo,
      );
    }
    final soma = novos.values.fold<double>(0, (s, i) => s + i.custoTotal);
    final total = totalInformado > 0 ? totalInformado : soma;

    final ids = {...antigos.keys, ...novos.keys};
    for (final id in ids) {
      final p = produtos[id];
      if (p == null) throw const RegraException('Um dos produtos não existe mais.');
      final mudanca =
          (novos[id]?.quantidade ?? 0) - (antigos[id]?.quantidade ?? 0);
      if (p.estoque + mudanca < 0) {
        throw RegraException(
            '${p.nome}: não há saldo suficiente para reduzir essa quantidade da nota.');
      }
    }

    final ref = antiga == null ? _col.doc() : _col.doc(antiga.id);
    final batch = _db.batch();
    final dados = {
      'dataEntrada': Timestamp.fromDate(
          DateTime(dataEntrada.year, dataEntrada.month, dataEntrada.day)),
      'numero': numero.trim(),
      'fornecedor': fornecedor.trim(),
      'total': total,
      'observacao': observacao.trim(),
      'itens': novos.values.map((i) => i.toMap()).toList(),
    };
    if (antiga == null) {
      batch.set(ref, {
        ...dados,
        'criadoPor': Sessao.instancia.autor,
        'criadoEm': Timestamp.now(),
      });
    } else {
      batch.update(ref, {
        ...dados,
        'editadoPor': Sessao.instancia.autor,
        'editadoEm': Timestamp.now(),
      });
    }

    for (final id in ids) {
      final p = produtos[id]!;
      final mudanca =
          (novos[id]?.quantidade ?? 0) - (antigos[id]?.quantidade ?? 0);
      Estoque.movimentar(
        batch,
        produto: p,
        quantidade: mudanca,
        tipo: antiga == null
            ? MovimentoEstoque.entrada
            : MovimentoEstoque.entradaEdicao,
        referenciaTipo: 'nota_entrada',
        referenciaId: ref.id,
        motivo: antiga == null
            ? 'Entrada de mercadorias'
            : 'Edição da nota de entrada',
        extra: {if (novos.containsKey(id)) 'custo': novos[id]!.custoUnitario},
      );
    }

    AuditoriaRepository.noBatch(
      batch,
      antiga == null ? 'goods_entry.create' : 'goods_entry.update',
      antiga == null
          ? 'Nota de entrada criada'
          : 'Nota de entrada alterada e estoque reconciliado',
      entidade: 'nota_entrada',
      entidadeId: ref.id,
      antes: antiga == null
          ? null
          : {
              'total': antiga.total,
              'itens': antiga.itens.map((i) => i.toMap()).toList(),
            },
      depois: Map.of(dados)..remove('dataEntrada'),
    );
    semAguardar(batch.commit(), 'nota de entrada ${ref.id}');
    return ref.id;
  }
}
