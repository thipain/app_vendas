import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/sessao.dart';
import '../../data/auditoria_repository.dart';
import '../../data/banco.dart';
import '../../data/dados.dart';
import '../../data/sistema_repository.dart';
import '../../data/usuario_repository.dart';
import '../../models/loja.dart';
import '../../models/usuario.dart';
import '../sistema/painel_sistema_page.dart';
import 'app_shell.dart';

/// Depois do login decide o que mostrar: configuração inicial do sistema,
/// escolha da loja, loja/acesso bloqueado ou o sistema da loja escolhida.
class SessaoGate extends StatefulWidget {
  final User conta;
  const SessaoGate({super.key, required this.conta});

  @override
  State<SessaoGate> createState() => _SessaoGateState();
}

/// Uma loja que a pessoa pode abrir.
class _Opcao {
  final String lojaId;
  final String nome;
  final bool bloqueada;
  final bool comoDono;
  const _Opcao(
    this.lojaId,
    this.nome, {
    this.bloqueada = false,
    this.comoDono = false,
  });
}

class _SessaoGateState extends State<SessaoGate> {
  final _repo = SistemaRepository();
  late final Stream<Sistema> _sistema = _repo.watchSistema();
  late final Stream<List<Vinculo>> _vinculos = _repo.watchVinculos(
    widget.conta.uid,
  );
  Stream<List<Loja>>? _todasLojas;

  String get _chavePreferencia => 'ultimaLoja_${widget.conta.uid}';
  String? _escolhida;
  bool _preferenciaLida = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance()
        .then((p) {
          if (!mounted) return;
          setState(() {
            _escolhida = p.getString(_chavePreferencia);
            _preferenciaLida = true;
          });
        })
        .catchError((Object _) {
          if (mounted) setState(() => _preferenciaLida = true);
        });
  }

  @override
  void dispose() {
    Dados.parar();
    Banco.selecionarLoja(null);
    Sessao.instancia.definir(null);
    super.dispose();
  }

  Future<void> _escolher(String? lojaId) async {
    setState(() => _escolhida = lojaId);
    try {
      final p = await SharedPreferences.getInstance();
      if (lojaId == null) {
        await p.remove(_chavePreferencia);
      } else {
        await p.setString(_chavePreferencia, lojaId);
      }
    } catch (_) {
      // Lembrar a loja é só conveniência.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_preferenciaLida) return const _Carregando();
    return StreamBuilder<Sistema>(
      stream: _sistema,
      builder: (context, snapSistema) {
        if (snapSistema.hasError) {
          return _Aviso.erro(snapSistema.error!);
        }
        final sistema = snapSistema.data;
        if (sistema == null) return const _Carregando();
        if (!sistema.existe) {
          return _PrimeiroAcesso(
            conta: widget.conta,
            onConcluido: (id) => _escolher(id),
          );
        }
        final dono = sistema.isDono(widget.conta.uid);
        if (dono) _todasLojas ??= _repo.watchLojas();
        return StreamBuilder<List<Vinculo>>(
          stream: _vinculos,
          builder: (context, snapVinculos) {
            if (snapVinculos.hasError) return _Aviso.erro(snapVinculos.error!);
            final vinculos = snapVinculos.data;
            if (vinculos == null) return const _Carregando();
            if (!dono) return _resolver(sistema, vinculos, const [], dono);
            return StreamBuilder<List<Loja>>(
              stream: _todasLojas,
              builder: (context, snapLojas) {
                if (snapLojas.hasError) return _Aviso.erro(snapLojas.error!);
                if (!snapLojas.hasData) return const _Carregando();
                return _resolver(sistema, vinculos, snapLojas.data!, dono);
              },
            );
          },
        );
      },
    );
  }

  Widget _resolver(
    Sistema sistema,
    List<Vinculo> vinculos,
    List<Loja> lojas,
    bool dono,
  ) {
    final opcoes = <String, _Opcao>{};
    for (final l in lojas) {
      opcoes[l.id] = _Opcao(l.id, l.nome, bloqueada: !l.ativa, comoDono: true);
    }
    for (final v in vinculos.where((v) => v.ativo)) {
      opcoes[v.lojaId] = _Opcao(
        v.lojaId,
        v.lojaNome,
        bloqueada: opcoes[v.lojaId]?.bloqueada ?? false,
      );
    }
    final lista = opcoes.values.toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    if (lista.isEmpty) {
      if (dono) return const PainelSistemaPage(semLojas: true);
      return const _Aviso(
        icone: Icons.person_off_outlined,
        titulo: 'Conta sem acesso',
        mensagem:
            'Seu e-mail não está cadastrado na equipe de nenhuma loja. '
            'Peça ao administrador da loja para liberar seu acesso.',
      );
    }

    var escolhida = opcoes[_escolhida];
    if (escolhida == null && lista.length == 1 && !dono) {
      escolhida = lista.first;
    }
    if (escolhida == null) {
      return _SeletorLoja(opcoes: lista, dono: dono, onEscolher: _escolher);
    }
    final podeTrocar = lista.length > 1 || dono;
    return _LojaAberta(
      key: ValueKey(escolhida.lojaId),
      conta: widget.conta,
      lojaId: escolhida.lojaId,
      dono: dono,
      trocarLoja: podeTrocar ? () => _escolher(null) : null,
    );
  }
}

