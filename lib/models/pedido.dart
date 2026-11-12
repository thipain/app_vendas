import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';
import 'comanda.dart';
import 'venda.dart';

/// Pedido de delivery.
///
/// Como na comanda, os itens saem do estoque quando entram no pedido e voltam
/// se ele for cancelado. A venda só é gerada na conclusão, quando a loja
/// recebe o pagamento (acerto com o entregador), e por isso a conclusão exige
/// caixa aberto.
///
/// Fluxo: novo → em preparo → em rota (com entregador) → entregue →
/// concluído. Pode ser cancelado em qualquer etapa antes da conclusão.
class Pedido {
  static const novo = 'novo';
  static const preparo = 'preparo';
  static const emRota = 'em_rota';
  static const entregue = 'entregue';
  static const concluido = 'concluido';
  static const cancelado = 'cancelado';

  /// Etapas que aparecem no painel (ainda não concluídas nem canceladas).
  static const ativos = [novo, preparo, emRota, entregue];

  static const nomes = {
    novo: 'Novo',
    preparo: 'Em preparo',
    emRota: 'Saiu para entrega',
    entregue: 'Entregue',
    concluido: 'Concluído',
    cancelado: 'Cancelado',
  };

  final String id;
  final String status;

  /// Cliente: cadastro opcional; nome, telefone e endereço ficam no pedido.
  final String? clienteId;
  final String clienteNome;
  final String telefone;

  /// Rua e número.
  final String endereco;
  final String bairro;

  /// Complemento e ponto de referência.
  final String referencia;
  final String observacao;

  final List<ItemComanda> itens;
  final double taxaEntrega;

  /// Desconto do cupom (valor em R$, já calculado sobre os produtos).
  final double desconto;
  final String? cupom;

  /// Forma combinada com o cliente (Pix, Dinheiro, Débito, Crédito, VR).
  final String formaPagamento;

  /// Dinheiro: valor da nota que o cliente vai usar (null = sem troco).
  final double? trocoPara;
  final bool pixConfirmado;
  final bool temComprovante;

  /// Motoboy cadastrado que levou o pedido (conta nas entregas do dia).
  final String? motoboyId;

  /// Login do motoboy no app, quando ele tem (vê o pedido no celular).
  final String? entregadorId;
  final String entregadorNome;

  final String criadoPorNome;
  final DateTime criadoEm;
  final DateTime? saiuEm;
  final DateTime? entregueEm;
  final DateTime? finalizadoEm;

  /// Endereço ou coordenada obtidos pelo celular do entregador na entrega.
  final String localEntrega;
  final String? vendaId;

  /// Pedido feito pelo cliente na loja online que originou este (o status
  /// é copiado para lá, para o cliente acompanhar).
  final String? pedidoOnlineId;
  final String? motivoCancelamento;
  final bool pendente;

  const Pedido({
    required this.id,
    required this.status,
    this.clienteId,
    required this.clienteNome,
    this.telefone = '',
    required this.endereco,
    this.bairro = '',
    this.referencia = '',
    this.observacao = '',
    this.itens = const [],
    this.taxaEntrega = 0,
    this.desconto = 0,
    this.cupom,
    required this.formaPagamento,
    this.trocoPara,
    this.pixConfirmado = false,
    this.temComprovante = false,
    this.motoboyId,
    this.entregadorId,
    this.entregadorNome = '',
    this.criadoPorNome = '',
    required this.criadoEm,
    this.saiuEm,
    this.entregueEm,
    this.finalizadoEm,
    this.localEntrega = '',
    this.vendaId,
    this.pedidoOnlineId,
    this.motivoCancelamento,
    this.pendente = false,
  });

  String get statusNome => nomes[status] ?? status;
  String get codigo => id.length > 6 ? id.substring(0, 6).toUpperCase() : id;

  bool get isAtivo => ativos.contains(status);

  /// Itens só mudam antes de o pedido sair para entrega.
  bool get podeAlterarItens => status == novo || status == preparo;

  bool get isPix => formaPagamento == FormaPagamento.pix;
  bool get isDinheiro => formaPagamento == FormaPagamento.dinheiro;
  bool get isCartao =>
      formaPagamento == FormaPagamento.debito ||
      formaPagamento == FormaPagamento.credito ||
      formaPagamento == FormaPagamento.vr;

  int get quantidadeItens => itens.fold(0, (s, i) => s + i.quantidade);
  int get subtotalCentavos => itens.fold(0, (s, i) => s + i.totalCentavos);
  int get descontoCentavos {
    final d = centavos(desconto);
    return d > subtotalCentavos ? subtotalCentavos : (d < 0 ? 0 : d);
  }

