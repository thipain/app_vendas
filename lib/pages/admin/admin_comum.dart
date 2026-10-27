import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/mensagens.dart';
import 'loja_detalhe_page.dart';

/// Utilitários compartilhados pelas telas do painel administrativo.

final formatoData = DateFormat('dd/MM/yyyy');

/// Formas de pagamento aceitas para a mensalidade.
const formasPagamento = [
  'Pix',
  'Dinheiro',
  'Transferência',
  'Cartão',
  'Boleto',
];

/// Cor da situação: verde (ok), âmbar (atenção) ou vermelho (travada).
Color corSituacao(BuildContext context, SituacaoLoja s) => switch (s) {
  SituacaoLoja.semCobranca ||
  SituacaoLoja.emTeste ||
  SituacaoLoja.emDia => Colors.green.shade700,
  SituacaoLoja.vencendo || SituacaoLoja.atrasada => Colors.amber.shade800,
  SituacaoLoja.travadaPagamento ||
  SituacaoLoja.travadaManual => Theme.of(context).colorScheme.error,
};

IconData iconeSituacao(SituacaoLoja s) => switch (s) {
  SituacaoLoja.semCobranca => Icons.money_off_outlined,
  SituacaoLoja.emTeste => Icons.hourglass_top,
  SituacaoLoja.emDia => Icons.check_circle_outline,
  SituacaoLoja.vencendo => Icons.schedule,
  SituacaoLoja.atrasada => Icons.warning_amber,
  SituacaoLoja.travadaPagamento || SituacaoLoja.travadaManual => Icons.lock,
};

/// Selo colorido com a situação da loja.
class SeloSituacao extends StatelessWidget {
  final SituacaoLoja situacao;

  const SeloSituacao(this.situacao, {super.key});

  @override
  Widget build(BuildContext context) {
    final cor = corSituacao(context, situacao);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconeSituacao(situacao), size: 14, color: cor),
          const SizedBox(width: 4),
          Text(
            situacao.rotulo,
            style: TextStyle(
              color: cor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// "vence em 3 dias", "vence hoje", "vencida há 2 dias" ou "sem cobrança".
String textoVencimento(Loja l) {
  final d = l.diasParaVencer();
  if (d == null) return 'sem cobrança';
  final prefixo = l.emTeste ? 'teste ' : '';
  if (d > 1) return '${prefixo}vence em $d dias';
  if (d == 1) return '${prefixo}vence amanhã';
  if (d == 0) return '${prefixo}vence hoje';
  if (d == -1) return '${prefixo}vencida há 1 dia';
  return '${prefixo}vencida há ${-d} dias';
}

/// Resumo de uma linha: vencimento e valor.
String resumoCobranca(Loja l) => [
  if (l.pagoAte != null)
    '${formatoData.format(l.pagoAte!)} (${textoVencimento(l)})'
  else
    'Sem cobrança',
  if (l.valorMensal > 0) '${formatarMoeda(l.valorMensal)}/mês',
].join(' · ');

/// Abre os detalhes da loja (página empilhada).
Future<void> abrirLoja(
  BuildContext context,
  Loja loja,
  ValueChanged<String> onEntrarLoja,
) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => LojaDetalhePage(loja: loja, onEntrarLoja: onEntrarLoja),
  ),
);

/// Executa uma operação que precisa de internet mostrando um indicador de
/// progresso. Retorna true quando deu certo.
Future<bool> executarComProgresso(
  BuildContext context,
  Future<void> Function() acao, {
  String? sucesso,
  String mensagem = 'Salvando...',
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(mensagem)),
          ],
        ),
      ),
    ),
  );
  try {
    await acao();
    nav.pop();
    if (context.mounted && sucesso != null) avisar(context, sucesso);
    return true;
  } catch (e) {
    nav.pop();
    if (context.mounted) mostrarErro(context, mensagemErroConta(e));
    return false;
  }
}

