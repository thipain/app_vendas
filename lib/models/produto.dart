import 'package:cloud_firestore/cloud_firestore.dart';

class Produto {
  final String id;
  final String nome;
  final String codigo;
  final double preco;
  final int estoque;
  final bool ativo;

  /// true enquanto a última alteração ainda não foi enviada ao servidor.
  final bool pendente;

  const Produto({
    this.id = '',
    required this.nome,
    this.codigo = '',
    required this.preco,
    this.estoque = 0,
    this.ativo = true,
    this.pendente = false,
  });

  factory Produto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Produto(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      codigo: d['codigo'] as String? ?? '',
      preco: (d['preco'] as num?)?.toDouble() ?? 0,
      estoque: (d['estoque'] as num?)?.toInt() ?? 0,
      ativo: d['ativo'] as bool? ?? true,
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'nomeBusca': nome.toLowerCase(),
        'codigo': codigo,
        'preco': preco,
        'estoque': estoque,
        'ativo': ativo,
      };
}
