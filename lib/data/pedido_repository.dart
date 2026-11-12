import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';
import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/comanda.dart';
import '../models/movimento_estoque.dart';
import '../models/pedido.dart';
import '../models/produto.dart';
import '../models/motoboy.dart';
import '../models/venda.dart';
import 'auditoria_repository.dart';
import 'banco.dart';
import 'estoque.dart';
import 'offline.dart';
import 'venda_repository.dart';

/// Pedidos de delivery. A conclusão (que gera a venda) fica no
/// VendaRepository, junto com as outras formas de gerar venda.
class PedidoRepository {
  final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get colecao =>
      Banco.col('pedidos');

  /// Comprovante do Pix fica num documento à parte, para que a imagem não
  /// seja baixada junto com a lista de pedidos.
  static DocumentReference<Map<String, dynamic>> _comprovante(String id) =>
      colecao.doc(id).collection('anexos').doc('comprovante');

  static int _ordem(Pedido a, Pedido b) => a.criadoEm.compareTo(b.criadoEm);

  /// Pedidos ainda não concluídos nem cancelados (painel da loja).
  Stream<List<Pedido>> watchAtivos() => colecao
      .where('status', whereIn: Pedido.ativos)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Pedido.fromDoc).toList()..sort(_ordem));

  /// Entregas atribuídas a um entregador, a caminho ou aguardando o acerto.
  Stream<List<Pedido>> watchDoEntregador(String uid) => colecao
      .where('entregadorId', isEqualTo: uid)
      .where('status', whereIn: [Pedido.emRota, Pedido.entregue])
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Pedido.fromDoc).toList()..sort(_ordem));

  Stream<Pedido?> watch(String id) => colecao
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? Pedido.fromDoc(d) : null);

  /// Imagem do comprovante do Pix em base64 (null = sem comprovante).
  Stream<String?> watchComprovante(String id) =>
      _comprovante(id).snapshots().map((d) => d.data()?['imagem'] as String?);

  static DadosPedido _validar(DadosPedido d) {
    final nome = d.clienteNome.trim();
    final telefone = d.telefone.trim();
    final endereco = d.endereco.trim();
    if (nome.isEmpty || nome.length > 100) {
      throw const RegraException('Informe o nome do cliente (até 100 letras).');
    }
    if (telefone.replaceAll(RegExp(r'\D'), '').length < 8 ||
        telefone.length > 30) {
      throw const RegraException('Informe um telefone válido do cliente.');
    }
    if (endereco.isEmpty || endereco.length > 200) {
      throw const RegraException('Informe o endereço de entrega.');
    }
    if (d.bairro.trim().length > 80 ||
        d.referencia.trim().length > 200 ||
        d.observacao.trim().length > 300) {
      throw const RegraException(
        'Um dos campos do pedido ultrapassa o tamanho permitido.',
      );
    }
    if (d.taxaEntrega < 0 || d.taxaEntrega > 1000) {
      throw const RegraException('Taxa de entrega inválida.');
    }
    if (!FormaPagamento.todas.contains(d.formaPagamento)) {
      throw const RegraException('Escolha a forma de pagamento.');
    }
    final troco = d.trocoPara;
    if (troco != null && (troco <= 0 || troco > 10000)) {
      throw const RegraException('Valor para troco inválido.');
    }
    return DadosPedido(
      clienteId: d.clienteId,
      clienteNome: nome,
      telefone: telefone,
      endereco: endereco,
      bairro: d.bairro.trim(),
      referencia: d.referencia.trim(),
      observacao: d.observacao.trim(),
      taxaEntrega: deCentavos(centavos(d.taxaEntrega)),
      formaPagamento: d.formaPagamento,
      trocoPara: troco == null ? null : deCentavos(centavos(troco)),
    );
  }

  static void _validarTroco(DadosPedido d, int totalCentavos) {
    final t = d.trocoPara;
    if (d.formaPagamento == FormaPagamento.dinheiro &&
        t != null &&
        centavos(t) < totalCentavos) {
      throw const RegraException(
        'O valor para troco é menor que o total do pedido.',
      );
    }
  }

  Map<String, Object> _linhaItem(Produto p, int quantidade, bool nova) => {
    'quantidade': FieldValue.increment(quantidade),
    'precoUnitario': p.preco,
    'nome': p.nome,
    'codigo': p.codigo,
    if (nova) 'adicionadoEm': Timestamp.now(),
  };

  /// Registra o pedido e baixa o estoque dos itens. Retorna o id.
  String criar(DadosPedido dados, List<ItemCarrinho> carrinho) {
    final d = _validar(dados);
    VendaRepository.validarCarrinho(carrinho);
    final subtotal = carrinho.fold<int>(
      0,
      (s, i) => s + centavos(i.produto.preco) * i.quantidade,
    );
    _validarTroco(d, subtotal + centavos(d.taxaEntrega));
    final ref = colecao.doc();
    final batch = _db.batch();
    batch.set(ref, {
      ...d.toMap(),
      'status': Pedido.novo,
      'canal': 'balcao',
      'itens': {
        for (final i in carrinho)
          i.produto.id: {
            'quantidade': i.quantidade,
            'precoUnitario': i.produto.preco,
            'nome': i.produto.nome,
            'codigo': i.produto.codigo,
            'adicionadoEm': Timestamp.now(),
          },
      },
      'pixConfirmado': false,
      'temComprovante': false,
      'entregadorId': null,
      'criadoPor': Sessao.instancia.autor,
      'criadoEm': Timestamp.now(),
    });
    for (final i in carrinho) {
      Estoque.movimentar(
        batch,
        produto: i.produto,
        quantidade: -i.quantidade,
        tipo: MovimentoEstoque.delivery,
        referenciaTipo: 'pedido',
        referenciaId: ref.id,
        motivo: 'Pedido de delivery',
      );
    }
    AuditoriaRepository.noBatch(
      batch,
      'delivery.create',
      'Pedido de delivery registrado',
      entidade: 'pedido',
      entidadeId: ref.id,
      depois: {
        'cliente': d.clienteNome,
        'subtotal': deCentavos(subtotal),
        'taxaEntrega': d.taxaEntrega,
        'formaPagamento': d.formaPagamento,
      },
    );
    semAguardar(batch.commit(), 'pedido de ${d.clienteNome}');
    return ref.id;
  }

  void _exigirAtivo(Pedido p) {
    if (!p.isAtivo) {
      throw const RegraException('O pedido já foi concluído ou cancelado.');
    }
  }

  /// Altera cliente, endereço, taxa e pagamento.
  void editarDados(Pedido pedido, DadosPedido dados) {
    _exigirAtivo(pedido);
    final d = _validar(dados);
    _validarTroco(d, pedido.subtotalCentavos + centavos(d.taxaEntrega));
    final batch = _db.batch();
    final mudouForma = d.formaPagamento != pedido.formaPagamento;
    batch.update(colecao.doc(pedido.id), {
      ...d.toMap(),
      if (mudouForma) 'pixConfirmado': false,
    });
    AuditoriaRepository.noBatch(
      batch,
      'delivery.update',
      'Pedido de delivery alterado',
      entidade: 'pedido',
      entidadeId: pedido.id,
      antes: DadosPedido.de(pedido).toMap(),
      depois: d.toMap(),
    );
    semAguardar(batch.commit(), 'pedido ${pedido.codigo}');
  }

  /// Acrescenta itens (antes de o pedido sair para entrega).
  void adicionarItens(Pedido pedido, List<ItemCarrinho> carrinho) {
    if (!pedido.podeAlterarItens) {
      throw const RegraException(
        'Os itens só podem mudar antes de o pedido sair para entrega.',
      );
    }
    VendaRepository.validarCarrinho(carrinho);
    final existentes = {for (final i in pedido.itens) i.produtoId};
    final batch = _db.batch();
    final atualizacao = <String, Object?>{};
    for (final i in carrinho) {
      final linha = _linhaItem(
        i.produto,
        i.quantidade,
        !existentes.contains(i.produto.id),
      );
      linha.forEach((k, v) => atualizacao['itens.${i.produto.id}.$k'] = v);
      Estoque.movimentar(
        batch,
        produto: i.produto,
        quantidade: -i.quantidade,
        tipo: MovimentoEstoque.delivery,
        referenciaTipo: 'pedido',
        referenciaId: pedido.id,
        motivo: 'Item adicionado ao pedido',
      );
    }
    batch.update(colecao.doc(pedido.id), atualizacao);
    AuditoriaRepository.noBatch(
      batch,
      'delivery.items_add',
      'Itens adicionados ao pedido',
      entidade: 'pedido',
      entidadeId: pedido.id,
      depois: {
        'itens': [
          for (final i in carrinho)
            {'produto': i.produto.nome, 'quantidade': i.quantidade},
        ],
      },
    );
    semAguardar(batch.commit(), 'itens do pedido ${pedido.codigo}');
  }

  /// Altera a quantidade de um item (0 remove e devolve ao estoque).
  void alterarQuantidade(
    Pedido pedido,
    ItemComanda item,
    int novaQuantidade,
    Produto? produto,
  ) {
    if (!pedido.podeAlterarItens) {
      throw const RegraException(
        'Os itens só podem mudar antes de o pedido sair para entrega.',
      );
    }
    final nova = novaQuantidade < 0 ? 0 : novaQuantidade;
    final diferenca = nova - item.quantidade;
    if (diferenca == 0) return;
    if (nova == 0 && pedido.itens.length == 1) {
      throw const RegraException(
        'O pedido precisa de ao menos um item. Para desistir, cancele o pedido.',
      );
    }
    final p =
        produto ??
        Produto(id: item.produtoId, nome: item.nome, preco: item.precoUnitario);
    if (diferenca > 0 && diferenca > p.estoque) {
      throw RegraException('${p.nome}: estoque insuficiente.');
    }
    final batch = _db.batch();
    batch.update(colecao.doc(pedido.id), {
      if (nova == 0)
        'itens.${item.produtoId}': FieldValue.delete()
      else
        'itens.${item.produtoId}.quantidade': FieldValue.increment(diferenca),
    });
    Estoque.movimentar(
      batch,
      produto: p,
      quantidade: -diferenca,
      tipo: MovimentoEstoque.delivery,
      referenciaTipo: 'pedido',
      referenciaId: pedido.id,
      motivo: nova == 0
          ? 'Item removido do pedido'
          : 'Quantidade do pedido alterada',
    );
    AuditoriaRepository.noBatch(
      batch,
      'delivery.item_update',
      nova == 0 ? 'Item removido do pedido' : 'Quantidade do pedido alterada',
      entidade: 'pedido',
      entidadeId: pedido.id,
      antes: {'produto': item.nome, 'quantidade': item.quantidade},
      depois: {'quantidade': nova},
    );
    semAguardar(batch.commit(), 'item do pedido ${pedido.codigo}');
  }

  void _mudarStatus(
    Pedido pedido,
    String status,
    String descricao, {
    Map<String, Object?> extra = const {},
  }) {
    final batch = _db.batch();
    batch.update(colecao.doc(pedido.id), {'status': status, ...extra});
    AuditoriaRepository.noBatch(
      batch,
      'delivery.status',
      descricao,
      entidade: 'pedido',
      entidadeId: pedido.id,
      antes: {'status': pedido.status},
      depois: {
        'status': status,
        for (final e in extra.entries)
          if (e.value is! FieldValue && e.value is! Timestamp) e.key: e.value,
      },
    );
    semAguardar(batch.commit(), 'pedido ${pedido.codigo}');
  }

  void iniciarPreparo(Pedido pedido) {
    if (pedido.status != Pedido.novo) {
      throw const RegraException('O pedido não está mais como novo.');
    }
    _mudarStatus(pedido, Pedido.preparo, 'Pedido em preparo');
  }

  static Map<String, Object?> _dadosMotoboy(Motoboy m) => {
    'motoboyId': m.id,
    // Só quem tem login no app vê o pedido no celular.
    'entregadorId': m.usuarioId,
    'entregador': {'motoboyId': m.id, 'uid': m.usuarioId, 'nome': m.nome},
  };

  /// Entrega o pedido a um motoboy. Se ele tem login no app, passa a ver o
  /// pedido no celular.
  void despachar(Pedido pedido, Motoboy motoboy) {
    if (!pedido.podeAlterarItens) {
      throw const RegraException('O pedido já saiu para entrega.');
    }
    if (!motoboy.ativo) {
      throw const RegraException('Este motoboy está desativado.');
    }
    _mudarStatus(
      pedido,
      Pedido.emRota,
      'Pedido saiu para entrega',
      extra: {..._dadosMotoboy(motoboy), 'saiuEm': Timestamp.now()},
    );
  }

  /// Troca o motoboy de um pedido em rota ou já entregue (ex.: escolhido
  /// errado). A entrega passa a contar para o novo motoboy.
  void trocarMotoboy(Pedido pedido, Motoboy motoboy) {
    if (pedido.status != Pedido.emRota && pedido.status != Pedido.entregue) {
      throw const RegraException(
        'Só é possível trocar o motoboy de um pedido em rota ou entregue.',
      );
    }
    _mudarStatus(
      pedido,
      pedido.status,
      'Motoboy do pedido trocado',
      extra: _dadosMotoboy(motoboy),
    );
  }

  /// Marca como entregue (pelo entregador ou pela loja). O pagamento é
  /// acertado depois, na conclusão.
  void marcarEntregue(Pedido pedido, {String local = ''}) {
    if (pedido.status != Pedido.emRota) {
      throw const RegraException('O pedido não está em rota.');
    }
    final l = local.length > 300 ? local.substring(0, 300) : local;
    _mudarStatus(
      pedido,
      Pedido.entregue,
      'Pedido entregue ao cliente',
      extra: {'entregueEm': Timestamp.now(), 'localEntrega': l},
    );
  }

  void confirmarPix(Pedido pedido, bool confirmado) {
    _exigirAtivo(pedido);
    if (!pedido.isPix) {
      throw const RegraException('Este pedido não é pago por Pix.');
    }
    final batch = _db.batch();
    batch.update(colecao.doc(pedido.id), {'pixConfirmado': confirmado});
    AuditoriaRepository.noBatch(
      batch,
      'delivery.pix',
      confirmado ? 'Pix do pedido confirmado' : 'Confirmação do Pix desfeita',
      entidade: 'pedido',
      entidadeId: pedido.id,
      depois: {'pixConfirmado': confirmado},
    );
    semAguardar(batch.commit(), 'Pix do pedido ${pedido.codigo}');
  }

  /// Guarda a imagem (JPEG em base64) do comprovante do Pix.
  void anexarComprovante(Pedido pedido, String imagemBase64) {
    _exigirAtivo(pedido);
    if (imagemBase64.length > 900000) {
      throw const RegraException(
        'A imagem do comprovante ficou grande demais.',
      );
    }
    final batch = _db.batch();
    batch.set(_comprovante(pedido.id), {
      'imagem': imagemBase64,
      'enviadoPor': Sessao.instancia.autor,
      'enviadoEm': Timestamp.now(),
    });
    batch.update(colecao.doc(pedido.id), {'temComprovante': true});
    AuditoriaRepository.noBatch(
      batch,
      'delivery.pix_receipt',
      'Comprovante do Pix anexado',
      entidade: 'pedido',
      entidadeId: pedido.id,
    );
    semAguardar(batch.commit(), 'comprovante do pedido ${pedido.codigo}');
  }

  void removerComprovante(Pedido pedido) {
    _exigirAtivo(pedido);
    final batch = _db.batch();
    batch.delete(_comprovante(pedido.id));
    batch.update(colecao.doc(pedido.id), {
      'temComprovante': false,
      'pixConfirmado': false,
    });
    AuditoriaRepository.noBatch(
      batch,
      'delivery.pix_receipt_remove',
      'Comprovante do Pix removido',
      entidade: 'pedido',
      entidadeId: pedido.id,
    );
    semAguardar(batch.commit(), 'comprovante do pedido ${pedido.codigo}');
  }

  /// Cancela o pedido e devolve os itens ao estoque.
  void cancelar(Pedido pedido, String motivo, Map<String, Produto> produtos) {
    _exigirAtivo(pedido);
    final m = motivo.trim();
    if (m.length < 5) {
      throw const RegraException(
        'Informe um motivo com pelo menos 5 caracteres.',
      );
    }
    final motivoFinal = m.length > 255 ? m.substring(0, 255) : m;
    final batch = _db.batch();
    for (final i in pedido.itens) {
      Estoque.movimentar(
        batch,
        produto:
            produtos[i.produtoId] ??
            Produto(id: i.produtoId, nome: i.nome, preco: i.precoUnitario),
        quantidade: i.quantidade,
        tipo: MovimentoEstoque.delivery,
        referenciaTipo: 'pedido',
        referenciaId: pedido.id,
        motivo: 'Cancelamento do pedido: $motivoFinal',
      );
    }
    batch.update(colecao.doc(pedido.id), {
      'status': Pedido.cancelado,
      'finalizadoEm': Timestamp.now(),
      'motivoCancelamento': motivoFinal,
      'canceladoPor': Sessao.instancia.autor,
    });
    AuditoriaRepository.noBatch(
      batch,
      'delivery.cancel',
      'Pedido de delivery cancelado',
      entidade: 'pedido',
      entidadeId: pedido.id,
      antes: {
        'status': pedido.status,
        'cliente': pedido.clienteNome,
        'itens': [
          for (final i in pedido.itens)
            {'produto': i.nome, 'quantidade': i.quantidade},
        ],
      },
      depois: {'motivo': motivoFinal},
    );
    semAguardar(batch.commit(), 'cancelamento do pedido ${pedido.codigo}');
  }
}
