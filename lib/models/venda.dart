import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';
import '../core/regra_exception.dart';

class FormaPagamento {
  static const pix = 'Pix';
  static const dinheiro = 'Dinheiro';
  static const debito = 'Débito';
  static const credito = 'Crédito';
  static const vr = 'VR';

  /// Usada automaticamente quando o total da venda é zero (desconto de 100%).
  static const cortesia = 'Cortesia';

  static const todas = [pix, dinheiro, debito, credito, vr];
  static const maxParcelas = 24;
}

class ItemVenda {
  final String produtoId;
  final String nome;
  final int quantidade;
  final double precoUnitario;

  /// Custo do produto no momento da venda (para o relatório de lucro).
  final double custoUnitario;

  const ItemVenda({
    required this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
    this.custoUnitario = 0,
  });

  int get totalCentavos => centavos(precoUnitario) * quantidade;
  double get subtotal => deCentavos(totalCentavos);
  double get custoTotal => custoUnitario * quantidade;

  ItemVenda copyWith({int? quantidade, double? precoUnitario}) => ItemVenda(
        produtoId: produtoId,
        nome: nome,
        quantidade: quantidade ?? this.quantidade,
        precoUnitario: precoUnitario ?? this.precoUnitario,
        custoUnitario: custoUnitario,
      );

