import 'package:cloud_firestore/cloud_firestore.dart';

/// Histórico de cada alteração no saldo de um produto.
class MovimentoEstoque {
  static const inicial = 'inicial';
  static const entrada = 'entrada';
  static const entradaEdicao = 'entrada_edicao';
  static const venda = 'venda';
  static const estorno = 'estorno';
  static const ajuste = 'ajuste';
  static const comanda = 'comanda';
  static const perda = 'perda';
  static const composicao = 'composicao';
  static const decomposicao = 'decomposicao';
  static const retirada = 'retirada';
  static const retiradaDevolucao = 'retirada_devolucao';

  static const nomes = {
    inicial: 'Saldo inicial',
    entrada: 'Entrada de mercadoria',
    entradaEdicao: 'Edição de nota',
    venda: 'Venda',
    estorno: 'Estorno',
    ajuste: 'Ajuste manual',
    comanda: 'Comanda',
    perda: 'Perda',
    composicao: 'Montagem',
    decomposicao: 'Desmanche',
    retirada: 'Retirada de funcionário',
    retiradaDevolucao: 'Devolução de retirada',
  };

  final String id;
  final String produtoId;
  final String produtoNome;
  final String tipo;

  /// Positivo = entrou no estoque; negativo = saiu.
  final int quantidade;

  /// Saldo visto por este aparelho no momento da operação. Com vários
  /// aparelhos offline ao mesmo tempo pode diferir do saldo final do servidor.
  final int estoqueAntes;
  final int estoqueDepois;
  final String? referenciaTipo;
  final String? referenciaId;
  final String motivo;
  final String usuarioNome;
  final DateTime data;
  final bool pendente;

  const MovimentoEstoque({
    required this.id,
    required this.produtoId,
    required this.produtoNome,
    required this.tipo,
    required this.quantidade,
    required this.estoqueAntes,
    required this.estoqueDepois,
    this.referenciaTipo,
    this.referenciaId,
    this.motivo = '',
    this.usuarioNome = '',
    required this.data,
    this.pendente = false,
  });

  String get tipoNome => nomes[tipo] ?? tipo;

  factory MovimentoEstoque.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MovimentoEstoque(
      id: doc.id,
      produtoId: d['produtoId'] as String? ?? '',
      produtoNome: d['produtoNome'] as String? ?? '',
      tipo: d['tipo'] as String? ?? '',
      quantidade: (d['quantidade'] as num?)?.toInt() ?? 0,
      estoqueAntes: (d['estoqueAntes'] as num?)?.toInt() ?? 0,
      estoqueDepois: (d['estoqueDepois'] as num?)?.toInt() ?? 0,
      referenciaTipo: d['referenciaTipo'] as String?,
      referenciaId: d['referenciaId'] as String?,
      motivo: d['motivo'] as String? ?? '',
      usuarioNome: (d['usuario'] as Map?)?['nome'] as String? ?? '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}
