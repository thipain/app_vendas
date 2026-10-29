import 'package:cloud_firestore/cloud_firestore.dart';

class ItemReceita {
  final String produtoId;
  final String produtoNome;
  final int quantidade;

  const ItemReceita({
    required this.produtoId,
    required this.produtoNome,
    required this.quantidade,
  });

  factory ItemReceita.fromMap(Map<String, dynamic> m) => ItemReceita(
    produtoId: m['produtoId'] as String? ?? '',
    produtoNome: m['produtoNome'] as String? ?? '',
    quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'produtoId': produtoId,
    'produtoNome': produtoNome,
    'quantidade': quantidade,
  };
}

List<ItemReceita> _itens(Object? v) => (v as List? ?? const [])
    .map((e) => ItemReceita.fromMap(Map<String, dynamic>.from(e as Map)))
    .toList();

/// Regra reutilizável de montagem (vários itens → um produto final) ou
/// desmanche (um item agrupado → um ou vários itens).
class Receita {
  static const composicao = 'composicao';
  static const decomposicao = 'decomposicao';

  final String id;
  final String nome;
  final String tipo;
  final bool ativo;
  final List<ItemReceita> entradas;
  final List<ItemReceita> saidas;
  final bool pendente;

  const Receita({
    this.id = '',
    required this.nome,
    required this.tipo,
    this.ativo = true,
    required this.entradas,
    required this.saidas,
    this.pendente = false,
  });

  bool get isComposicao => tipo == composicao;
  String get tipoNome => isComposicao ? 'Montagem' : 'Desmanche';

  factory Receita.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Receita(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      tipo: d['tipo'] as String? ?? composicao,
      ativo: d['ativo'] as bool? ?? true,
      entradas: _itens(d['entradas']),
      saidas: _itens(d['saidas']),
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  Map<String, dynamic> toMap() => {
    'nome': nome,
    'nomeBusca': nome.toLowerCase(),
    'tipo': tipo,
    'ativo': ativo,
    'entradas': entradas.map((i) => i.toMap()).toList(),
    'saidas': saidas.map((i) => i.toMap()).toList(),
  };
}

class ItemOperacao {
  final String produtoId;
  final String produtoNome;

  /// 'entrada' (consumido) ou 'saida' (gerado).
  final String direcao;
  final int quantidade;
  final int estoqueAntes;
  final int estoqueDepois;

  const ItemOperacao({
    required this.produtoId,
    required this.produtoNome,
    required this.direcao,
    required this.quantidade,
    required this.estoqueAntes,
    required this.estoqueDepois,
  });

  factory ItemOperacao.fromMap(Map<String, dynamic> m) => ItemOperacao(
    produtoId: m['produtoId'] as String? ?? '',
    produtoNome: m['produtoNome'] as String? ?? '',
    direcao: m['direcao'] as String? ?? 'entrada',
    quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
    estoqueAntes: (m['estoqueAntes'] as num?)?.toInt() ?? 0,
    estoqueDepois: (m['estoqueDepois'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'produtoId': produtoId,
    'produtoNome': produtoNome,
    'direcao': direcao,
    'quantidade': quantidade,
    'estoqueAntes': estoqueAntes,
    'estoqueDepois': estoqueDepois,
  };
}

/// Execução de uma receita (histórico).
class OperacaoEstoque {
  final String id;
  final String receitaId;
  final String receitaNome;
  final String tipo;
  final int lotes;
  final String observacao;
  final List<ItemOperacao> itens;
  final String usuarioNome;
  final DateTime data;
  final bool pendente;

  const OperacaoEstoque({
    required this.id,
    required this.receitaId,
    required this.receitaNome,
    required this.tipo,
    required this.lotes,
    required this.observacao,
    required this.itens,
    required this.usuarioNome,
    required this.data,
    this.pendente = false,
  });

  String get tipoNome => tipo == Receita.composicao ? 'Montagem' : 'Desmanche';

  factory OperacaoEstoque.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return OperacaoEstoque(
      id: doc.id,
      receitaId: d['receitaId'] as String? ?? '',
      receitaNome: d['receitaNome'] as String? ?? '',
      tipo: d['tipo'] as String? ?? Receita.composicao,
      lotes: (d['lotes'] as num?)?.toInt() ?? 0,
      observacao: d['observacao'] as String? ?? '',
      itens: (d['itens'] as List? ?? const [])
          .map((e) => ItemOperacao.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      usuarioNome: (d['usuario'] as Map?)?['nome'] as String? ?? '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}
