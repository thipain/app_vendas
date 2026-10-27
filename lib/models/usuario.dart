import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/permissoes.dart';

/// Perfil de um membro da equipe. O documento usa o mesmo id (uid) da conta
/// no Firebase Authentication.
class Usuario {
  static const papelAdmin = 'admin';
  static const papelVendas = 'vendas';

  final String id;
  final String nome;
  final String email;
  final String papel;
  final bool ativo;
  final Set<String> permissoes;

  const Usuario({
    this.id = '',
    required this.nome,
    required this.email,
    this.papel = papelVendas,
    this.ativo = true,
    this.permissoes = const {},
  });

  bool get isAdmin => papel == papelAdmin;

  bool pode(String permissao) {
    if (!ativo) return false;
    if (isAdmin) return true;
    if (permissao == Permissao.admin) return false;
    return Permissao.livres.contains(permissao) ||
        permissoes.contains(permissao);
  }

  factory Usuario.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Usuario(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      email: d['email'] as String? ?? '',
      papel: d['papel'] as String? ?? papelVendas,
      ativo: d['ativo'] as bool? ?? true,
      permissoes: (d['permissoes'] as List? ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'nomeBusca': nome.toLowerCase(),
        'email': email,
        'papel': papel,
        'ativo': ativo,
        'permissoes': permissoes.toList()..sort(),
      };

  Usuario copyWith({
    String? nome,
    String? papel,
    bool? ativo,
    Set<String>? permissoes,
  }) =>
      Usuario(
        id: id,
        nome: nome ?? this.nome,
        email: email,
        papel: papel ?? this.papel,
        ativo: ativo ?? this.ativo,
        permissoes: permissoes ?? this.permissoes,
      );
}
