import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/largura_maxima.dart';
import '../inicio/comum.dart';
import 'admin_comum.dart';

/// Cadastro de nova loja (com o administrador dela) ou edição do cadastro e
/// da cobrança de uma loja existente. Retorna true quando salvou.
class LojaFormPage extends StatefulWidget {
  /// null = nova loja.
  final Loja? loja;

  const LojaFormPage({super.key, this.loja});

  @override
  State<LojaFormPage> createState() => _LojaFormPageState();
}

class _LojaFormPageState extends State<LojaFormPage> {
  final _repo = SistemaRepository();
  final _form = GlobalKey<FormState>();

  late final Loja? _antes = widget.loja;
  bool get _nova => _antes == null;

  late final _nome = TextEditingController(text: _antes?.nome);
  late final _respNome = TextEditingController(text: _antes?.responsavelNome);
  late final _respFone = TextEditingController(
    text: _antes?.responsavelTelefone,
  );
  late final _respEmail = TextEditingController(text: _antes?.responsavelEmail);
  late final _documento = TextEditingController(text: _antes?.documento);
  late final _obs = TextEditingController(text: _antes?.observacoes);
  late final _valor = TextEditingController(
    text: (_antes?.valorMensal ?? 0) > 0
        ? valorParaCampo(_antes!.valorMensal)
        : (_nova ? valorParaCampo(PlanoLoja.completo.valorSugerido) : ''),
  );
  late final _carencia = TextEditingController(
    text: '${_antes?.carenciaDias ?? 5}',
  );
  final _diasTeste = TextEditingController(text: '7');

  final _adminNome = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminSenha = TextEditingController();

  /// Vencimento (edição) ou primeiro vencimento (nova loja sem teste).
  late DateTime? _pagoAte = _nova ? somarMeses(_hoje, 1) : _antes!.pagoAte;
  late bool _emTeste = _antes?.emTeste ?? false;
  late PlanoLoja _plano = _antes?.plano ?? PlanoLoja.completo;

  bool _salvando = false;
  String? _erro;

  static DateTime get _hoje {
    final h = DateTime.now();
    return DateTime(h.year, h.month, h.day);
  }

  int get _teste => int.tryParse(_diasTeste.text.trim()) ?? 0;

