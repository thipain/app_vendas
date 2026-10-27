import 'package:cloud_firestore/cloud_firestore.dart';

class ItemRetirada {
  final String produtoId;
  final String produtoNome;
  final int quantidade;
  final double custoUnitario;
  final double precoUnitario;

  const ItemRetirada({
    required this.produtoId,
    required this.produtoNome,
    required this.quantidade,
    required this.custoUnitario,
    required this.precoUnitario,
  });

  double get totalVenda => quantidade * precoUnitario;
  double get totalCusto => quantidade * custoUnitario;

  factory ItemRetirada.fromMap(Map<String, dynamic> m) => ItemRetirada(
        produtoId: m['produtoId'] as String? ?? '',
        produtoNome: m['produtoNome'] as String? ?? '',
        quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
        custoUnitario: (m['custoUnitario'] as num?)?.toDouble() ?? 0,
        precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'produtoId': produtoId,
        'produtoNome': produtoNome,
        'quantidade': quantidade,
        'custoUnitario': custoUnitario,
        'precoUnitario': precoUnitario,
      };
}

/// Consumo de produtos por funcionário: baixa o estoque sem passar pelo caixa.
class Retirada {
  static const ativa = 'ativa';
  static const cancelada = 'cancelada';

  final String id;
  final String funcionarioId;
  final String funcionarioNome;
  final String registradoPorNome;
  final String observacao;
  final List<ItemRetirada> itens;
  final double totalCusto;
  final double totalVenda;
  final String status;
  final DateTime data;
  final DateTime? canceladaEm;
  final String? canceladaPorNome;
  final String? motivoCancelamento;
  final bool pendente;

  const Retirada({
    required this.id,
    required this.funcionarioId,
    required this.funcionarioNome,
    required this.registradoPorNome,
    this.observacao = '',
    required this.itens,
    required this.totalCusto,
    required this.totalVenda,
    required this.status,
    required this.data,
    this.canceladaEm,
    this.canceladaPorNome,
    this.motivoCancelamento,
    this.pendente = false,
  });

  bool get isAtiva => status == ativa;
  int get unidades => itens.fold(0, (s, i) => s + i.quantidade);
  String get codigo => id.length > 6 ? id.substring(0, 6).toUpperCase() : id;

  factory Retirada.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final func = d['funcionario'] as Map?;
    final canc = d['cancelamento'] as Map?;
    return Retirada(
      id: doc.id,
      funcionarioId: func?['uid'] as String? ?? '',
      funcionarioNome: func?['nome'] as String? ?? '',
      registradoPorNome: (d['registradoPor'] as Map?)?['nome'] as String? ?? '',
      observacao: d['observacao'] as String? ?? '',
      itens: (d['itens'] as List? ?? const [])
          .map((e) => ItemRetirada.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      totalCusto: (d['totalCusto'] as num?)?.toDouble() ?? 0,
      totalVenda: (d['totalVenda'] as num?)?.toDouble() ?? 0,
      status: d['status'] as String? ?? ativa,
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      canceladaEm: (canc?['em'] as Timestamp?)?.toDate(),
      canceladaPorNome: (canc?['por'] as Map?)?['nome'] as String?,
      motivoCancelamento: canc?['motivo'] as String?,
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}