  int get totalCentavos =>
      subtotalCentavos - descontoCentavos + centavos(taxaEntrega);
  double get subtotal => deCentavos(subtotalCentavos);
  double get total => deCentavos(totalCentavos);

  /// Troco que o entregador deve levar (0 quando não precisa).
  double get troco {
    final t = trocoPara;
    if (!isDinheiro || t == null) return 0;
    final c = centavos(t) - totalCentavos;
    return c > 0 ? deCentavos(c) : 0;
  }

  /// Endereço numa linha (para mapa, impressão e mensagens).
  String get enderecoCompleto =>
      [endereco.trim(), bairro.trim()].where((s) => s.isNotEmpty).join(' - ');

  /// Resumo do que o entregador precisa saber sobre o pagamento.
  String get instrucaoPagamento {
    if (isPix) {
      return pixConfirmado
          ? 'PIX já pago — não cobrar'
          : 'PIX — pagamento ainda não confirmado pela loja';
    }
    if (isDinheiro) {
      return troco > 0
          ? 'Cobrar em DINHEIRO — levar troco de ${_moeda(troco)} '
                '(cliente paga com ${_moeda(trocoPara!)})'
          : 'Cobrar em DINHEIRO — sem troco';
    }
    if (isCartao) return 'LEVAR MAQUININHA — $formaPagamento';
    return formaPagamento;
  }

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  factory Pedido.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final entregador = d['entregador'] as Map?;
    DateTime? data(String k) => (d[k] as Timestamp?)?.toDate();
    return Pedido(
      id: doc.id,
      status: d['status'] as String? ?? novo,
      clienteId: d['clienteId'] as String?,
      clienteNome: d['clienteNome'] as String? ?? '',
      telefone: d['telefone'] as String? ?? '',
      endereco: d['endereco'] as String? ?? '',
      bairro: d['bairro'] as String? ?? '',
      referencia: d['referencia'] as String? ?? '',
      observacao: d['observacao'] as String? ?? '',
      itens: ItemComanda.doMapa(d['itens'] as Map?),
      taxaEntrega: (d['taxaEntrega'] as num?)?.toDouble() ?? 0,
      desconto: (d['desconto'] as num?)?.toDouble() ?? 0,
      cupom: d['cupom'] as String?,
      formaPagamento: d['formaPagamento'] as String? ?? '',
      trocoPara: (d['trocoPara'] as num?)?.toDouble(),
      pixConfirmado: d['pixConfirmado'] as bool? ?? false,
      temComprovante: d['temComprovante'] as bool? ?? false,
      motoboyId: d['motoboyId'] as String?,
      entregadorId: d['entregadorId'] as String?,
      entregadorNome: entregador?['nome'] as String? ?? '',
      criadoPorNome: (d['criadoPor'] as Map?)?['nome'] as String? ?? '',
      criadoEm: data('criadoEm') ?? DateTime.now(),
      saiuEm: data('saiuEm'),
      entregueEm: data('entregueEm'),
      finalizadoEm: data('finalizadoEm'),
      localEntrega: d['localEntrega'] as String? ?? '',
      vendaId: d['vendaId'] as String?,
      pedidoOnlineId: d['pedidoOnlineId'] as String?,
      motivoCancelamento: d['motivoCancelamento'] as String?,
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}

/// Dados do cliente, do endereço e do pagamento (tudo menos os itens),
/// usados para criar e para editar um pedido.
class DadosPedido {
  final String? clienteId;
  final String clienteNome;
  final String telefone;
  final String endereco;
  final String bairro;
  final String referencia;
  final String observacao;
  final double taxaEntrega;
  final String formaPagamento;
  final double? trocoPara;

  const DadosPedido({
    this.clienteId,
    required this.clienteNome,
    required this.telefone,
    required this.endereco,
    this.bairro = '',
    this.referencia = '',
    this.observacao = '',
    this.taxaEntrega = 0,
    required this.formaPagamento,
    this.trocoPara,
  });

  factory DadosPedido.de(Pedido p) => DadosPedido(
    clienteId: p.clienteId,
    clienteNome: p.clienteNome,
    telefone: p.telefone,
    endereco: p.endereco,
    bairro: p.bairro,
    referencia: p.referencia,
    observacao: p.observacao,
    taxaEntrega: p.taxaEntrega,
    formaPagamento: p.formaPagamento,
    trocoPara: p.trocoPara,
  );

  Map<String, Object?> toMap() => {
    'clienteId': clienteId,
    'clienteNome': clienteNome,
    'telefone': telefone,
    'endereco': endereco,
    'bairro': bairro,
    'referencia': referencia,
    'observacao': observacao,
    'taxaEntrega': taxaEntrega,
    'formaPagamento': formaPagamento,
    'trocoPara': formaPagamento == FormaPagamento.dinheiro ? trocoPara : null,
  };
}