  @override
  void dispose() {
    for (final c in [
      _nome,
      _respNome,
      _respFone,
      _respEmail,
      _documento,
      _obs,
      _valor,
      _carencia,
      _diasTeste,
      _adminNome,
      _adminEmail,
      _adminSenha,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherVencimento() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _pagoAte ?? _hoje,
      firstDate: DateTime(2020),
      lastDate: DateTime(_hoje.year + 5),
      helpText: _nova ? 'Primeiro vencimento' : 'Vencimento',
    );
    if (d != null) setState(() => _pagoAte = d);
  }

  Loja _montar() {
    final base = _antes ?? Loja(id: '', nome: _nome.text.trim());
    return base.copyWith(
      nome: _nome.text.trim(),
      responsavelNome: _respNome.text.trim(),
      responsavelTelefone: _respFone.text.trim(),
      responsavelEmail: _respEmail.text.trim().toLowerCase(),
      documento: _documento.text.trim(),
      observacoes: _obs.text.trim(),
      valorMensal: lerValor(_valor.text) ?? 0,
      carenciaDias: int.tryParse(_carencia.text.trim()) ?? 5,
      pagoAte: _pagoAte,
      limparPagoAte: _pagoAte == null,
      emTeste: _pagoAte != null && _emTeste,
      plano: _plano,
    );
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final dados = _montar();
      if (_nova) {
        final teste = _teste;
        // Com teste grátis, criarLoja calcula o vencimento (hoje + dias).
        // Sem teste, o vencimento escolhido vai no cadastro e é mantido.
        await _repo.criarLoja(
          nomeLoja: dados.nome,
          nomeAdmin: _adminNome.text.trim(),
          emailAdmin: _adminEmail.text.trim(),
          senhaAdmin: _adminSenha.text,
          cadastro: teste > 0
              ? dados.copyWith(limparPagoAte: true, emTeste: false)
              : dados.copyWith(emTeste: false),
          diasTeste: teste,
        );
      } else {
        await _repo.salvarCadastro(_antes!, dados);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = textoErro(e);
      });
    }
  }

  Widget _campoVencimento(String rotulo, String? ajuda) => InkWell(
    onTap: _escolherVencimento,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: rotulo,
        helperText: ajuda,
        helperMaxLines: 2,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pagoAte != null)
              IconButton(
                tooltip: 'Sem cobrança',
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() => _pagoAte = null),
              ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.event),
            ),
          ],
        ),
      ),
      child: Text(
        _pagoAte == null ? 'Sem cobrança' : formatoData.format(_pagoAte!),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const espaco = SizedBox(height: 12);
    final desktop = MediaQuery.sizeOf(context).width >= 600;
    Widget par(Widget a, Widget b) => desktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          )
        : Column(children: [a, espaco, b]);

    return Scaffold(
      appBar: AppBar(
        title: Text(_nova ? 'Nova loja' : 'Editar ${_antes!.nome}'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            LarguraMaxima(
              largura: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TituloSecao('Loja'),
                  TextFormField(
                    controller: _nome,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome da loja',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
                  ),
                  const TituloSecao('Responsável'),
                  par(
                    TextFormField(
                      controller: _respNome,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nome'),
                    ),
                    TextFormField(
                      controller: _respFone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefone / WhatsApp',
                        hintText: '(11) 91234-5678',
                      ),
                    ),
                  ),
                  espaco,
                  par(
                    TextFormField(
                      controller: _respEmail,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (v) => validarEmail(v, obrigatorio: false),
                    ),
                    TextFormField(
                      controller: _documento,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'CPF / CNPJ',
                      ),
                    ),
                  ),
                  espaco,
                  TextFormField(
                    controller: _obs,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 1000,
                    decoration: const InputDecoration(labelText: 'Observações'),
                  ),
                  const TituloSecao('Cobrança'),
                  SegmentedButton<PlanoLoja>(
                    segments: [
                      for (final p in PlanoLoja.values)
                        ButtonSegment(
                          value: p,
                          label: Text('${p.rotulo} · ${p.descricaoLimite}'),
                        ),
                    ],
                    selected: {_plano},
                    onSelectionChanged: (s) => setState(() {
                      final antigo = _plano;
                      _plano = s.first;
                      // Troca o valor só se ainda era o sugerido do plano.
                      final atual = lerValor(_valor.text);
                      if (atual == null || atual == antigo.valorSugerido) {
                        _valor.text = valorParaCampo(_plano.valorSugerido);
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  par(
                    TextFormField(
                      controller: _valor,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Valor mensal',
                        prefixText: r'R$ ',
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return null;
                        final n = lerValor(v!);
                        return n == null || n < 0
                            ? 'Informe um valor válido'
                            : null;
                      },
                    ),
                    TextFormField(
                      controller: _carencia,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Carência (dias)',
                        helperText: 'Dias após o vencimento antes de travar',
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 0 || n > 60
                            ? 'Informe de 0 a 60'
                            : null;
                      },
                    ),
                  ),
                  espaco,
                  if (_nova) ...[
                    TextFormField(
                      controller: _diasTeste,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Teste grátis (dias)',
                        helperText: '0 = começa cobrando',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 0 || n > 90
                            ? 'Informe de 0 a 90'
                            : null;
                      },
                    ),
                    espaco,
                    if (_teste > 0)
                      Text(
                        'O teste vai até '
                        '${formatoData.format(_hoje.add(Duration(days: _teste)))}. '
                        'O primeiro pagamento encerra o teste.',
                        style: t.textTheme.bodySmall,
                      )
                    else
                      _campoVencimento(
                        'Primeiro vencimento',
                        'Limpe a data para deixar a loja sem cobrança.',
                      ),
                  ] else ...[
                    _campoVencimento(
                      'Vencimento (pago até)',
                      'Limpe a data para deixar a loja sem cobrança.',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Em teste grátis'),
                      subtitle: const Text(
                        'O primeiro pagamento encerra o teste.',
                      ),
                      value: _pagoAte != null && _emTeste,
                      onChanged: _pagoAte == null
                          ? null
                          : (v) => setState(() => _emTeste = v),
                    ),
                  ],
                  if (_nova) ...[
                    const TituloSecao('Administrador da loja'),
                    Text(
                      'Quem vai administrar a loja no app. Ele cadastra a '
                      'própria equipe.',
                      style: t.textTheme.bodySmall,
                    ),
                    espaco,
                    ...camposAdministrador(
                      _adminNome,
                      _adminEmail,
                      _adminSenha,
                    ),
                  ],
                  if (_erro != null) ...[
                    const SizedBox(height: 16),
                    Text(_erro!, style: TextStyle(color: t.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        _salvando
                            ? 'Salvando...'
                            : _nova
                            ? 'Cadastrar loja'
                            : 'Salvar',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
