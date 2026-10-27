import 'package:cloud_firestore/cloud_firestore.dart';

class Cliente {
  final String id;
  final String nome;
  final String documento;
  final String telefone;
  final String email;
  final String endereco;
  final bool pendente;

  const Cliente({
    this.id = '',
    required this.nome,
    this.documento = '',
    this.telefone = '',
    this.email = '',
    this.endereco = '',
    this.pendente = false,
  });

  factory Cliente.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Cliente(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      documento: d['documento'] as String? ?? '',
      telefone: d['telefone'] as String? ?? '',
      email: d['email'] as String? ?? '',
      endereco: d['endereco'] as String? ?? '',
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'nomeBusca': nome.toLowerCase(),
        'documento': documento,
        'telefone': telefone,
        'email': email,
        'endereco': endereco,
      };
}
