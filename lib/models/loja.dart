import 'package:cloud_firestore/cloud_firestore.dart';

/// Uma loja (cliente) do sistema. Os dados dela ficam em lojas/{id}/...
class Loja {
  final String id;
  final String nome;

  /// Loja bloqueada pelo dono do sistema: ninguém da equipe consegue entrar.
  final bool ativa;
  final DateTime? criadaEm;

  const Loja({
    required this.id,
    required this.nome,
    this.ativa = true,
    this.criadaEm,
  });

  factory Loja.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Loja(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      ativa: d['ativa'] as bool? ?? true,
      criadaEm: (d['criadaEm'] as Timestamp?)?.toDate(),
    );
  }
}

/// Vínculo do usuário logado com uma loja (documento lojas/{id}/membros/{uid}).
class Vinculo {
  final String lojaId;
  final String lojaNome;
  final String papel;
  final bool ativo;

  const Vinculo({
    required this.lojaId,
    required this.lojaNome,
    required this.papel,
    required this.ativo,
  });

  factory Vinculo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Vinculo(
      lojaId: d['lojaId'] as String? ?? doc.reference.parent.parent!.id,
      lojaNome: d['lojaNome'] as String? ?? '',
      papel: d['papel'] as String? ?? 'vendas',
      ativo: d['ativo'] as bool? ?? true,
    );
  }
}

/// Configuração geral do sistema (config/sistema).
class Sistema {
  final bool existe;
  final Set<String> donos;
  final String? migradoPara;

  const Sistema({this.existe = false, this.donos = const {}, this.migradoPara});

  /// Dono do sistema: cadastra e bloqueia lojas e pode entrar em qualquer uma.
  bool isDono(String uid) => donos.contains(uid);

  factory Sistema.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return const Sistema();
    return Sistema(
      existe: true,
      donos: {
        if (d['adminInicial'] is String) d['adminInicial'] as String,
        ...(d['superAdmins'] as List? ?? const []).whereType<String>(),
      },
      migradoPara: d['migradoPara'] as String?,
    );
  }
}