/// Sistema de uma loja: confere o vínculo da pessoa e se a loja está ativa.
class _LojaAberta extends StatefulWidget {
  final User conta;
  final String lojaId;
  final bool dono;
  final VoidCallback? trocarLoja;

  const _LojaAberta({
    super.key,
    required this.conta,
    required this.lojaId,
    required this.dono,
    required this.trocarLoja,
  });

  @override
  State<_LojaAberta> createState() => _LojaAbertaState();
}

class _LojaAbertaState extends State<_LojaAberta> {
  late final Stream<Loja?> _loja;
  late final Stream<Usuario?> _perfil;
  bool _dadosIniciados = false;

  @override
  void initState() {
    super.initState();
    Banco.selecionarLoja(widget.lojaId);
    _loja = SistemaRepository().watchLoja(widget.lojaId);
    _perfil = UsuarioRepository().watch(widget.conta.uid);
  }

  @override
  void dispose() {
    Dados.parar();
    Sessao.instancia.definir(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trocar = widget.trocarLoja;
    return StreamBuilder<Loja?>(
      stream: _loja,
      builder: (context, snapLoja) {
        if (snapLoja.hasError) {
          return _Aviso.erro(snapLoja.error!, trocarLoja: trocar);
        }
        if (!snapLoja.hasData &&
            snapLoja.connectionState == ConnectionState.waiting) {
          return const _Carregando();
        }
        final loja = snapLoja.data;
        if (loja == null) {
          return _Aviso(
            icone: Icons.store_mall_directory_outlined,
            titulo: 'Loja não encontrada',
            mensagem: 'Esta loja não existe mais.',
            trocarLoja: trocar,
          );
        }
        if (!loja.ativa && !widget.dono) {
          return _Aviso(
            icone: Icons.store_outlined,
            titulo: 'Loja bloqueada',
            mensagem:
                'O acesso à ${loja.nome} está suspenso. '
                'Entre em contato com o suporte do sistema.',
            trocarLoja: trocar,
          );
        }
        return StreamBuilder<Usuario?>(
          stream: _perfil,
          builder: (context, snap) {
            if (snap.hasError) {
              return _Aviso.erro(snap.error!, trocarLoja: trocar);
            }
            if (!snap.hasData &&
                snap.connectionState == ConnectionState.waiting) {
              return const _Carregando();
            }
            var usuario = snap.data;
            // O dono do sistema entra em qualquer loja como administrador.
            if (usuario == null && widget.dono) {
              usuario = Usuario(
                id: widget.conta.uid,
                nome: 'Suporte do sistema',
                email: widget.conta.email ?? '',
                papel: Usuario.papelAdmin,
              );
            }
            if (usuario == null) {
              return _Aviso(
                icone: Icons.person_off_outlined,
                titulo: 'Sem acesso a esta loja',
                mensagem:
                    'Seu e-mail não está cadastrado na equipe da '
                    '${loja.nome}.',
                trocarLoja: trocar,
              );
            }
            if (!usuario.ativo) {
              return _Aviso(
                icone: Icons.block,
                titulo: 'Acesso bloqueado',
                mensagem:
                    'Seu acesso à ${loja.nome} foi bloqueado pelo '
                    'administrador.',
                trocarLoja: trocar,
              );
            }
            final sessao = Sessao.instancia
              ..lojaNome = loja.nome
              ..isDono = widget.dono
              ..trocarLoja = trocar;
            sessao.definir(usuario);
            if (!_dadosIniciados) {
              _dadosIniciados = true;
              Dados.iniciar();
              AuditoriaRepository.registrar('auth.login', 'Acesso ao sistema');
            }
            // Recria o shell quando papel ou permissões mudam, para refazer o
            // menu.
            final permissoes = usuario.permissoes.toList()..sort();
            return AppShell(
              key: ValueKey('${usuario.papel}|${permissoes.join(',')}'),
            );
          },
        );
      },
    );
  }
}

class _SeletorLoja extends StatelessWidget {
  final List<_Opcao> opcoes;
  final bool dono;
  final ValueChanged<String> onEscolher;

