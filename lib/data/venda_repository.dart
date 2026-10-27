import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';
import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/caixa.dart';
import '../models/comanda.dart';
import '../models/movimento_estoque.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'auditoria_repository.dart';
import 'caixa_repository.dart';
import 'estoque.dart';
import 'offline.dart';

/// Linha do carrinho antes de virar venda.
class ItemCarrinho {
  final Produto produto;
  final int quantidade;
  const ItemCarrinho(this.produto, this.quantidade);
}

class VendaRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _vendas =>
      _db.collection('vendas');
  CollectionReference<Map<String, dynamic>> get _comandas =>
      _db.collection('comandas');

  Stream<List<Venda>> watchRecentes({int limite = 200}) => _vendas
      .orderBy('data', descending: true)
      .limit(limite)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Venda.fromDoc).toList());

  /// Vendas de [inicio] (inclusive) até [fim] (exclusivo).
  Stream<List<Venda>> watchPeriodo(DateTime inicio, DateTime fim) => _vendas
      .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
      .where('data', isLessThan: Timestamp.fromDate(fim))
      .orderBy('data', descending: true)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Venda.fromDoc).toList());

  Stream<Venda?> watch(String id) => _vendas
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? Venda.fromDoc(d) : null);

  static void _validarCarrinho(List<ItemCarrinho> carrinho) {
    if (carrinho.isEmpty) {
      throw const RegraException('Adicione ao menos um produto.');
    }
    if (carrinho.length > 200) {
      throw const RegraException('A venda possui itens demais.');
    }
    for (final i in carrinho) {
      if (i.quantidade < 1) throw const RegraException('Quantidade inválida.');
      if (!i.produto.ativo) throw const RegraException('Produto não encontrado.');
      if (i.quantidade > i.produto.estoque) {
        throw RegraException(
            '${i.produto.nome}: há somente ${i.produto.estoque} em estoque.');
      }
    }
  }

  /// Grava a venda, os pagamentos, o dinheiro no caixa e a auditoria.
  /// O estoque é baixado pelo chamador (venda direta) ou já foi baixado
  /// (comanda).
  Venda _gravarVenda(
    WriteBatch batch,
    DocumentReference<Map<String, dynamic>> ref, {
    required List<ItemVenda> itens,
    required bool descontoPercentual,
    required double descontoInformado,
    required List<Pagamento> pagamentos,
    required Caixa caixa,
    Comanda? comanda,
    String? clienteId,
    String? clienteNome,
  }) {
    final subtotal = itens.fold<int>(0, (s, i) => s + i.totalCentavos);
    final desconto =
        calcularDesconto(subtotal, descontoPercentual, descontoInformado);
    final processados = processarPagamentos(pagamentos, subtotal - desconto);
    final eu = Sessao.instancia.atual;
    final venda = Venda(
      id: ref.id,
      clienteId: clienteId,
      clienteNome: clienteNome,
      itens: itens,
      pagamentos: processados,
      descontoPercentual: descontoPercentual,
      descontoInformado: descontoInformado < 0 ? 0 : descontoInformado,
      desconto: deCentavos(desconto),
      formaPagamento: processados.first.forma,
      caixaId: caixa.id,
      comandaId: comanda?.id,
      comandaNome: comanda?.nome,
      vendedorId: eu.id,
      vendedorNome: eu.nome,
      data: DateTime.now(),
    );
    batch.set(ref, {...venda.toMap(), 'criadoEm': FieldValue.serverTimestamp()});
    final dinheiro = venda.valorEmDinheiro;
    if (dinheiro > 0) {
      CaixaRepository.movimentoNoBatch(batch,
          caixaId: caixa.id,
          tipo: MovimentoCaixa.venda,
          valor: dinheiro,
          descricao:
              comanda == null ? 'Venda concluída' : 'Fechamento de comanda',
          vendaId: ref.id);
    }
    return venda;
  }

  /// Venda direta no balcão. Exige caixa aberto.
  Venda registrar({
    required List<ItemCarrinho> carrinho,
    required Caixa? caixa,
    required bool descontoPercentual,
    required double descontoInformado,
    required List<Pagamento> pagamentos,
    String? clienteId,
    String? clienteNome,
  }) {
    if (caixa == null) {
      throw const RegraException('Abra o caixa antes de finalizar uma venda.');
    }
    _validarCarrinho(carrinho);
    final ref = _vendas.doc();
    final batch = _db.batch();
    final venda = _gravarVenda(
      batch,
      ref,
      itens: [
        for (final i in carrinho)
          ItemVenda(
            produtoId: i.produto.id,
            nome: i.produto.nome,
            quantidade: i.quantidade,
            precoUnitario: i.produto.preco,
            custoUnitario: i.produto.custo,
          ),
      ],
      descontoPercentual: descontoPercentual,
      descontoInformado: descontoInformado,
      pagamentos: pagamentos,
      caixa: caixa,
      clienteId: clienteId,
      clienteNome: clienteNome,
    );
    for (final i in carrinho) {
      Estoque.movimentar(batch,
          produto: i.produto,
          quantidade: -i.quantidade,
          tipo: MovimentoEstoque.venda,
          referenciaTipo: 'venda',
          referenciaId: ref.id,
          motivo: 'Venda finalizada');
    }
    AuditoriaRepository.noBatch(batch, 'sale.create', 'Venda registrada',
        entidade: 'venda',
        entidadeId: ref.id,
        depois: {
          'total': venda.total,
          'pagamentos': venda.pagamentos.map((p) => p.toMap()).toList(),
        });
    semAguardar(batch.commit(), 'venda ${ref.id}');
    return venda;
  }

  /// Lança itens numa comanda aberta: o estoque sai agora e o preço da linha
  /// passa a ser o preço atual do produto. Não exige caixa aberto.
  void lancarNaComanda(Comanda comanda, List<ItemCarrinho> carrinho) {
    if (!comanda.isAberta) {
      throw const RegraException('A comanda não está mais aberta.');
    }
    _validarCarrinho(carrinho);
    final batch = _db.batch();
    final ref = _comandas.doc(comanda.id);
    final existentes = {for (final i in comanda.itens) i.produtoId};
    final atualizacao = <String, Object?>{};
    for (final i in carrinho) {
      final p = i.produto;
      atualizacao['itens.${p.id}.quantidade'] =
          FieldValue.increment(i.quantidade);
      atualizacao['itens.${p.id}.precoUnitario'] = p.preco;
      atualizacao['itens.${p.id}.nome'] = p.nome;
      atualizacao['itens.${p.id}.codigo'] = p.codigo;
      if (!existentes.contains(p.id)) {
        atualizacao['itens.${p.id}.adicionadoEm'] = Timestamp.now();
      }
      Estoque.movimentar(batch,
          produto: p,
          quantidade: -i.quantidade,
          tipo: MovimentoEstoque.comanda,
          referenciaTipo: 'comanda',
          referenciaId: comanda.id,
          motivo: 'Item adicionado à comanda');
    }
    batch.update(ref, atualizacao);
    final subtotal = carrinho.fold<int>(
        0, (s, i) => s + centavos(i.produto.preco) * i.quantidade);
    AuditoriaRepository.noBatch(
        batch, 'tab.items_add', 'Itens adicionados à comanda',
        entidade: 'comanda',
        entidadeId: comanda.id,
        depois: {'itens': carrinho.length, 'subtotal': deCentavos(subtotal)});
    semAguardar(batch.commit(), 'itens da comanda ${comanda.nome}');
  }

  /// Fecha a comanda gerando a venda. O estoque já foi baixado nos
  /// lançamentos; o custo usado é o custo atual dos produtos.
  Venda fecharComanda({
    required Comanda comanda,
    required Caixa? caixa,
    required Map<String, Produto> produtos,
    required bool descontoPercentual,
    required double descontoInformado,
    required List<Pagamento> pagamentos,
  }) {
    if (caixa == null) {
      throw const RegraException('Abra o caixa antes de fechar uma comanda.');
    }
    if (!comanda.isAberta) throw const RegraException('Comanda não encontrada.');
    if (comanda.itens.isEmpty) throw const RegraException('A comanda está vazia.');
    final ref = _vendas.doc();
    final batch = _db.batch();
    final venda = _gravarVenda(
      batch,
      ref,
      itens: [
        for (final i in comanda.itens)
          ItemVenda(
            produtoId: i.produtoId,
            nome: i.nome,
            quantidade: i.quantidade,
            precoUnitario: i.precoUnitario,
            custoUnitario: produtos[i.produtoId]?.custo ?? 0,
          ),
      ],
      descontoPercentual: descontoPercentual,
      descontoInformado: descontoInformado,
      pagamentos: pagamentos,
      caixa: caixa,
      comanda: comanda,
    );
    batch.update(_comandas.doc(comanda.id), {
      'status': Comanda.fechada,
      'fechadaEm': Timestamp.now(),
      'vendaId': ref.id,
    });
    AuditoriaRepository.noBatch(batch, 'tab.close', 'Comanda fechada',
        entidade: 'comanda',
        entidadeId: comanda.id,
        depois: {
          'vendaId': ref.id,
          'total': venda.total,
          'pagamentos': venda.pagamentos.map((p) => p.toMap()).toList(),
          'troco': venda.troco,
        });
    semAguardar(batch.commit(), 'fechamento da comanda ${comanda.nome}');
    return venda;
  }

  /// Cancela a venda: devolve os itens ao estoque e, se houve pagamento em
  /// dinheiro, registra o estorno no caixa aberto agora.
  void cancelar(Venda venda, String motivo,
      {required Caixa? caixaAberto, required Map<String, Produto> produtos}) {
    final m = motivo.trim();
    if (m.length < 5) {
      throw const RegraException(
          'Informe um motivo com pelo menos 5 caracteres.');
    }
    if (venda.isCancelada) {
      throw const RegraException('Venda não encontrada ou já cancelada.');
    }
    final dinheiro = venda.valorEmDinheiro;
    if (dinheiro > 0 && caixaAberto == null) {
      throw const RegraException(
          'Abra o caixa antes de estornar uma venda recebida em dinheiro.');
    }
    final motivoFinal = m.length > 255 ? m.substring(0, 255) : m;
    final batch = _db.batch();
    batch.update(_vendas.doc(venda.id), {
      'status': Venda.cancelada,
      'cancelamento': {
        'em': Timestamp.now(),
        'por': Sessao.instancia.autor,
        'motivo': motivoFinal,
      },
    });
    for (final i in venda.itens) {
      final p = produtos[i.produtoId] ??
          Produto(id: i.produtoId, nome: i.nome, preco: i.precoUnitario);
      Estoque.movimentar(batch,
          produto: p,
          quantidade: i.quantidade,
          tipo: MovimentoEstoque.estorno,
          referenciaTipo: 'venda',
          referenciaId: venda.id,
          motivo: 'Cancelamento: $motivoFinal');
    }
    if (dinheiro > 0) {
      CaixaRepository.movimentoNoBatch(batch,
          caixaId: caixaAberto!.id,
          tipo: MovimentoCaixa.estorno,
          valor: dinheiro,
          descricao: 'Estorno: $motivoFinal',
          vendaId: venda.id);
    }
    AuditoriaRepository.noBatch(batch, 'sale.cancel', 'Venda cancelada',
        entidade: 'venda',
        entidadeId: venda.id,
        antes: {'total': venda.total, 'status': venda.status},
        depois: {'motivo': motivoFinal});
    semAguardar(batch.commit(), 'cancelamento da venda ${venda.id}');
  }

  /// Salva o texto completo editado do comprovante. Texto vazio restaura o
  /// layout original.
  void salvarTextoComprovante(Venda venda, String texto) {
    final t = texto.replaceAll('\r\n', '\n').trim();
    if (t.length > 12000) {
      throw const RegraException(
          'O comprovante pode ter no máximo 12.000 caracteres.');
    }
    final batch = _db.batch();
    batch.update(_vendas.doc(venda.id), {
      'textoComprovante': t.isEmpty ? FieldValue.delete() : t,
    });
    AuditoriaRepository.noBatch(
        batch, 'sale.receipt_edit', 'Comprovante editado',
        entidade: 'venda',
        entidadeId: venda.id,
        antes: {'texto': venda.textoComprovante},
        depois: {'texto': t.isEmpty ? null : t});
    semAguardar(batch.commit(), 'comprovante ${venda.id}');
  }
}
