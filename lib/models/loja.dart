import 'package:cloud_firestore/cloud_firestore.dart';

/// Situação da loja quanto ao acesso e à mensalidade.
enum SituacaoLoja {
  semCobranca('Sem cobrança'),
  emTeste('Em teste'),
  emDia('Em dia'),
  vencendo('Vencendo'),
  atrasada('Atrasada (carência)'),
  travadaPagamento('Travada por falta de pagamento'),
  travadaManual('Travada');

  final String rotulo;
  const SituacaoLoja(this.rotulo);

  bool get travada => this == travadaPagamento || this == travadaManual;
}

/// Uma loja (cliente) do sistema. Os dados dela ficam em lojas/{id}/...
class Loja {
  /// Dias antes do vencimento em que a loja passa a ver o aviso.
  static const diasAviso = 7;

  final String id;
  final String nome;

  /// false = travada manualmente pelo dono do sistema.
  final bool ativa;
  final DateTime? travadaEm;
  final DateTime? criadaEm;

  final String responsavelNome;
  final String responsavelTelefone;
  final String responsavelEmail;
  final String documento;
  final String observacoes;

  /// Valor da mensalidade (0 = sem cobrança).
  final double valorMensal;

  /// Vencimento: a loja está paga até esta data. null = sem cobrança.
  final DateTime? pagoAte;

  /// Dias depois do vencimento em que a loja ainda funciona.
  final int carenciaDias;

  /// Período de teste grátis (até o primeiro pagamento).
  final bool emTeste;

  const Loja({
    required this.id,
    required this.nome,
    this.ativa = true,
    this.travadaEm,
    this.criadaEm,
    this.responsavelNome = '',
    this.responsavelTelefone = '',
    this.responsavelEmail = '',
    this.documento = '',
    this.observacoes = '',
    this.valorMensal = 0,
    this.pagoAte,
    this.carenciaDias = 5,
    this.emTeste = false,
  });

  /// Data em que a loja trava se não houver pagamento.
  DateTime? get travaEm => pagoAte?.add(Duration(days: carenciaDias));

  SituacaoLoja situacao([DateTime? agora]) {
    final hoje = agora ?? DateTime.now();
    if (!ativa) return SituacaoLoja.travadaManual;
    final venc = pagoAte;
    if (venc == null) return SituacaoLoja.semCobranca;
    if (hoje.isBefore(venc)) {
      if (emTeste) return SituacaoLoja.emTeste;
      return venc.difference(hoje).inDays < diasAviso
          ? SituacaoLoja.vencendo
          : SituacaoLoja.emDia;
    }
    return hoje.isBefore(travaEm!)
        ? SituacaoLoja.atrasada
        : SituacaoLoja.travadaPagamento;
  }

  /// Dias até o vencimento (negativo = vencido há N dias).
  int? diasParaVencer([DateTime? agora]) {
    final venc = pagoAte;
    if (venc == null) return null;
    final h = agora ?? DateTime.now();
    final hoje = DateTime(h.year, h.month, h.day);
    return DateTime(venc.year, venc.month, venc.day).difference(hoje).inDays;
  }

  factory Loja.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final r = d['responsavel'] as Map? ?? const {};
    return Loja(
      id: doc.id,
      nome: d['nome'] as String? ?? '',
      ativa: d['ativa'] as bool? ?? true,
      travadaEm: (d['travadaEm'] as Timestamp?)?.toDate(),
      criadaEm: (d['criadaEm'] as Timestamp?)?.toDate(),
      responsavelNome: r['nome'] as String? ?? '',
      responsavelTelefone: r['telefone'] as String? ?? '',
      responsavelEmail: r['email'] as String? ?? '',
      documento: r['documento'] as String? ?? '',
      observacoes: d['observacoes'] as String? ?? '',
      valorMensal: (d['valorMensal'] as num?)?.toDouble() ?? 0,
      pagoAte: (d['pagoAte'] as Timestamp?)?.toDate(),
      carenciaDias: (d['carenciaDias'] as num?)?.toInt() ?? 5,
      emTeste: d['emTeste'] as bool? ?? false,
    );
  }

  /// Dados cadastrais e de cobrança editáveis pelo dono do sistema.
  Map<String, dynamic> dadosCadastro() => {
    'nome': nome,
    'responsavel': {
      'nome': responsavelNome,
      'telefone': responsavelTelefone,
      'email': responsavelEmail,
      'documento': documento,
    },
    'observacoes': observacoes,
    'valorMensal': valorMensal,
    'pagoAte': pagoAte == null ? null : Timestamp.fromDate(pagoAte!),
    'carenciaDias': carenciaDias,
    'emTeste': emTeste,
  };

  Loja copyWith({
    String? nome,
    String? responsavelNome,
    String? responsavelTelefone,
    String? responsavelEmail,
    String? documento,
    String? observacoes,
    double? valorMensal,
    DateTime? pagoAte,
    bool limparPagoAte = false,
    int? carenciaDias,
    bool? emTeste,
  }) => Loja(
    id: id,
    nome: nome ?? this.nome,
    ativa: ativa,
    travadaEm: travadaEm,
    criadaEm: criadaEm,
    responsavelNome: responsavelNome ?? this.responsavelNome,
    responsavelTelefone: responsavelTelefone ?? this.responsavelTelefone,
    responsavelEmail: responsavelEmail ?? this.responsavelEmail,
    documento: documento ?? this.documento,
    observacoes: observacoes ?? this.observacoes,
    valorMensal: valorMensal ?? this.valorMensal,
    pagoAte: limparPagoAte ? null : (pagoAte ?? this.pagoAte),
    carenciaDias: carenciaDias ?? this.carenciaDias,
    emTeste: emTeste ?? this.emTeste,
  );
}