/// Traduz erros de criação de conta (Firebase Auth) para o usuário.
Object mensagemErroConta(Object e) {
  if (e is! FirebaseAuthException) return e;
  return StateError(switch (e.code) {
    'email-already-in-use' =>
      'Este e-mail já tem conta, mas não está vinculado a nenhuma loja '
          'por este app. Use outro e-mail.',
    'invalid-email' => 'E-mail inválido.',
    'weak-password' => 'Senha fraca: use pelo menos 8 caracteres.',
    'network-request-failed' =>
      'Sem internet. Esta operação precisa de conexão.',
    _ => 'Não foi possível concluir (${e.code}).',
  });
}

/// Texto do erro para exibir dentro de formulários.
String textoErro(Object e) => switch (mensagemErroConta(e)) {
  StateError(:final message) => message,
  final outro => '$outro',
};

// ---------------------------------------------------------------- WhatsApp

/// Telefone do responsável no formato do wa.me (com 55), ou null.
String? telefoneWhatsApp(Loja l) {
  final d = l.responsavelTelefone.replaceAll(RegExp(r'\D'), '');
  if (d.length < 8) return null;
  return d.length <= 11 ? '55$d' : d;
}

String mensagemCobranca(Loja l) {
  final nome = l.responsavelNome.trim().isEmpty
      ? ''
      : ' ${l.responsavelNome.trim().split(RegExp(r'\s+')).first}';
  final valor = l.valorMensal > 0
      ? ' no valor de ${formatarMoeda(l.valorMensal)}'
      : '';
  final venc = l.pagoAte;
  final dias = l.diasParaVencer() ?? 0;
  final quando = venc == null
      ? ''
      : dias >= 0
      ? ' vence em ${formatoData.format(venc)}'
      : ' venceu em ${formatoData.format(venc)}';
  final trava = l.travaEm;
  final aviso = l.situacao().travada
      ? ' O acesso da equipe está suspenso até a confirmação do pagamento.'
      : dias < 0 && trava != null
      ? ' Para evitar a suspensão do acesso, o pagamento precisa ser feito '
            'até ${formatoData.format(trava)}.'
      : '';
  return 'Olá$nome, a mensalidade do app da ${l.nome}$valor$quando.$aviso '
      'Pode me enviar o comprovante quando realizar o pagamento? Obrigado!';
}

Future<void> cobrarNoWhatsApp(BuildContext context, Loja l) async {
  final fone = telefoneWhatsApp(l);
  if (fone == null) {
    avisar(context, 'Cadastre o telefone do responsável para cobrar.');
    return;
  }
  final uri = Uri.parse(
    'https://wa.me/$fone?text=${Uri.encodeComponent(mensagemCobranca(l))}',
  );
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      avisar(context, 'Não foi possível abrir o WhatsApp.');
    }
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
  }
}

/// Botões rápidos de cobrança (registrar pagamento e WhatsApp).
class BotoesCobranca extends StatelessWidget {
  final Loja loja;

  const BotoesCobranca(this.loja, {super.key});

