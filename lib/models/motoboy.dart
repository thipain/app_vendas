import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';

/// Motoboy cadastrado na loja. Pode ou não ter login no app: quando está
/// ligado a um usuário com papel Entregador ([usuarioId]), os pedidos
/// despachados para ele aparecem na tela "Minhas entregas" do celular dele.
class Motoboy {
  final String id;
  final String nome;
  final String telefone;
  final bool ativo;
  final String? usuarioId;

  const Motoboy({
    this.id = '',
    required this.nome,
    this.telefone = '',
    this.ativo = true,
    this.usuarioId,
  });

  factory Motoboy.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Motoboy(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      telefone: d['telefone'] as String? ?? '',
      ativo: d['ativo'] as bool? ?? true,
      usuarioId: d['usuarioId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'nome': nome,
    'nomeBusca': nome.toLowerCase(),
    'telefone': telefone,
    'ativo': ativo,
    'usuarioId': usuarioId,
  };
}

/// Quanto um motoboy recebe no dia: diária (se trabalhou) + valor por
/// entrega feita. Tudo em centavos.
int pagamentoMotoboyCentavos({
  required int entregas,
  required double diaria,
  required double porEntrega,
  required bool recebeDiaria,
}) =>
    (recebeDiaria ? centavos(diaria) : 0) +
    centavos(porEntrega) * (entregas < 0 ? 0 : entregas);

/// Uma linha do fechamento do dia.
class LinhaFechamento {
  final String motoboyId;
  final String nome;
  final int entregas;
  final double diaria;
  final double porEntrega;
  final double total;

  const LinhaFechamento({
    required this.motoboyId,
    required this.nome,
    required this.entregas,
    required this.diaria,
    required this.porEntrega,
    required this.total,
  });

  factory LinhaFechamento.fromMap(Map<String, dynamic> m) => LinhaFechamento(
    motoboyId: m['motoboyId'] as String? ?? '',
    nome: m['nome'] as String? ?? '',
    entregas: (m['entregas'] as num?)?.toInt() ?? 0,
    diaria: (m['diaria'] as num?)?.toDouble() ?? 0,
    porEntrega: (m['porEntrega'] as num?)?.toDouble() ?? 0,
    total: (m['total'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'motoboyId': motoboyId,
    'nome': nome,
    'entregas': entregas,
    'diaria': diaria,
    'porEntrega': porEntrega,
    'total': total,
  };
}

/// Fechamento do dia dos motoboys ("zerar"): guarda quantas entregas cada
/// um fez desde o fechamento anterior e quanto recebeu. O próximo dia conta
/// as entregas feitas a partir de [fim].
class FechamentoMotoboys {
  final String id;
  final DateTime inicio;
  final DateTime fim;
  final List<LinhaFechamento> linhas;
  final String porNome;
  final bool pagoPeloCaixa;
  final bool pendente;

  const FechamentoMotoboys({
    required this.id,
    required this.inicio,
    required this.fim,
    required this.linhas,
    this.porNome = '',
    this.pagoPeloCaixa = false,
    this.pendente = false,
  });

  int get entregas => linhas.fold(0, (s, l) => s + l.entregas);
  double get total =>
      deCentavos(linhas.fold(0, (s, l) => s + centavos(l.total)));

  factory FechamentoMotoboys.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return FechamentoMotoboys(
      id: doc.id,
      inicio: (d['inicio'] as Timestamp?)?.toDate() ?? DateTime(2000),
      fim: (d['fim'] as Timestamp?)?.toDate() ?? DateTime.now(),
      linhas: (d['linhas'] as List? ?? const [])
          .map(
            (e) => LinhaFechamento.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      porNome: (d['por'] as Map?)?['nome'] as String? ?? '',
      pagoPeloCaixa: d['pagoPeloCaixa'] as bool? ?? false,
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}