  const _SeletorLoja({
    required this.opcoes,
    required this.dono,
    required this.onEscolher,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escolha a loja'),
        actions: [
          if (dono)
            TextButton.icon(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Painel do sistema'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PainelSistemaPage()),
              ),
            ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final o in opcoes)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        o.nome.isEmpty
                            ? '?'
                            : o.nome.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(o.nome),
                    subtitle: Text(
                      [
                        if (o.bloqueada) 'Bloqueada',
                        if (o.comoDono) 'Acesso de dono do sistema',
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !o.bloqueada || dono,
                    textColor: o.bloqueada ? t.colorScheme.error : null,
                    onTap: () => onEscolher(o.lojaId),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Carregando extends StatelessWidget {
  const _Carregando();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String mensagem;
  final VoidCallback? trocarLoja;

  const _Aviso({
    required this.icone,
    required this.titulo,
    required this.mensagem,
    this.trocarLoja,
  });

  factory _Aviso.erro(Object erro, {VoidCallback? trocarLoja}) => _Aviso(
    icone: Icons.cloud_off,
    titulo: 'Não foi possível carregar seus dados',
    mensagem: '$erro',
    trocarLoja: trocarLoja,
  );

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
              if (trocarLoja != null)
                FilledButton(
                  onPressed: trocarLoja,
                  child: const Text('Trocar de loja'),
                ),
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

/// Primeiro acesso de uma instalação nova: cria a primeira loja e torna a
/// conta logada dona do sistema e administradora da loja.
class _PrimeiroAcesso extends StatefulWidget {
  final User conta;
  final ValueChanged<String> onConcluido;
  const _PrimeiroAcesso({required this.conta, required this.onConcluido});

  @override
  State<_PrimeiroAcesso> createState() => _PrimeiroAcessoState();
}

class _PrimeiroAcessoState extends State<_PrimeiroAcesso> {
  final _loja = TextEditingController();
  final _nome = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _loja.dispose();
    _nome.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_loja.text.trim().isEmpty || _nome.text.trim().isEmpty) {
      setState(() => _erro = 'Informe o nome da loja e o seu nome');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final id = await SistemaRepository().configurarSistema(
        nomeLoja: _loja.text,
        nome: _nome.text,
      );
      widget.onConcluido(id);
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
                Text(
                  'Configuração inicial',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Este é o primeiro acesso ao sistema. A conta '
                  '${widget.conta.email} será a dona do sistema (cadastra as '
                  'lojas) e a administradora da primeira loja.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _loja,
                  decoration: const InputDecoration(
                    labelText: 'Nome da primeira loja',
                  ),
                ),
                const SizedBox(height: 12),
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
