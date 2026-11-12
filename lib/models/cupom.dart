import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/dinheiro.dart';

/// Cupom de desconto da loja online. O código é o id do documento (em
/// maiúsculas). O desconto vale só sobre os produtos, não sobre a taxa de
/// entrega.
class Cupom {
  static const percentual = 'percentual';
  static const valor = 'valor';

  final String codigo;
  final String tipo;

  /// Percentual (0–100) ou valor em R$, conforme o [tipo].
  final double quantia;

  /// Valor mínimo em produtos para o cupom valer.
  final double minimo;

  /// Último dia de validade (null = sem prazo).
  final DateTime? validoAte;
  final bool ativo;
  final String descricao;

  /// Quantas vezes foi usado (pedidos aceitos).
  final int usos;

  const Cupom({
    required this.codigo,
    this.tipo = percentual,
    required this.quantia,
    this.minimo = 0,
    this.validoAte,
    this.ativo = true,
    this.descricao = '',
    this.usos = 0,
  });

  static final _codigoValido = RegExp(r'^[A-Z0-9]{3,20}$');

  static String normalizarCodigo(String c) => c.trim().toUpperCase();
  static bool codigoValido(String c) => _codigoValido.hasMatch(c);

  bool get isPercentual => tipo == percentual;

  /// "10% off" ou "R$ 5,00 off".
  String get resumo => isPercentual
      ? '${quantia.toStringAsFixed(quantia % 1 == 0 ? 0 : 1).replaceAll('.', ',')}% de desconto'
      : 'R\$ ${quantia.toStringAsFixed(2).replaceAll('.', ',')} de desconto';

  /// Por que o cupom não vale para este pedido (null = vale).
  String? motivoInvalido(int subtotalCentavos, DateTime agora) {
    if (!ativo) return 'Cupom desativado.';
    final v = validoAte;
    if (v != null && !agora.isBefore(DateTime(v.year, v.month, v.day + 1))) {
      return 'Cupom vencido.';
    }
    if (subtotalCentavos < centavos(minimo)) {
      return 'Cupom vale para pedidos a partir de '
          'R\$ ${minimo.toStringAsFixed(2).replaceAll('.', ',')} em produtos.';
    }
    return null;
  }

  /// Desconto em centavos sobre o subtotal dos produtos (nunca maior que ele).
  int descontoCentavos(int subtotalCentavos) {
    final d = isPercentual
        ? (subtotalCentavos * quantia.clamp(0, 100) / 100).round()
        : centavos(quantia);
    if (d < 0) return 0;
    return d > subtotalCentavos ? subtotalCentavos : d;
  }

  factory Cupom.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Cupom(
      codigo: doc.id,
      tipo: d['tipo'] as String? ?? percentual,
      quantia: (d['valor'] as num?)?.toDouble() ?? 0,
      minimo: (d['minimo'] as num?)?.toDouble() ?? 0,
      validoAte: (d['validoAte'] as Timestamp?)?.toDate(),
      ativo: d['ativo'] as bool? ?? true,
      descricao: d['descricao'] as String? ?? '',
      usos: (d['usos'] as num?)?.toInt() ?? 0,
    );
  }

  /// Dados que a página do cliente pode ler (sem uso nem descrição interna).
  Map<String, Object?> toPublico() => {
    'tipo': tipo,
    'valor': quantia,
    'minimo': minimo,
    // Fim do último dia de validade.
    'validoAte': validoAte == null
        ? null
        : Timestamp.fromDate(
            DateTime(validoAte!.year, validoAte!.month, validoAte!.day + 1),
          ),
    'ativo': ativo,
  };

  Map<String, Object?> toMap() => {
    'tipo': tipo,
    'valor': quantia,
    'minimo': minimo,
    'validoAte': validoAte == null ? null : Timestamp.fromDate(validoAte!),
    'ativo': ativo,
    'descricao': descricao,
  };
}
