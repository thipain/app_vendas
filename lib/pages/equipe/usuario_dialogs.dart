import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/permissoes.dart';
import '../../core/regra_exception.dart';
import '../../core/sessao.dart';
import '../../data/dados.dart';
import '../../data/usuario_repository.dart';
import '../../models/usuario.dart';
import '../../widgets/mensagens.dart';

final _regexEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Traduz os erros do Firebase Authentication para mensagens da equipe.
String mensagemErroConta(Object erro) {
  if (erro is FirebaseAuthException) {
    return switch (erro.code) {
      'email-already-in-use' => 'Este e-mail já está cadastrado.',
      'invalid-email' => 'Informe um e-mail válido.',
      'weak-password' => 'A senha é muito fraca. Use pelo menos 8 caracteres, misturando letras e números.',
      'network-request-failed' => 'Sem conexão com a internet. Esta operação precisa de internet; tente novamente quando estiver online.',
      'wrong-password' ||
      'invalid-credential' => 'A senha atual está incorreta.',
      'too-many-requests' =>
        'Muitas tentativas. Aguarde alguns minutos e tente novamente.',
      'requires-recent-login' =>
        'Por segurança, saia e entre novamente antes de alterar a senha.',
      'user-not-found' => 'Conta de acesso não encontrada.',
      _ => 'Não foi possível concluir: ${erro.message ?? erro.code}',
    };
  }
  if (erro is RegraException) return erro.mensagem;
  if (erro is StateError) return erro.message;
  return 'Não foi possível concluir: $erro';
}

/// Rótulos dos níveis de acesso.
const _niveis = {
  Usuario.papelVendas: 'Funcionário com acessos personalizados',
  Usuario.papelAdmin: 'Administrador completo',
};

/// Abre o cadastro de um novo funcionário (precisa de internet).
Future<void> novoFuncionario(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _NovoFuncionarioDialog(),
  );
  if (ok == true && context.mounted) {
    avisar(context, 'Funcionário cadastrado com os acessos selecionados.');
  }
}

/// Abre a edição de nome, nível e permissões de um funcionário.
Future<void> editarAcessos(BuildContext context, Usuario usuario) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _AcessosDialog(usuario: usuario),
  );
  if (ok == true && context.mounted) {
    avisar(
      context,
      'Permissões atualizadas. O menu do funcionário muda na hora.',
    );
  }
}

/// Lista de módulos do catálogo com caixas de seleção.
class _ListaPermissoes extends StatelessWidget {
  final Set<String> selecionadas;
  final bool habilitado;
  final ValueChanged<Set<String>> onChanged;

  const _ListaPermissoes({
    required this.selecionadas,
    required this.habilitado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text('Módulos liberados', style: t.textTheme.titleSmall),
        ),
        if (!habilitado)
          Text(
            'Administradores têm acesso a todos os módulos.',
            style: t.textTheme.bodySmall,
          ),
        for (final e in Permissao.catalogo.entries)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: !habilitado || selecionadas.contains(e.key),
            title: Text(e.value),
            subtitle: e.key == Permissao.notificacoes
                ? const Text('Libera também o estoque')
                : null,
            onChanged: habilitado
                ? (v) {
                    final novo = {...selecionadas};
                    if (v == true) {
                      novo.add(e.key);
                      if (e.key == Permissao.notificacoes) {
                        novo.add(Permissao.estoque);
                      }
                    } else {
                      novo.remove(e.key);
                    }
                    onChanged(novo);
                  }
                : null,
          ),
      ],
    );
  }
}

class _NovoFuncionarioDialog extends StatefulWidget {
  const _NovoFuncionarioDialog();

  @override
  State<_NovoFuncionarioDialog> createState() => _NovoFuncionarioDialogState();
}