  factory ItemVenda.fromMap(Map<String, dynamic> m) => ItemVenda(
        produtoId: m['produtoId'] as String? ?? '',
        nome: m['nome'] as String? ?? '',
        quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
        precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
        custoUnitario: (m['custoUnitario'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'produtoId': produtoId,
        'nome': nome,
        'quantidade': quantidade,
        'precoUnitario': precoUnitario,
        'custoUnitario': custoUnitario,
        'total': subtotal,
      };
}

class Pagamento {
  final String forma;
  final double valor;
  final int parcelas;

  /// Valor entregue pelo cliente (só em dinheiro; nas outras = valor).
  final double recebido;
  final double troco;

  const Pagamento({
    required this.forma,
    required this.valor,
    this.parcelas = 1,
    double? recebido,
    this.troco = 0,
  }) : recebido = recebido ?? valor;

  String get descricao =>
      forma == FormaPagamento.credito && parcelas > 1 ? '$forma ${parcelas}x' : forma;

  factory Pagamento.fromMap(Map<String, dynamic> m) => Pagamento(
        forma: m['forma'] as String? ?? '',
        valor: (m['valor'] as num?)?.toDouble() ?? 0,
        parcelas: (m['parcelas'] as num?)?.toInt() ?? 1,
        recebido: (m['recebido'] as num?)?.toDouble(),
        troco: (m['troco'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'forma': forma,
        'valor': valor,
        'parcelas': parcelas,
        'recebido': recebido,
        'troco': troco,
      };
}

/// Valida e normaliza as formas de pagamento, como no sistema original:
/// linhas com valor zero são ignoradas, crédito aceita 1 a 24 parcelas,
/// dinheiro calcula o troco e a soma precisa fechar exatamente com o total.
/// Total zero vira uma única linha "Cortesia".
List<Pagamento> processarPagamentos(List<Pagamento> linhas, int totalCentavos) {
  if (totalCentavos == 0) {
    return const [Pagamento(forma: FormaPagamento.cortesia, valor: 0)];
  }
  final resultado = <Pagamento>[];
  var soma = 0;
  for (final l in linhas) {
    final valor = centavos(l.valor);
    if (valor <= 0) continue;
    if (!FormaPagamento.todas.contains(l.forma)) {
      throw const RegraException('Forma de pagamento inválida.');
    }
    final parcelas = l.forma == FormaPagamento.credito
        ? l.parcelas.clamp(1, FormaPagamento.maxParcelas)
        : 1;
    final dinheiro = l.forma == FormaPagamento.dinheiro;
    final recebido = dinheiro ? centavos(l.recebido) : valor;
    if (dinheiro && recebido < valor) {
      throw const RegraException(
          'O valor recebido em dinheiro é menor que a parte informada.');
    }
    resultado.add(Pagamento(
      forma: l.forma,
      valor: deCentavos(valor),
      parcelas: parcelas,
      recebido: deCentavos(recebido),
      troco: dinheiro ? deCentavos(recebido - valor) : 0,
    ));
    soma += valor;
  }
  if (resultado.isEmpty || soma != totalCentavos) {
    throw const RegraException(
        'A soma dos pagamentos deve ser igual ao total da venda.');
  }
  return resultado;
}

/// Desconto em centavos, limitado ao subtotal.
int calcularDesconto(int subtotalCentavos, bool percentual, double informado) {
  final v = informado < 0 ? 0.0 : informado;
  final d = percentual
      ? (subtotalCentavos * (v > 100 ? 100 : v) / 100).round()
      : centavos(v);
  return d > subtotalCentavos ? subtotalCentavos : d;
}

class Venda {
  static const concluida = 'concluida';
  static const cancelada = 'cancelada';

  final String id;
  final String? clienteId;
  final String? clienteNome;
  final List<ItemVenda> itens;
  final List<Pagamento> pagamentos;
  final bool descontoPercentual;
  final double descontoInformado;
  final double desconto;

  /// Primeira forma de pagamento (ou a única, nas vendas antigas).
  final String formaPagamento;
  final String status;
  final String? caixaId;
  final String? comandaId;
  final String? comandaNome;
  final String vendedorId;
  final String vendedorNome;

  /// Data do dispositivo no momento da venda (funciona offline, ao contrário
  /// do serverTimestamp, que só é preenchido depois de sincronizar).
  final DateTime data;
  final DateTime? canceladaEm;
  final String? canceladaPorNome;
  final String? motivoCancelamento;

  /// Texto completo editado do comprovante; quando existe, é impresso no
  /// lugar do layout padrão.
  final String? textoComprovante;
  final bool pendente;

  const Venda({
    this.id = '',
    this.clienteId,
    this.clienteNome,
    required this.itens,
    this.pagamentos = const [],
    this.descontoPercentual = false,
    this.descontoInformado = 0,
    this.desconto = 0,
    required this.formaPagamento,
    this.status = concluida,
    this.caixaId,
    this.comandaId,
    this.comandaNome,
    this.vendedorId = '',
    this.vendedorNome = '',
    required this.data,
    this.canceladaEm,
    this.canceladaPorNome,
    this.motivoCancelamento,
    this.textoComprovante,
    this.pendente = false,
  });

  int get subtotalCentavos => itens.fold(0, (s, i) => s + i.totalCentavos);
  double get subtotal => deCentavos(subtotalCentavos);
  double get total => deCentavos(subtotalCentavos - centavos(desconto));
  double get custoTotal => itens.fold(0, (s, i) => s + i.custoTotal);
  double get troco => pagamentos.fold(0, (s, p) => s + p.troco);
  bool get isCancelada => status == cancelada;

  /// Parte da venda paga em dinheiro (já descontado o troco): é o que entra
  /// na gaveta do caixa.
  double get valorEmDinheiro {
    final d = pagamentos
        .where((p) => p.forma == FormaPagamento.dinheiro)
        .fold<double>(0, (s, p) => s + p.valor);
    if (d == 0 && pagamentos.isEmpty && formaPagamento == FormaPagamento.dinheiro) {
      return total;
    }
    return d;
  }

  String get pagamentoResumo =>
      pagamentos.length > 1 ? 'Dividido' : formaPagamento;

  /// Código curto para exibir (os ids do Firestore são longos).
  String get codigo => id.length > 6 ? id.substring(0, 6).toUpperCase() : id;

  factory Venda.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final vendedor = d['vendedor'] as Map?;
    final cancelamento = d['cancelamento'] as Map?;
    return Venda(
      id: doc.id,
      clienteId: d['clienteId'] as String?,
      clienteNome: d['clienteNome'] as String?,
      itens: (d['itens'] as List? ?? const [])
          .map((e) => ItemVenda.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      pagamentos: (d['pagamentos'] as List? ?? const [])
          .map((e) => Pagamento.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      descontoPercentual: d['descontoPercentual'] as bool? ?? false,
      descontoInformado: (d['descontoInformado'] as num?)?.toDouble() ?? 0,
      desconto: (d['desconto'] as num?)?.toDouble() ?? 0,
      formaPagamento: d['formaPagamento'] as String? ?? '',
      status: d['status'] as String? ?? concluida,
      caixaId: d['caixaId'] as String?,
      comandaId: d['comandaId'] as String?,
      comandaNome: d['comandaNome'] as String?,
      vendedorId: vendedor?['uid'] as String? ?? '',
      vendedorNome: vendedor?['nome'] as String? ??
          d['vendedorEmail'] as String? ??
          '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      canceladaEm: (cancelamento?['em'] as Timestamp?)?.toDate(),
      canceladaPorNome: (cancelamento?['por'] as Map?)?['nome'] as String?,
      motivoCancelamento: cancelamento?['motivo'] as String?,
      textoComprovante: d['textoComprovante'] as String?,
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  Map<String, dynamic> toMap() => {
        'clienteId': clienteId,
        'clienteNome': clienteNome,
        'itens': itens.map((i) => i.toMap()).toList(),
        'pagamentos': pagamentos.map((p) => p.toMap()).toList(),
        'descontoPercentual': descontoPercentual,
        'descontoInformado': descontoInformado,
        'desconto': desconto,
        'subtotal': subtotal,
        'total': total,
        'custoTotal': custoTotal,
        'formaPagamento': formaPagamento,
        'status': status,
        'caixaId': caixaId,
        'comandaId': comandaId,
        'comandaNome': comandaNome,
        'vendedor': {'uid': vendedorId, 'nome': vendedorNome},
        'data': Timestamp.fromDate(data),
      };
}
