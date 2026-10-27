import 'package:cloud_firestore/cloud_firestore.dart';

/// Sessão de caixa (turno). Só existe um caixa aberto por vez na loja.
class Caixa {
  static const aberto = 'aberto';
  static const fechado = 'fechado';

  final String id;
  final String status;
  final double valorAbertura;
  final String observacao;
  final String abertoPorNome;
  final DateTime abertoEm;
  final double? valorFechamento;
  final double? valorEsperado;
  final double? diferenca;
  final String? fechadoPorNome;
  final DateTime? fechadoEm;
  final bool pendente;

  const Caixa({
    required this.id,
    required this.status,
    required this.valorAbertura,
    this.observacao = '',
    required this.abertoPorNome,
    required this.abertoEm,
    this.valorFechamento,
    this.valorEsperado,
    this.diferenca,
    this.fechadoPorNome,
    this.fechadoEm,
    this.pendente = false,
  });

  bool get isAberto => status == aberto;
  String get codigo => id.length > 6 ? id.substring(0, 6).toUpperCase() : id;

  factory Caixa.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Caixa(
      id: doc.id,
      status: d['status'] as String? ?? fechado,
      valorAbertura: (d['valorAbertura'] as num?)?.toDouble() ?? 0,
      observacao: d['observacao'] as String? ?? '',
      abertoPorNome: (d['abertoPor'] as Map?)?['nome'] as String? ?? '',
      abertoEm: (d['abertoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
      valorFechamento: (d['valorFechamento'] as num?)?.toDouble(),
      valorEsperado: (d['valorEsperado'] as num?)?.toDouble(),
      diferenca: (d['diferenca'] as num?)?.toDouble(),
      fechadoPorNome: (d['fechadoPor'] as Map?)?['nome'] as String?,
      fechadoEm: (d['fechadoEm'] as Timestamp?)?.toDate(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}

class MovimentoCaixa {
  static const abertura = 'abertura';
  static const venda = 'venda';
  static const suprimento = 'suprimento';
  static const sangria = 'sangria';
  static const estorno = 'estorno';
  static const fechamento = 'fechamento';

  static const nomes = {
    abertura: 'Abertura',
    venda: 'Venda',
    suprimento: 'Suprimento',
    sangria: 'Sangria',
    estorno: 'Estorno',
    fechamento: 'Fechamento',
  };

  final String id;
  final String caixaId;
  final String tipo;
  final double valor;
  final String descricao;
  final String? vendaId;
  final String usuarioNome;
  final DateTime data;
  final bool pendente;

  const MovimentoCaixa({
    required this.id,
    required this.caixaId,
    required this.tipo,
    required this.valor,
    this.descricao = '',
    this.vendaId,
    this.usuarioNome = '',
    required this.data,
    this.pendente = false,
  });

  String get tipoNome => nomes[tipo] ?? tipo;

  /// Efeito no saldo da gaveta (o fechamento não altera o saldo).
  double get efeito => switch (tipo) {
        abertura || venda || suprimento => valor,
        sangria || estorno => -valor,
        _ => 0,
      };

  factory MovimentoCaixa.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MovimentoCaixa(
      id: doc.id,
      caixaId: d['caixaId'] as String? ?? '',
      tipo: d['tipo'] as String? ?? '',
      valor: (d['valor'] as num?)?.toDouble() ?? 0,
      descricao: d['descricao'] as String? ?? '',
      vendaId: d['vendaId'] as String?,
      usuarioNome: (d['usuario'] as Map?)?['nome'] as String? ?? '',
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}

/// Saldo esperado na gaveta = abertura + vendas + suprimentos − sangrias − estornos.
double saldoCaixa(Iterable<MovimentoCaixa> movimentos) =>
    (movimentos.fold<int>(0, (s, m) => s + (m.efeito * 100).round())) / 100;
