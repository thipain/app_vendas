import 'package:flutter/material.dart';

/// Identidade da loja e dados do comprovante, editados em Configurações.
class ConfigLoja {
  final String nomeLoja;
  final String nomeSistema;
  final String telefone;
  final String documento;
  final String endereco;
  final String mensagemComprovante;
  final String statusLoja;
  final Color corPrimaria;
  final Color corDestaque;

  /// Logo em JPEG/PNG codificado em base64 (vazio = inicial do nome).
  final String logo;

  const ConfigLoja({
    this.nomeLoja = 'Minha Loja',
    this.nomeSistema = 'App Vendas',
    this.telefone = '',
    this.documento = '',
    this.endereco = '',
    this.mensagemComprovante = 'Obrigado pela preferência!',
    this.statusLoja = 'Loja aberta',
    this.corPrimaria = const Color(0xFF173F2D),
    this.corDestaque = const Color(0xFFD8ED87),
    this.logo = '',
  });

  static Color _cor(Object? v, Color padrao) {
    if (v is! String) return padrao;
    final hex = v.replaceFirst('#', '');
    final n = int.tryParse(hex, radix: 16);
    if (n == null || hex.length != 6) return padrao;
    return Color(0xFF000000 | n);
  }

  static String corParaHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  factory ConfigLoja.fromMap(Map<String, dynamic>? d) {
    const p = ConfigLoja();
    if (d == null) return p;
    String s(String k, String padrao) => (d[k] as String?) ?? padrao;
    return ConfigLoja(
      nomeLoja: s('nomeLoja', p.nomeLoja),
      nomeSistema: s('nomeSistema', p.nomeSistema),
      telefone: s('telefone', p.telefone),
      documento: s('documento', p.documento),
      endereco: s('endereco', p.endereco),
      mensagemComprovante: s('mensagemComprovante', p.mensagemComprovante),
      statusLoja: s('statusLoja', p.statusLoja),
      corPrimaria: _cor(d['corPrimaria'], p.corPrimaria),
      corDestaque: _cor(d['corDestaque'], p.corDestaque),
      logo: s('logo', p.logo),
    );
  }

  Map<String, dynamic> toMap() => {
    'nomeLoja': nomeLoja,
    'nomeSistema': nomeSistema,
    'telefone': telefone,
    'documento': documento,
    'endereco': endereco,
    'mensagemComprovante': mensagemComprovante,
    'statusLoja': statusLoja,
    'corPrimaria': corParaHex(corPrimaria),
    'corDestaque': corParaHex(corDestaque),
    'logo': logo,
  };
}