  @override
  Widget build(BuildContext context) {
    final temFone = telefoneWhatsApp(loja) != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Registrar pagamento',
          icon: const Icon(Icons.payments_outlined),
          onPressed: () => registrarPagamento(context, loja),
        ),
        IconButton(
          tooltip: temFone
              ? 'Cobrar no WhatsApp'
              : 'Sem telefone do responsável',
          icon: const Icon(Icons.chat_outlined),
          onPressed: temFone ? () => cobrarNoWhatsApp(context, loja) : null,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ Pagamento

/// Abre o diálogo de pagamento. Retorna o novo vencimento, ou null.
Future<DateTime?> registrarPagamento(BuildContext context, Loja loja) async {
  final novo = await showDialog<DateTime>(
    context: context,
    builder: (_) => _DialogPagamento(loja: loja),
  );
  if (novo != null && context.mounted) {
    avisar(
      context,
      'Pagamento registrado. Novo vencimento: ${formatoData.format(novo)}.',
    );
  }
  return novo;
}

class _DialogPagamento extends StatefulWidget {
  final Loja loja;

  const _DialogPagamento({required this.loja});

  @override
  State<_DialogPagamento> createState() => _DialogPagamentoState();
}

class _DialogPagamentoState extends State<_DialogPagamento> {
  final _repo = SistemaRepository();
  final _form = GlobalKey<FormState>();
  late final _valor = TextEditingController(
    text: widget.loja.valorMensal > 0
        ? valorParaCampo(widget.loja.valorMensal)
        : '',
  );
  final _obs = TextEditingController();
  int _meses = 1;
  DateTime _data = DateTime.now();
  String _forma = formasPagamento.first;
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _valor.dispose();
    _obs.dispose();
    super.dispose();
  }

  DateTime get _previsao => proximoVencimento(
    widget.loja.emTeste ? null : widget.loja.pagoAte,
    _meses,
  );

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final agora = DateTime.now();
      final novo = await _repo.registrarPagamento(
        widget.loja,
        valor: lerValor(_valor.text) ?? 0,
        meses: _meses,
        data: DateTime(
          _data.year,
          _data.month,
          _data.day,
          agora.hour,
          agora.minute,
        ),
        forma: _forma,
        observacao: _obs.text,
      );
      if (mounted) Navigator.pop(context, novo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = textoErro(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final l = widget.loja;
    return AlertDialog(
      title: Text('Pagamento · ${l.nome}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _valor,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valor recebido',
                    prefixText: r'R$ ',
                  ),
                  validator: (v) {
                    final n = lerValor(v ?? '');
                    return n == null || n < 0 ? 'Informe o valor' : null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _meses,
                        decoration: const InputDecoration(
                          labelText: 'Meses pagos',
                        ),
                        items: [
                          for (var i = 1; i <= 12; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(i == 1 ? '1 mês' : '$i meses'),
                            ),
                        ],
                        onChanged: (v) {
                          final n = v ?? 1;
                          setState(() {
                            final unit = lerValor(_valor.text);
                            if (unit != null &&
                                l.valorMensal > 0 &&
                                unit == l.valorMensal * _meses) {
                              _valor.text = valorParaCampo(l.valorMensal * n);
                            }
                            _meses = n;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _forma,
                        decoration: const InputDecoration(labelText: 'Forma'),
                        items: [
                          for (final f in formasPagamento)
                            DropdownMenuItem(value: f, child: Text(f)),
                        ],
                        onChanged: (v) => setState(() => _forma = v ?? _forma),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _escolherData,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data do pagamento',
                      suffixIcon: Icon(Icons.event),
                    ),
                    child: Text(formatoData.format(_data)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _obs,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                  ),
                ),
                const SizedBox(height: 4),
                Card(
                  margin: EdgeInsets.zero,
                  color: t.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vencimento atual: '
                          '${l.pagoAte == null ? 'sem cobrança' : formatoData.format(l.pagoAte!)}'
                          '${l.emTeste ? ' (teste grátis)' : ''}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Novo vencimento: ${formatoData.format(_previsao)}',
                          style: t.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (l.emTeste)
                          const Text(
                            'O primeiro pagamento encerra o teste grátis e '
                            'conta a partir de hoje.',
                          ),
                      ],
                    ),
                  ),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(_erro!, style: TextStyle(color: t.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: Text(_salvando ? 'Registrando...' : 'Registrar'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------- Travar / liberar

Future<void> alternarTrava(BuildContext context, Loja loja) async {
  final travar = loja.ativa;
  final trava = loja.travaEm;
  final vencida = trava != null && !DateTime.now().isBefore(trava);
  final ok = await confirmar(
    context,
    titulo: travar ? 'Travar loja' : 'Liberar loja',
    mensagem: travar
        ? 'A equipe da ${loja.nome} verá a tela "Acesso suspenso" e não '
              'conseguirá usar o app até você liberar novamente. Os dados '
              'são mantidos.'
        : 'A equipe da ${loja.nome} voltará a ter acesso ao app.'
              '${vencida ? ' Atenção: a mensalidade está vencida desde '
                        '${formatoData.format(loja.pagoAte!)}, então a loja '
                        'continuará travada por falta de pagamento até você '
                        'registrar um pagamento ou alterar o vencimento.' : ''}',
    confirmarTexto: travar ? 'Travar' : 'Liberar',
  );
  if (!ok || !context.mounted) return;
  await executarComProgresso(
    context,
    () => SistemaRepository().definirAtiva(loja, !travar),
    sucesso: travar ? 'Loja travada.' : 'Loja liberada.',
  );
}

// ------------------------------------------------------- Administrador

Future<void> adicionarAdministrador(BuildContext context, Loja loja) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => DialogAdministrador(loja: loja),
  );
  if (ok == true && context.mounted) {
    avisar(context, 'Administrador adicionado.');
  }
}

/// Cadastra outro administrador para a loja (conta nova ou já existente).
class DialogAdministrador extends StatefulWidget {
  final Loja loja;

  const DialogAdministrador({super.key, required this.loja});

  @override
  State<DialogAdministrador> createState() => _DialogAdministradorState();
}

class _DialogAdministradorState extends State<DialogAdministrador> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await SistemaRepository().adicionarAdministrador(
        widget.loja,
        nome: _nome.text.trim(),
        email: _email.text.trim(),
        senha: _senha.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = textoErro(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Administrador da ${widget.loja.nome}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...camposAdministrador(_nome, _email, _senha),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: Text(_salvando ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }
}

final _regexEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validarEmail(String? v, {bool obrigatorio = true}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return obrigatorio ? 'Informe o e-mail' : null;
  return _regexEmail.hasMatch(t) ? null : 'Informe um e-mail válido';
}

/// Campos nome, e-mail e senha inicial do administrador da loja.
List<Widget> camposAdministrador(
  TextEditingController nome,
  TextEditingController email,
  TextEditingController senha,
) => [
  TextFormField(
    controller: nome,
    textCapitalization: TextCapitalization.words,
    decoration: const InputDecoration(labelText: 'Nome'),
    validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
  ),
  const SizedBox(height: 12),
  TextFormField(
    controller: email,
    keyboardType: TextInputType.emailAddress,
    decoration: const InputDecoration(labelText: 'E-mail'),
    validator: validarEmail,
  ),
  const SizedBox(height: 12),
  TextFormField(
    controller: senha,
    obscureText: true,
    decoration: const InputDecoration(
      labelText: 'Senha inicial',
      helperText:
          'Se a pessoa já usa o app em outra loja, a senha dela continua a '
          'mesma.',
      helperMaxLines: 2,
    ),
    validator: (v) =>
        (v ?? '').length < 8 ? 'Use pelo menos 8 caracteres' : null,
  ),
];

/// Linha de loja com selo de situação e botões de cobrança.
class ListTileLojaCobranca extends StatelessWidget {
  final Loja loja;
  final ValueChanged<String> onEntrarLoja;

  const ListTileLojaCobranca({
    super.key,
    required this.loja,
    required this.onEntrarLoja,
  });

  @override
  Widget build(BuildContext context) {
    final l = loja;
    return ListTile(
      onTap: () => abrirLoja(context, l, onEntrarLoja),
      title: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text(l.nome), SeloSituacao(l.situacao())],
      ),
      subtitle: Text(
        [
          resumoCobranca(l),
          if (l.responsavelNome.isNotEmpty) l.responsavelNome,
        ].join(' · '),
      ),
      trailing: BotoesCobranca(l),
    );
  }
}