class _NovoFuncionarioDialogState extends State<_NovoFuncionarioDialog> {
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  String _papel = Usuario.papelVendas;
  Set<String> _permissoes = {...Permissao.padraoNovoFuncionario};
  bool _salvando = false;
  bool _verSenha = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    final email = _email.text.trim().toLowerCase();
    final senha = _senha.text;
    if (nome.isEmpty || !_emailValido(email) || senha.length < 8) {
      setState(
        () => _erro =
            'Preencha nome, e-mail válido e senha com pelo menos 8 caracteres.',
      );
      return;
    }
    if (Dados.equipe.value.any((u) => u.email.toLowerCase() == email)) {
      setState(() => _erro = 'Este e-mail já está cadastrado.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await UsuarioRepository().criar(
        nome: nome,
        email: email,
        senha: senha,
        papel: _papel,
        permissoes: _papel == Usuario.papelAdmin ? const {} : _permissoes,
        lojaNome: Sessao.instancia.lojaNome,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = mensagemErroConta(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo funcionário'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nome,
                enabled: !_salvando,
                maxLength: 100,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome *'),
              ),
              TextField(
                controller: _email,
                enabled: !_salvando,
                maxLength: 160,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail *'),
              ),
              TextField(
                controller: _senha,
                enabled: !_salvando,
                obscureText: !_verSenha,
                decoration: InputDecoration(
                  labelText: 'Senha *',
                  helperText: 'Pelo menos 8 caracteres. Se a pessoa já usa o '
                      'app em outra loja, a senha dela continua a mesma.',
                  helperMaxLines: 2,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _verSenha ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _verSenha = !_verSenha),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _papel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Nível'),
                items: [
                  for (final e in _niveis.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _salvando
                    ? null
                    : (v) => setState(() => _papel = v ?? _papel),
              ),
              _ListaPermissoes(
                selecionadas: _permissoes,
                habilitado: !_salvando && _papel != Usuario.papelAdmin,
                onChanged: (p) => setState(() => _permissoes = p),
              ),
              Text(
                'O cadastro de funcionários precisa de internet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_erro != null) _MensagemErro(_erro!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _salvando ? null : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_alt_1),
          label: Text(_salvando ? 'Cadastrando...' : 'Cadastrar'),
        ),
      ],
    );
  }
}

bool _emailValido(String e) => _regexEmail.hasMatch(e);

class _AcessosDialog extends StatefulWidget {
  final Usuario usuario;
  const _AcessosDialog({required this.usuario});

  @override
  State<_AcessosDialog> createState() => _AcessosDialogState();
}

class _AcessosDialogState extends State<_AcessosDialog> {
  late final _nome = TextEditingController(text: widget.usuario.nome);
  late String _papel = _souEu ? Usuario.papelAdmin : widget.usuario.papel;
  late Set<String> _permissoes = {...widget.usuario.permissoes};
  bool _salvando = false;
  bool _enviando = false;
  String? _erro;

  bool get _souEu => widget.usuario.id == Sessao.instancia.atual.id;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty || nome.length > 100) {
      setState(() => _erro = 'Informe nome e e-mail válidos.');
      return;
    }
    final antes = widget.usuario;
    final papel = _souEu ? Usuario.papelAdmin : _papel;
    final depois = antes.copyWith(
      nome: nome,
      papel: papel,
      permissoes: papel == Usuario.papelAdmin ? const {} : _permissoes,
    );
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await UsuarioRepository().salvar(
        antes,
        depois,
        equipe: Dados.equipe.value,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = mensagemErroConta(e);
        });
      }
    }
  }

  Future<void> _redefinirSenha() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await UsuarioRepository().enviarRedefinicaoSenha(widget.usuario);
      if (mounted) {
        avisar(
          context,
          'E-mail de redefinição de senha enviado para ${widget.usuario.email}.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErroConta(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ocupado = _salvando || _enviando;
    return AlertDialog(
      title: Text('Editar ${widget.usuario.nome}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nome,
                enabled: !ocupado,
                maxLength: 100,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome *'),
              ),
              TextFormField(
                initialValue: widget.usuario.email,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  helperText: 'O e-mail de acesso não pode ser alterado.',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _papel,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Nível',
                  helperText: _souEu
                      ? 'Você não pode remover o próprio acesso administrativo.'
                      : null,
                  helperMaxLines: 2,
                ),
                items: [
                  for (final e in _niveis.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _souEu || ocupado
                    ? null
                    : (v) => setState(() => _papel = v ?? _papel),
              ),
              const SizedBox(height: 8),
              Text(
                '✓ Vendas   ✓ Retiradas   ✓ Meu ponto',
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.primary,
                ),
              ),
              _ListaPermissoes(
                selecionadas: _permissoes,
                habilitado: !ocupado && _papel != Usuario.papelAdmin,
                onChanged: (p) => setState(() => _permissoes = p),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_reset),
                label: const Text('Enviar e-mail de redefinição de senha'),
                onPressed: ocupado ? null : _redefinirSenha,
              ),
              const SizedBox(height: 4),
              Text(
                'O funcionário recebe um link para criar uma nova senha.',
                style: t.textTheme.bodySmall,
              ),
              if (_erro != null) _MensagemErro(_erro!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: ocupado ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: ocupado ? null : _salvar,
          child: const Text('Salvar acessos'),
        ),
      ],
    );
  }
}

class _MensagemErro extends StatelessWidget {
  final String texto;
  const _MensagemErro(this.texto);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(texto, style: TextStyle(color: c.onErrorContainer)),
    );
  }
}
