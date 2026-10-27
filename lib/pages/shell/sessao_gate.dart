import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/sessao.dart';
import '../../data/auditoria_repository.dart';
import '../../data/dados.dart';
import '../../data/usuario_repository.dart';
import '../../models/usuario.dart';
import 'app_shell.dart';

/// Depois do login, carrega o perfil da equipe do usuário e decide o que
/// mostrar: configuração inicial, acesso bloqueado ou o sistema.
class SessaoGate extends StatefulWidget {
  final User conta;
  const SessaoGate({super.key, required this.conta});

  @override
  State<SessaoGate> createState() => _SessaoGateState();
}

class _SessaoGateState extends State<SessaoGate> {
  late final Stream<Usuario?> _perfil =
      UsuarioRepository().watch(widget.conta.uid);
  Future<bool>? _precisaSetup;
  bool _dadosIniciados = false;

  @override
  void dispose() {
    Dados.parar();
    Sessao.instancia.definir(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Usuario?>(
      stream: _perfil,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Aviso(
            icone: Icons.cloud_off,
            titulo: 'Não foi possível carregar seu perfil',
            mensagem: '${snap.error}',
          );
        }
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final usuario = snap.data;
        if (usuario == null) {
          _precisaSetup ??= UsuarioRepository().precisaConfiguracaoInicial();
          return FutureBuilder<bool>(
            future: _precisaSetup,
            builder: (context, s) {
              if (s.hasError) {
                return _Aviso(
                  icone: Icons.wifi_off,
                  titulo: 'Sem conexão',
                  mensagem: 'O primeiro acesso precisa de internet.',
                  tentarNovamente: () =>
                      setState(() => _precisaSetup = null),
                );
              }
              if (!s.hasData) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              return s.data!
                  ? _PrimeiroAcesso(conta: widget.conta)
                  : const _Aviso(
                      icone: Icons.person_off_outlined,
                      titulo: 'Conta sem acesso',
                      mensagem: 'Seu e-mail não está cadastrado na equipe. '
                          'Peça ao administrador para liberar seu acesso.',
                    );
            },
          );
        }
        if (!usuario.ativo) {
          return const _Aviso(
            icone: Icons.block,
            titulo: 'Acesso bloqueado',
            mensagem: 'Seu acesso foi bloqueado pelo administrador.',
          );
        }
        Sessao.instancia.definir(usuario);
        if (!_dadosIniciados) {
          _dadosIniciados = true;
          Dados.iniciar();
          AuditoriaRepository.registrar('auth.login', 'Acesso ao sistema');
        }
        // Recria o shell quando papel ou permissões mudam, para refazer o menu.
        final permissoes = usuario.permissoes.toList()..sort();
        return AppShell(
            key: ValueKey('${usuario.papel}|${permissoes.join(',')}'));
      },
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String mensagem;
  final VoidCallback? tentarNovamente;

  const _Aviso({
    required this.icone,
    required this.titulo,
    required this.mensagem,
    this.tentarNovamente,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 56),
              const SizedBox(height: 16),
              Text(titulo, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(mensagem, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (tentarNovamente != null)
                FilledButton(
                    onPressed: tentarNovamente,
                    child: const Text('Tentar novamente')),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Sair'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primeiro acesso ao sistema: a conta logada vira o administrador.
class _PrimeiroAcesso extends StatefulWidget {
  final User conta;
  const _PrimeiroAcesso({required this.conta});

  @override
  State<_PrimeiroAcesso> createState() => _PrimeiroAcessoState();
}

class _PrimeiroAcessoState extends State<_PrimeiroAcesso> {
  final _nome = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_nome.text.trim().isEmpty) {
      setState(() => _erro = 'Informe seu nome');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await UsuarioRepository().configurarPrimeiroAdmin(_nome.text.trim());
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível concluir: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 56),
                const SizedBox(height: 16),
                Text('Configuração inicial',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Este é o primeiro acesso ao sistema. A conta '
                  '${widget.conta.email} será o administrador, com acesso '
                  'total e permissão para cadastrar a equipe.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nome,
                  decoration: InputDecoration(
                    labelText: 'Seu nome',
                    errorText: _erro,
                  ),
                  onSubmitted: (_) => _salvar(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _salvando ? null : _salvar,
                  child: Text(_salvando ? 'Salvando...' : 'Começar'),
                ),
                TextButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
