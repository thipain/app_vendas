import 'package:cloud_firestore/cloud_firestore.dart';

class ItemNotaEntrada {
  final String produtoId;
  final String produtoNome;
  final int quantidade;
  final double custoUnitario;

  const ItemNotaEntrada({
    required this.produtoId,
    required this.produtoNome,
    required this.quantidade,
    required this.custoUnitario,
  });

  double get custoTotal =>
      (quantidade * custoUnitario * 100).roundToDouble() / 100;

  factory ItemNotaEntrada.fromMap(Map<String, dynamic> m) => ItemNotaEntrada(
    produtoId: m['produtoId'] as String? ?? '',
    produtoNome: m['produtoNome'] as String? ?? '',
    quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
    custoUnitario: (m['custoUnitario'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'produtoId': produtoId,
    'produtoNome': produtoNome,
    'quantidade': quantidade,
    'custoUnitario': custoUnitario,
    'custoTotal': custoTotal,
  };
}

/// Nota de entrada de mercadorias (controle interno, não é NF-e).
class NotaEntrada {
  final String id;
  final DateTime dataEntrada;
  final String numero;
  final String fornecedor;

  /// Valor total da nota; quando não informado, é a soma dos itens.
  final double total;
  final String observacao;
  final List<ItemNotaEntrada> itens;
  final String criadoPorNome;
  final String? editadoPorNome;
  final DateTime criadoEm;
  final DateTime? editadoEm;
  final bool pendente;

  const NotaEntrada({
    this.id = '',
    required this.dataEntrada,
    this.numero = '',
    this.fornecedor = '',
    required this.total,
    this.observacao = '',
    required this.itens,
    this.criadoPorNome = '',
    this.editadoPorNome,
    required this.criadoEm,
    this.editadoEm,
    this.pendente = false,
  });

  double get somaItens => itens.fold(0, (s, i) => s + i.custoTotal);
  int get quantidadeTotal => itens.fold(0, (s, i) => s + i.quantidade);

  factory NotaEntrada.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return NotaEntrada(
      id: doc.id,
      dataEntrada: (d['dataEntrada'] as Timestamp?)?.toDate() ?? DateTime.now(),
      numero: d['numero'] as String? ?? '',
      fornecedor: d['fornecedor'] as String? ?? '',
      total: (d['total'] as num?)?.toDouble() ?? 0,
      observacao: d['observacao'] as String? ?? '',
      itens: (d['itens'] as List? ?? const [])
          .map(
            (e) => ItemNotaEntrada.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      criadoPorNome: (d['criadoPor'] as Map?)?['nome'] as String? ?? '',
      editadoPorNome: (d['editadoPor'] as Map?)?['nome'] as String?,
      criadoEm: (d['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
      editadoEm: (d['editadoEm'] as Timestamp?)?.toDate(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}
