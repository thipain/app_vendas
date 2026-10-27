import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Calculadora simples, como no sistema original: + − × ÷ e % (resto da
/// divisão). As contas são feitas por um analisador próprio (sem eval).
class CalculadoraPage extends StatelessWidget {
  const CalculadoraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: const Calculadora(),
          ),
        ),
      ),
    );
  }
}

/// Mostra a calculadora em uma janela (atalho da barra superior).
Future<void> mostrarCalculadora(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Calculadora',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Calculadora(fecharComEsc: true),
            ],
          ),
        ),
      ),
    ),
  );
}

class Calculadora extends StatefulWidget {
  /// Na janela, Esc fecha (como em qualquer diálogo) em vez de limpar.
  final bool fecharComEsc;

  const Calculadora({super.key, this.fecharComEsc = false});

  @override
  State<Calculadora> createState() => _CalculadoraState();
}

class _CalculadoraState extends State<Calculadora> {
  static const _erro = 'Erro';
  final _foco = FocusNode();
  String _visor = '0';

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  void _tecla(String k) {
    setState(() {
      switch (k) {
        case 'C':
          _visor = '0';
        case '⌫':
          _visor = _visor.length <= 1 || _visor == _erro
              ? '0'
              : _visor.substring(0, _visor.length - 1);
        case '=':
          _visor = calcular(_visor);
        default:
          _visor = (_visor == '0' || _visor == _erro) ? k : _visor + k;
      }
    });
  }

  KeyEventResult _teclado(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _tecla('=');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _tecla('⌫');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete ||
        (k == LogicalKeyboardKey.escape && !widget.fecharComEsc)) {
      _tecla('C');
      return KeyEventResult.handled;
    }
    final c = e.character;
    if (c == null || c.isEmpty) return KeyEventResult.ignored;
    final mapa = <String, String>{
      '*': '×',
      'x': '×',
      'X': '×',
      '/': '÷',
      '-': '−',
      '+': '+',
      '%': '%',
      ',': ',',
      '.': ',',
      '=': '=',
      'c': 'C',
      'C': 'C',
    };
    if (RegExp(r'^[0-9]$').hasMatch(c)) {
      _tecla(c);
      return KeyEventResult.handled;
    }
    final m = mapa[c];
    if (m != null) {
      _tecla(m);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const linhas = [
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['0', ',', '='],
    ];
    return Focus(
      focusNode: _foco,
      autofocus: true,
      onKeyEvent: _teclado,
      child: GestureDetector(
        onTap: _foco.requestFocus,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Resultado',
                    style: t.textTheme.labelMedium?.copyWith(
                      color: t.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: SelectableText(
                        _visor,
                        maxLines: 1,
                        style: t.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _visor == _erro ? t.colorScheme.error : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final linha in linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    for (final k in linha)
                      Expanded(
                        flex: k == '0' ? 2 : 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _Botao(
                            rotulo: k,
                            tipo: k == '='
                                ? _TipoBotao.igual
                                : RegExp(r'^[0-9,]$').hasMatch(k)
                                ? _TipoBotao.numero
                                : _TipoBotao.operador,
                            onPressed: () {
                              _tecla(k);
                              _foco.requestFocus();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Text(
              '% calcula o resto da divisão. Use o teclado: números, + - * / % , Enter e Backspace.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TipoBotao { numero, operador, igual }

class _Botao extends StatelessWidget {
  final String rotulo;
  final _TipoBotao tipo;
  final VoidCallback onPressed;

  const _Botao({
    required this.rotulo,
    required this.tipo,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (fundo, frente) = switch (tipo) {
      _TipoBotao.numero => (c.surfaceContainerHigh, c.onSurface),
      _TipoBotao.operador => (c.secondaryContainer, c.onSecondaryContainer),
      _TipoBotao.igual => (c.primary, c.onPrimary),
    };
    // Os botões não pegam o foco, para o teclado continuar na calculadora.
    return ExcludeFocus(
      child: SizedBox(
        height: 56,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: fundo,
            foregroundColor: frente,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: onPressed,
          child: Text(rotulo),
        ),
      ),
    );
  }
}

/// Avalia a expressão do visor. Devolve "Erro" para expressões inválidas ou
/// resultados não finitos (ex.: divisão por zero).
String calcular(String visor) {
  final expr = visor
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll(',', '.');
  try {
    final v = _Analisador(expr).avaliar();
    if (!v.isFinite) return 'Erro';
    return formatarResultado(v);
  } on FormatException {
    return 'Erro';
  }
}

/// Número com vírgula decimal, sem zeros à direita.
String formatarResultado(double v) {
  if (v == v.truncateToDouble() && v.abs() < 1e15) {
    return v.toInt().toString();
  }
  var s = double.parse(v.toStringAsPrecision(12)).toString();
  if (s.contains('e')) return s.replaceAll('.', ',');
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}

/// Analisador descendente recursivo:
///   expr   := termo (('+' | '-') termo)*
///   termo  := fator (('*' | '/' | '%') fator)*
///   fator  := ('+' | '-') fator | '(' expr ')' | número
class _Analisador {
  final String s;
  int i = 0;

  _Analisador(String texto) : s = texto.replaceAll(' ', '');

  double avaliar() {
    if (s.isEmpty) throw const FormatException('vazio');
    final v = _expr();
    if (i != s.length) throw const FormatException('sobra');
    return v;
  }

  String? get _atual => i < s.length ? s[i] : null;

  double _expr() {
    var v = _termo();
    while (_atual == '+' || _atual == '-') {
      final op = s[i++];
      final d = _termo();
      v = op == '+' ? v + d : v - d;
    }
    return v;
  }

  double _termo() {
    var v = _fator();
    while (_atual == '*' || _atual == '/' || _atual == '%') {
      final op = s[i++];
      final d = _fator();
      v = switch (op) {
        '*' => v * d,
        '/' => v / d,
        // Resto com o sinal do dividendo, como o % do JavaScript.
        _ => d == 0 ? double.nan : v.remainder(d),
      };
    }
    return v;
  }

  double _fator() {
    final c = _atual;
    if (c == '-') {
      i++;
      return -_fator();
    }
    if (c == '+') {
      i++;
      return _fator();
    }
    if (c == '(') {
      i++;
      final v = _expr();
      if (_atual != ')') throw const FormatException('parêntese');
      i++;
      return v;
    }
    final inicio = i;
    while (_atual != null && RegExp(r'[0-9.]').hasMatch(_atual!)) {
      i++;
    }
    if (inicio == i) throw const FormatException('número esperado');
    final v = double.tryParse(s.substring(inicio, i));
    if (v == null) throw const FormatException('número inválido');
    return v;
  }
}
