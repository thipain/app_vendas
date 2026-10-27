import 'package:cloud_firestore/cloud_firestore.dart';

const formasPagamento = [
  'Dinheiro',
  'Pix',
  'Cartão de crédito',
  'Cartão de débito',
  'Fiado',
];

class ItemVenda {
  final String produtoId;
  final String nome;
  final int quantidade;
  final double precoUnitario;

  const ItemVenda({
    required this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
  });

  double get subtotal => quantidade * precoUnitario;

  ItemVenda copyWith({int? quantidade}) => ItemVenda(
        produtoId: produtoId,
        nome: nome,
        quantidade: quantidade ?? this.quantidade,
        precoUnitario: precoUnitario,
      );

  factory ItemVenda.fromMap(Map<String, dynamic> m) => ItemVenda(
        produtoId: m['produtoId'] as String? ?? '',
        nome: m['nome'] as String? ?? '',
        quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
        precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'produtoId': produtoId,
        'nome': nome,
        'quantidade': quantidade,
        'precoUnitario': precoUnitario,
      };
}

class Venda {
  static const concluida = 'concluida';
  static const cancelada = 'cancelada';

  final String id;
  final String? clienteId;
  final String? clienteNome;
  final List<ItemVenda> itens;
  final double desconto;
  final String formaPagamento;
  final String status;
  final String vendedorEmail;

  /// Data do dispositivo no momento da venda (funciona offline, ao contrário
  /// do serverTimestamp, que só é preenchido depois de sincronizar).
  final DateTime data;
  final bool pendente;

  const Venda({
    this.id = '',
    this.clienteId,
    this.clienteNome,
    required this.itens,
    this.desconto = 0,
    required this.formaPagamento,
    this.status = concluida,
    this.vendedorEmail = '',
    required this.data,
    this.pendente = false,
  });

  double get subtotal => itens.fold(0, (soma, i) => soma + i.subtotal);
  double get total => subtotal - desconto;
  bool get isCancelada => status == cancelada;

  factory Venda.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Venda(
      id: doc.id,
      clienteId: d['clienteId'] as String?,
      clienteNome: d['clienteNome'] as String?,
      itens: (d['itens'] as List? ?? const [])
          .map((e) => ItemVenda.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      desconto: (d['desconto'] as num?)?.toDouble() ?? 0,
      formaPagamento: d['formaPagamento'] as String? ?? '',
      status: d['status'] as String? ?? concluida,
      vendedorEmail: d['vendedorEmail'] as String? ?? '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  Map<String, dynamic> toMap() => {
        'clienteId': clienteId,
        'clienteNome': clienteNome,
        'itens': itens.map((i) => i.toMap()).toList(),
        'desconto': desconto,
        'subtotal': subtotal,
        'total': total,
        'formaPagamento': formaPagamento,
        'status': status,
        'vendedorEmail': vendedorEmail,
        'data': Timestamp.fromDate(data),
      };
}
