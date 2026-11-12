import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';
import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/pedido.dart';
import '../models/pedido_online.dart';
import '../models/produto.dart';
import 'auditoria_repository.dart';
import 'offline.dart';
import 'pedido_repository.dart';
import 'venda_repository.dart';

/// Diferença entre o que o cliente pediu e o que a loja pode aceitar agora.
class ConferenciaPedidoOnline {
  final List<ItemCarrinho> carrinho;

  /// Itens que não podem ser atendidos (produto removido ou sem estoque).
  final List<String> problemas;

  /// Itens cujo preço mudou desde que o cliente montou o pedido.
  final List<String> precosAlterados;
  final int subtotalCentavos;

  const ConferenciaPedidoOnline({
    required this.carrinho,
    required this.problemas,
    required this.precosAlterados,
    required this.subtotalCentavos,
  });
}

class PedidoOnlineRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => PedidoRepository.online;

  Stream<List<PedidoOnline>> watchAguardando() => _col
      .where('status', isEqualTo: PedidoOnline.aguardando)
      .snapshots()
      .map(
        (s) =>
            s.docs.map(PedidoOnline.fromDoc).toList()
              ..sort((a, b) => a.criadoEm.compareTo(b.criadoEm)),
      );

  /// Comprovante do Pix enviado pelo cliente (base64), ou null.
  Future<String?> lerComprovante(String id) async {
    final d = await _col.doc(id).collection('anexos').doc('comprovante').get();
    return d.data()?['imagem'] as String?;
  }

  /// Confere os itens com o cadastro atual: preço de agora e estoque.
  static ConferenciaPedidoOnline conferir(
    PedidoOnline po,
    Map<String, Produto> produtos,
  ) {
    final carrinho = <ItemCarrinho>[];
    final problemas = <String>[];
    final precos = <String>[];
    var subtotal = 0;
    for (final i in po.itens) {
      final p = produtos[i.produtoId];
      if (i.quantidade <= 0) continue;
      if (p == null || !p.ativo) {
        problemas.add('${i.nome}: não está mais à venda');
        continue;
      }
      if (i.quantidade > p.estoque) {
        problemas.add(
          '${p.nome}: pediu ${i.quantidade}, há ${p.estoque} em estoque',
        );
        continue;
      }
      if (centavos(p.preco) != centavos(i.precoUnitario)) {
        precos.add(
          '${p.nome}: R\$ ${i.precoUnitario.toStringAsFixed(2)} → '
          'R\$ ${p.preco.toStringAsFixed(2)}',
        );
      }
      carrinho.add(ItemCarrinho(p, i.quantidade));
      subtotal += centavos(p.preco) * i.quantidade;
    }
    return ConferenciaPedidoOnline(
      carrinho: carrinho,
      problemas: problemas,
      precosAlterados: precos,
      subtotalCentavos: subtotal,
    );
  }

  /// Aceita o pedido: vira um pedido de delivery (estoque sai agora, com os
  /// preços atuais) e o cliente passa a ver "Pedido aceito". Retorna o id do
  /// pedido de delivery.
  String aceitar(
    PedidoOnline po,
    Map<String, Produto> produtos, {
    String? comprovantePix,
  }) {
    if (po.status != PedidoOnline.aguardando) {
      throw const RegraException('Este pedido já foi respondido.');
    }
    if (po.isPix && (comprovantePix ?? '').isEmpty) {
      throw const RegraException(
        'O comprovante do Pix ainda não carregou. Verifique a internet.',
      );
    }
    final c = conferir(po, produtos);
    if (c.problemas.isNotEmpty) {
      throw RegraException(
        'Não dá para aceitar como está:\n${c.problemas.join('\n')}\n'
        'Fale com o cliente e recuse o pedido, se for o caso.',
      );
    }
    final referencia = [
      po.referencia,
      if (po.cep.isNotEmpty) 'CEP ${po.cep}',
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    final total = c.subtotalCentavos + centavos(po.taxaEntrega);
    final troco = po.trocoPara;
    return PedidoRepository().criar(
      DadosPedido(
        clienteNome: po.clienteNome,
        telefone: po.telefone,
        endereco: po.endereco,
        bairro: po.bairro,
        referencia: referencia.length > 200
            ? referencia.substring(0, 200)
            : referencia,
        observacao: po.observacao,
        taxaEntrega: po.taxaEntrega,
        formaPagamento: po.formaPagamento,
        // Se o preço subiu e a nota não cobre mais, o troco é acertado na
        // entrega.
        trocoPara: troco != null && centavos(troco) >= total ? troco : null,
      ),
      c.carrinho,
      pedidoOnlineId: po.id,
      comprovantePix: comprovantePix,
    );
  }

  /// Recusa o pedido com um motivo que o cliente vê na página.
  void recusar(PedidoOnline po, String motivo) {
    if (po.status != PedidoOnline.aguardando) {
      throw const RegraException('Este pedido já foi respondido.');
    }
    final m = motivo.trim();
    if (m.length < 3) {
      throw const RegraException('Informe o motivo para o cliente.');
    }
    final motivoFinal = m.length > 255 ? m.substring(0, 255) : m;
    final batch = _db.batch();
    batch.update(_col.doc(po.id), {
      'status': PedidoOnline.recusado,
      'motivo': motivoFinal,
      'recusadoPor': Sessao.instancia.autor,
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    AuditoriaRepository.noBatch(
      batch,
      'online.refuse',
      'Pedido online recusado',
      entidade: 'pedidoOnline',
      entidadeId: po.id,
      depois: {
        'cliente': po.clienteNome,
        'total': po.total,
        'motivo': motivoFinal,
      },
    );
    semAguardar(batch.commit(), 'recusa do pedido online ${po.codigo}');
  }
}