/// Soma [meses] a uma data, mantendo o dia (limitado ao fim do mês).
DateTime somarMeses(DateTime data, int meses) {
  final alvo = DateTime(data.year, data.month + meses);
  final ultimoDia = DateTime(alvo.year, alvo.month + 1, 0).day;
  return DateTime(
    alvo.year,
    alvo.month,
    data.day > ultimoDia ? ultimoDia : data.day,
  );
}

/// Novo vencimento após pagar [meses]: continua do vencimento atual, ou de
/// hoje se a loja estava sem cobrança ou vencida há mais de um mês.
DateTime proximoVencimento(DateTime? pagoAte, int meses, [DateTime? agora]) {
  final h = agora ?? DateTime.now();
  final hoje = DateTime(h.year, h.month, h.day);
  final base =
      pagoAte == null ||
          pagoAte.isBefore(hoje.subtract(const Duration(days: 31)))
      ? hoje
      : pagoAte;
  return somarMeses(base, meses);
}

/// Pagamento de mensalidade registrado pelo dono do sistema.
class PagamentoLoja {
  final String id;
  final String lojaId;
  final String lojaNome;
  final double valor;
  final DateTime data;
  final int meses;
  final String forma;
  final String observacao;
  final DateTime? vencimentoAnterior;
  final DateTime novoVencimento;

  const PagamentoLoja({
    required this.id,
    required this.lojaId,
    required this.lojaNome,
    required this.valor,
    required this.data,
    required this.meses,
    required this.forma,
    required this.observacao,
    this.vencimentoAnterior,
    required this.novoVencimento,
  });

  factory PagamentoLoja.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return PagamentoLoja(
      id: doc.id,
      lojaId: d['lojaId'] as String? ?? '',
      lojaNome: d['lojaNome'] as String? ?? '',
      valor: (d['valor'] as num?)?.toDouble() ?? 0,
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      meses: (d['meses'] as num?)?.toInt() ?? 1,
      forma: d['forma'] as String? ?? '',
      observacao: d['observacao'] as String? ?? '',
      vencimentoAnterior: (d['vencimentoAnterior'] as Timestamp?)?.toDate(),
      novoVencimento:
          (d['novoVencimento'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Aviso do dono do sistema exibido no app das lojas.
class Aviso {
  final String id;
  final String titulo;
  final String mensagem;

  /// null = todas as lojas.
  final String? lojaId;
  final String? lojaNome;
  final bool ativo;
  final DateTime criadoEm;

  const Aviso({
    required this.id,
    required this.titulo,
    required this.mensagem,
    this.lojaId,
    this.lojaNome,
    this.ativo = true,
    required this.criadoEm,
  });

  factory Aviso.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Aviso(
      id: doc.id,
      titulo: d['titulo'] as String? ?? '',
      mensagem: d['mensagem'] as String? ?? '',
      lojaId: d['lojaId'] as String?,
      lojaNome: d['lojaNome'] as String?,
      ativo: d['ativo'] as bool? ?? true,
      criadoEm: (d['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Registro da auditoria do sistema (ações do dono do sistema).
class RegistroSistema {
  final String acao;
  final String descricao;
  final String? lojaId;
  final Object? dados;
  final String email;
  final DateTime data;

  const RegistroSistema({
    required this.acao,
    required this.descricao,
    this.lojaId,
    this.dados,
    required this.email,
    required this.data,
  });

  factory RegistroSistema.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return RegistroSistema(
      acao: d['acao'] as String? ?? '',
      descricao: d['descricao'] as String? ?? '',
      lojaId: d['lojaId'] as String?,
      dados: d['dados'],
      email: (d['usuario'] as Map?)?['email'] as String? ?? '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
