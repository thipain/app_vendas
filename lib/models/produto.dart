import 'package:cloud_firestore/cloud_firestore.dart';

class Produto {
  final String id;
  final String nome;

  /// Código interno / SKU / código de barras.
  final String codigo;
  final String categoria;
  final double preco;

  /// Preço de custo (atualizado pelas notas de entrada e transformações).
  final double custo;
  final int estoque;
  final int estoqueMinimo;
  final String unidade;

  final bool ativo;

  /// true enquanto a última alteração ainda não foi enviada ao servidor.
  final bool pendente;

  const Produto({
    this.id = '',
    required this.nome,
    this.codigo = '',
    this.categoria = '',
    required this.preco,
    this.custo = 0,
    this.estoque = 0,
    this.estoqueMinimo = 0,
    this.unidade = 'un',
    this.ativo = true,
    this.pendente = false,
  });

  bool get zerado => estoque <= 0;

  /// Estoque no mínimo ou abaixo (mas não zerado).
  bool get estoqueBaixo => !zerado && estoque <= estoqueMinimo;

  factory Produto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Produto(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      codigo: d['codigo'] as String? ?? '',
      categoria: d['categoria'] as String? ?? '',
      preco: (d['preco'] as num?)?.toDouble() ?? 0,
      custo: (d['custo'] as num?)?.toDouble() ?? 0,
      estoque: (d['estoque'] as num?)?.toInt() ?? 0,
      estoqueMinimo: (d['estoqueMinimo'] as num?)?.toInt() ?? 0,
      unidade: d['unidade'] as String? ?? 'un',
      ativo: d['ativo'] as bool? ?? true,
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  /// Campos cadastrais. O estoque não entra aqui: ele só muda por
  /// movimentações (venda, entrada, ajuste...), sempre com FieldValue.increment.
  Map<String, dynamic> toMap() => {
        'nome': nome,
        'nomeBusca': nome.toLowerCase(),
        'codigo': codigo,
        'categoria': categoria,
        'preco': preco,
        'custo': custo,
        'estoqueMinimo': estoqueMinimo,
        'unidade': unidade,
        'ativo': ativo,
      };

  Produto copyWith({String? id, int? estoque, double? custo}) => Produto(
        id: id ?? this.id,
        nome: nome,
        codigo: codigo,
        categoria: categoria,
        preco: preco,
        custo: custo ?? this.custo,
        estoque: estoque ?? this.estoque,
        estoqueMinimo: estoqueMinimo,
        unidade: unidade,
        ativo: ativo,
      );

  /// Dados para a auditoria (sem a foto).
  Map<String, dynamic> resumo() => {
        'nome': nome,
        'codigo': codigo,
        'categoria': categoria,
        'preco': preco,
        'custo': custo,
        'estoqueMinimo': estoqueMinimo,
        'unidade': unidade,
        'ativo': ativo,
      };
}
