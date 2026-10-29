import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';

class ItemComanda {
  final String produtoId;
  final String nome;
  final String codigo;
  final int quantidade;
  final double precoUnitario;
  final DateTime adicionadoEm;

  const ItemComanda({
    required this.produtoId,
    required this.nome,
    this.codigo = '',
    required this.quantidade,
    required this.precoUnitario,
    required this.adicionadoEm,
  });

  int get totalCentavos => centavos(precoUnitario) * quantidade;
  double get total => deCentavos(totalCentavos);
}

/// Comanda aberta: os itens já saem do estoque quando são lançados; o
/// pagamento e a venda acontecem só no fechamento.
class Comanda {
  static const aberta = 'aberta';
  static const fechada = 'fechada';
  static const cancelada = 'cancelada';

  final String id;
  final String nome;
  final int pessoas;
  final String status;
  final String abertaPorNome;
  final DateTime abertaEm;
  final DateTime? fechadaEm;
  final String? vendaId;
  final List<ItemComanda> itens;
  final bool pendente;

  const Comanda({
    required this.id,
    required this.nome,
    this.pessoas = 1,
    required this.status,
    this.abertaPorNome = '',
    required this.abertaEm,
    this.fechadaEm,
    this.vendaId,
    this.itens = const [],
    this.pendente = false,
  });

  bool get isAberta => status == aberta;
  int get quantidadeItens => itens.fold(0, (s, i) => s + i.quantidade);
  int get totalCentavos => itens.fold(0, (s, i) => s + i.totalCentavos);
  double get total => deCentavos(totalCentavos);
  String get codigo => id.length > 6 ? id.substring(0, 6).toUpperCase() : id;

  factory Comanda.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final itens = <ItemComanda>[];
    // Itens ficam num mapa produtoId → dados, para que lançamentos feitos em
    // aparelhos diferentes se somem (FieldValue.increment na quantidade).
    (d['itens'] as Map? ?? const {}).forEach((id, v) {
      final m = Map<String, dynamic>.from(v as Map);
      final qtd = (m['quantidade'] as num?)?.toInt() ?? 0;
      if (qtd <= 0) return;
      itens.add(
        ItemComanda(
          produtoId: id as String,
          nome: m['nome'] as String? ?? '',
          codigo: m['codigo'] as String? ?? '',
          quantidade: qtd,
          precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
          adicionadoEm:
              (m['adicionadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ),
      );
    });
    itens.sort((a, b) => a.adicionadoEm.compareTo(b.adicionadoEm));
    return Comanda(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      pessoas: (d['pessoas'] as num?)?.toInt() ?? 1,
      status: d['status'] as String? ?? aberta,
      abertaPorNome: (d['abertaPor'] as Map?)?['nome'] as String? ?? '',
      abertaEm: (d['abertaEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fechadaEm: (d['fechadaEm'] as Timestamp?)?.toDate(),
      vendaId: d['vendaId'] as String?,
      itens: itens,
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}
