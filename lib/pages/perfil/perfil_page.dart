import 'package:flutter/material.dart';

import '../../core/permissoes.dart';
import '../../core/regra_exception.dart';
import '../../core/sessao.dart';
import '../../data/usuario_repository.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../equipe/usuario_dialogs.dart';
import '../inicio/comum.dart';

/// Meu perfil: nome exibido e troca da própria senha. Nível e permissões só
/// podem ser alterados pelo administrador.
class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final _nome = TextEditingController(text: Sessao.instancia.atual.nome);
  final _senhaAtual = TextEditingController();
  final _novaSenha = TextEditingController();
  final _confirmacao = TextEditingController();
  bool _trocandoSenha = false;
  bool _verSenhas = false;

  @override
  void dispose() {
    _nome.dispose();
    _senhaAtual.dispose();
    _novaSenha.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  void _salvarNome() {
    final eu = Sessao.instancia.atual;
    final nome = _nome.text.trim();
    if (nome.isEmpty || nome.length > 100) {
      mostrarErro(context, const RegraException('Informe um nome válido.'));
      return;
    }
    if (nome == eu.nome) {
      avisar(context, 'Perfil atualizado.');
      return;
    }
    executar(
      context,
      () => UsuarioRepository().alterarMeuNome(eu, nome),
      sucesso: 'Perfil atualizado.',
    );
  }

  Future<void> _trocarSenha() async {
    final atual = _senhaAtual.text;
    final nova = _novaSenha.text;
    if (atual.isEmpty) {
      mostrarErro(context, const RegraException('Informe a senha atual.'));
      return;
    }
    if (nova.length < 8) {
      mostrarErro(
        context,
        const RegraException('A nova senha deve ter pelo menos 8 caracteres.'),
      );
      return;
    }
    if (nova != _confirmacao.text) {
      mostrarErro(
        context,
        const RegraException('A confirmação não confere com a nova senha.'),
      );
      return;
    }
    setState(() => _trocandoSenha = true);
    try {
      await UsuarioRepository().alterarMinhaSenha(atual, nova);
      if (!mounted) return;
      _senhaAtual.clear();
      _novaSenha.clear();
      _confirmacao.clear();
      avisar(context, 'Senha alterada com sucesso.');
    } catch (e) {
      if (mounted) mostrarErro(context, RegraException(mensagemErroConta(e)));
    } finally {
      if (mounted) setState(() => _trocandoSenha = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: ListenableBuilder(
        listenable: Sessao.instancia,
        builder: (context, _) {
          final eu = Sessao.instancia.atual;
          final modulos = eu.isAdmin
              ? 'Acesso total'
              : [
                  'Vendas',
                  'Retiradas',
                  'Meu ponto',
                  for (final e in Permissao.catalogo.entries)
                    if (eu.permissoes.contains(e.key)) e.value,
                ].join(', ');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LarguraMaxima(
                largura: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          radius: 26,
                          child: Text(iniciais(eu.nome)),
                        ),
                        title: Text(eu.nome, style: t.textTheme.titleMedium),
                        subtitle: Text(
                          '${eu.email}\n${eu.isAdmin ? 'Administrador' : 'Acesso personalizado'}',
                        ),
                        isThreeLine: true,
                      ),
                    ),
                    const TituloSecao('Dados pessoais'),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _nome,
                              maxLength: 100,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nome *',
                              ),
                            ),
                            TextFormField(
                              key: ValueKey(eu.email),
                              initialValue: eu.email,
                              enabled: false,
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                                helperText:
                                    'O e-mail de acesso não pode ser alterado.',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: ValueKey(eu.papel),
                              initialValue: eu.isAdmin
                                  ? 'Administrador'
                                  : 'Funcionário com acessos personalizados',
                              enabled: false,
                              decoration: const InputDecoration(
                                labelText: 'Nível',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Módulos: $modulos',
                              style: t.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: _salvarNome,
                                child: const Text('Salvar perfil'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const TituloSecao('Alterar senha'),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _campoSenha(_senhaAtual, 'Senha atual'),
                            const SizedBox(height: 12),
                            _campoSenha(
                              _novaSenha,
                              'Nova senha',
                              ajuda: 'Pelo menos 8 caracteres',
                            ),
                            const SizedBox(height: 12),
                            _campoSenha(_confirmacao, 'Confirme a nova senha'),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _verSenhas,
                              title: const Text('Mostrar senhas'),
                              onChanged: (v) =>
                                  setState(() => _verSenhas = v ?? false),
                            ),
                            Text(
                              'A troca de senha precisa de internet.',
                              style: t.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _trocandoSenha ? null : _trocarSenha,
                                icon: _trocandoSenha
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.lock_outline),
                                label: const Text('Alterar senha'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _campoSenha(TextEditingController c, String rotulo, {String? ajuda}) =>
      TextField(
        controller: c,
        enabled: !_trocandoSenha,
        obscureText: !_verSenhas,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: rotulo, helperText: ajuda),
      );
}
