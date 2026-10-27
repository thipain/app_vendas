import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/comanda.dart';
import '../models/movimento_estoque.dart';
import '../models/produto.dart';
import 'auditoria_repository.dart';
import 'estoque.dart';
import 'offline.dart';

class ComandaRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('comandas');

  Stream<List<Comanda>> watchAbertas() => _col
      .where('status', isEqualTo: Comanda.aberta)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Comanda.fromDoc).toList()
        ..sort((a, b) => a.abertaEm.compareTo(b.abertaEm)));

  Stream<Comanda?> watch(String id) => _col
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? Comanda.fromDoc(d) : null);

  static String _validarNome(String nome) {
    final n = nome.trim();
    if (n.isEmpty || n.length > 100) {
      throw const RegraException('Informe um nome de até 100 caracteres.');
    }
    return n;
  }

  String criar(String nome, int pessoas) {
    final n = _validarNome(nome);
    final p = pessoas.clamp(1, 999);
    final ref = _col.doc();
    final batch = _db.batch();
    batch.set(ref, {
      'nome': n,
      'pessoas': p,
      'status': Comanda.aberta,
      'abertaPor': Sessao.instancia.autor,
      'abertaEm': Timestamp.now(),
      'itens': <String, Object>{},
    });
    AuditoriaRepository.noBatch(batch, 'tab.create', 'Comanda aberta',
        entidade: 'comanda', entidadeId: ref.id, depois: {'nome': n, 'pessoas': p});
    semAguardar(batch.commit(), 'comanda $n');
    return ref.id;
  }

  void renomear(Comanda comanda, String nome) {
    final n = _validarNome(nome);
    if (!comanda.isAberta) throw const RegraException('Comanda não encontrada.');
    final batch = _db.batch();
    batch.update(_col.doc(comanda.id), {'nome': n});
    AuditoriaRepository.noBatch(batch, 'tab.rename', 'Comanda renomeada',
        entidade: 'comanda',
        entidadeId: comanda.id,
        antes: {'nome': comanda.nome},
        depois: {'nome': n});
    semAguardar(batch.commit(), 'comanda $n');
  }

  /// Altera a quantidade de um item (0 remove o item e devolve ao estoque).
  void alterarQuantidade(
      Comanda comanda, ItemComanda item, int novaQuantidade, Produto? produto) {
    if (!comanda.isAberta) throw const RegraException('Comanda não encontrada.');
    final nova = novaQuantidade < 0 ? 0 : novaQuantidade;
    final diferenca = nova - item.quantidade;
    if (diferenca == 0) return;
    final p = produto ??
        Produto(id: item.produtoId, nome: item.nome, preco: item.precoUnitario);
    if (diferenca > 0 && diferenca > p.estoque) {
      throw RegraException(
          '${p.nome}: estoque insuficiente para aumentar a quantidade.');
    }
    final batch = _db.batch();
    batch.update(_col.doc(comanda.id), {
      if (nova == 0)
        'itens.${item.produtoId}': FieldValue.delete()
      else
        'itens.${item.produtoId}.quantidade': FieldValue.increment(diferenca),
    });
    Estoque.movimentar(batch,
        produto: p,
        quantidade: -diferenca,
        tipo: MovimentoEstoque.comanda,
        referenciaTipo: 'comanda',
        referenciaId: comanda.id,
        motivo: nova == 0
            ? 'Item removido da comanda'
            : 'Quantidade da comanda alterada');
    AuditoriaRepository.noBatch(
        batch,
        nova == 0 ? 'tab.item_remove' : 'tab.item_update',
        nova == 0 ? 'Item removido da comanda' : 'Quantidade da comanda alterada',
        entidade: 'comanda',
        entidadeId: comanda.id,
        antes: {'produto': item.nome, 'quantidade': item.quantidade},
        depois: {'quantidade': nova});
    semAguardar(batch.commit(), 'item da comanda ${comanda.nome}');
  }

  /// Cancela a comanda e devolve todos os itens ao estoque.
  void cancelar(Comanda comanda, Map<String, Produto> produtos) {
    if (!comanda.isAberta) throw const RegraException('Comanda não encontrada.');
    final batch = _db.batch();
    for (final i in comanda.itens) {
      Estoque.movimentar(batch,
          produto: produtos[i.produtoId] ??
              Produto(id: i.produtoId, nome: i.nome, preco: i.precoUnitario),
          quantidade: i.quantidade,
          tipo: MovimentoEstoque.comanda,
          referenciaTipo: 'comanda',
          referenciaId: comanda.id,
          motivo: 'Cancelamento da comanda');
    }
    batch.update(_col.doc(comanda.id), {
      'status': Comanda.cancelada,
      'fechadaEm': Timestamp.now(),
      'itens': <String, Object>{},
    });
    AuditoriaRepository.noBatch(batch, 'tab.cancel', 'Comanda cancelada',
        entidade: 'comanda',
        entidadeId: comanda.id,
        antes: {
          'nome': comanda.nome,
          'itens': [
            for (final i in comanda.itens)
              {'produto': i.nome, 'quantidade': i.quantidade}
          ],
        });
    semAguardar(batch.commit(), 'cancelamento da comanda ${comanda.nome}');
  }
}
