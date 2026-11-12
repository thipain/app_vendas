import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';

/// Item como o cliente viu na loja online (o preço é conferido de novo ao
/// aceitar).
class ItemPedidoOnline {
  final String produtoId;
  final String nome;
  final int quantidade;
  final double precoUnitario;

  const ItemPedidoOnline({
    required this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
  });

  factory ItemPedidoOnline.fromMap(Map<String, dynamic> m) => ItemPedidoOnline(
    produtoId: m['produtoId'] as String? ?? '',
    nome: m['nome'] as String? ?? '',
    quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
    precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
  );
}

/// Pedido enviado pelo cliente na loja online
/// (`lojas/{loja}/pedidosOnline/{id}`). Fica "aguardando" até a loja aceitar
/// (vira um pedido de delivery normal) ou recusar. Depois de aceito, o
/// status acompanha o do pedido, para o cliente ver na página.
class PedidoOnline {
  static const aguardando = 'aguardando';
  static const recusado = 'recusado';

  final String id;
  final String status;
  final String clienteNome;
  final String telefone;
  final String cep;
  final String endereco;
  final String bairro;
  final String referencia;
  final String observacao;
  final List<ItemPedidoOnline> itens;
  final double subtotal;
  final double taxaEntrega;
  final double total;
  final String formaPagamento;
  final double? trocoPara;
  final bool temComprovante;
  final DateTime criadoEm;
  final String? pedidoId;
  final String? motivo;

  const PedidoOnline({
    required this.id,
    required this.status,
    required this.clienteNome,
    this.telefone = '',
    this.cep = '',
    required this.endereco,
    this.bairro = '',
    this.referencia = '',
    this.observacao = '',
    this.itens = const [],
    this.subtotal = 0,
    this.taxaEntrega = 0,
    this.total = 0,
    required this.formaPagamento,
    this.trocoPara,
    this.temComprovante = false,
    required this.criadoEm,
    this.pedidoId,
    this.motivo,
  });

  String get codigo => id.length > 6 ? id.substring(0, 6).toUpperCase() : id;
  int get quantidadeItens => itens.fold(0, (s, i) => s + i.quantidade);
  bool get isPix => formaPagamento == 'Pix';

  /// Subtotal recalculado pelos itens (o que o cliente viu).
  int get subtotalCentavos =>
      itens.fold(0, (s, i) => s + centavos(i.precoUnitario) * i.quantidade);

  factory PedidoOnline.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    double n(String k) => (d[k] as num?)?.toDouble() ?? 0;
    String s(String k) => d[k] as String? ?? '';
    return PedidoOnline(
      id: doc.id,
      status: s('status').isEmpty ? aguardando : s('status'),
      clienteNome: s('clienteNome'),
      telefone: s('telefone'),
      cep: s('cep'),
      endereco: s('endereco'),
      bairro: s('bairro'),
      referencia: s('referencia'),
      observacao: s('observacao'),
      itens: (d['itens'] as List? ?? const [])
          .map(
            (e) =>
                ItemPedidoOnline.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      subtotal: n('subtotal'),
      taxaEntrega: n('taxaEntrega'),
      total: n('total'),
      formaPagamento: s('formaPagamento'),
      trocoPara: (d['trocoPara'] as num?)?.toDouble(),
      temComprovante: d['temComprovante'] as bool? ?? false,
      // Sem o horário do servidor ainda (acabou de chegar): agora.
      criadoEm: (d['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pedidoId: d['pedidoId'] as String?,
      motivo: d['motivo'] as String?,
    );
  }
}
