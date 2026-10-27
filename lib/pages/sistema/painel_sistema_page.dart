import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/mensagens.dart';

/// Área do dono do sistema: cadastra lojas (clientes) e seus
/// administradores, bloqueia/libera lojas e migra os dados da versão antiga.
class PainelSistemaPage extends StatefulWidget {
  /// true quando o dono ainda não tem nenhuma loja (tela inicial).
  final bool semLojas;
  const PainelSistemaPage({super.key, this.semLojas = false});

  @override
  State<PainelSistemaPage> createState() => _PainelSistemaPageState();
}

class _PainelSistemaPageState extends State<PainelSistemaPage> {
  final _repo = SistemaRepository();
  late final Stream<List<Loja>> _lojas = _repo.watchLojas();
  late final Stream<Sistema> _sistema = _repo.watchSistema();
  Future<bool>? _temDadosAntigos;

  Future<void> _novaLoja() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogAdministrador(
        titulo: 'Nova loja',
        pedirNomeLoja: true,
        executar: (loja, nome, email, senha) => _repo.criarLoja(
          nomeLoja: loja,
          nomeAdmin: nome,
          emailAdmin: email,
          senhaAdmin: senha,
        ),
      ),
    );
    if (ok == true && mounted) {
      avisar(
        context,
        'Loja cadastrada. O administrador já pode entrar no app.',
      );
    }
  }

  Future<void> _adicionarAdmin(Loja loja) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogAdministrador(
        titulo: 'Administrador da ${loja.nome}',
        pedirNomeLoja: false,
        executar: (_, nome, email, senha) => _repo.adicionarAdministrador(
          loja,
          nome: nome,
          email: email,
          senha: senha,
        ),
      ),
    );
    if (ok == true && mounted) avisar(context, 'Administrador adicionado.');
  }

  Future<void> _renomear(Loja loja) async {
    final nome = await pedirTexto(
      context,
      titulo: 'Renomear loja',
      rotulo: 'Nome da loja',
      inicial: loja.nome,
      minimo: 1,
      maximo: 120,
    );
    if (nome == null || !mounted) return;
    await _rodar(() => _repo.renomearLoja(loja, nome), 'Loja renomeada.');
  }

  Future<void> _alternarBloqueio(Loja loja) async {
    final bloquear = loja.ativa;
    final ok = await confirmar(
      context,
      titulo: bloquear ? 'Bloquear loja' : 'Liberar loja',
      mensagem: bloquear
          ? 'Ninguém da equipe da ${loja.nome} conseguirá entrar no app até '
                'você liberar novamente. Os dados são mantidos.'
          : 'A equipe da ${loja.nome} voltará a ter acesso ao app.',
      confirmarTexto: bloquear ? 'Bloquear' : 'Liberar',
    );
    if (!ok || !mounted) return;
    await _rodar(
      () => _repo.definirAtiva(loja, !bloquear),
      bloquear ? 'Loja bloqueada.' : 'Loja liberada.',
    );
  }

  Future<void> _rodar(Future<void> Function() acao, String sucesso) async {
    try {
      await acao();
      if (mounted) avisar(context, sucesso);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  Future<void> _migrar() async {
    final sugestao = await _repo.nomeLojaAntiga();
    if (!mounted) return;
    final nome = await pedirTexto(
      context,
      titulo: 'Migrar dados da versão anterior',
      rotulo: 'Nome da loja que receberá os dados',
      inicial: sugestao,
      minimo: 1,
      maximo: 120,
      confirmar: 'Migrar',
      ajuda:
          'Produtos, vendas, caixa, equipe e configurações atuais serão '
          'copiados para esta loja.',
    );
    if (nome == null || !mounted) return;
    final etapa = ValueNotifier<String>('Preparando...');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: etapa,
            builder: (_, e, _) => Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(child: Text(e)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await _repo.migrarDadosAntigos(nome, progresso: (e) => etapa.value = e);
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() => _temDadosAntigos = Future.value(false));
      avisar(context, 'Dados migrados para a loja $nome.');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do sistema'),
        actions: [
          if (widget.semLojas)
            IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novaLoja,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nova loja'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: StreamBuilder<List<Loja>>(
            stream: _lojas,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final lojas = snap.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Text(
                    'Cada loja tem seus próprios produtos, vendas, caixa, '
                    'equipe e configurações. O administrador da loja cadastra '
                    'a própria equipe dentro do app.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<Sistema>(
                    stream: _sistema,
                    builder: (context, s) {
                      if (!s.hasData) return const SizedBox.shrink();
                      _temDadosAntigos ??= _repo
                          .temDadosAntigos(s.data!)
                          .catchError((Object _) => false);
                      return FutureBuilder<bool>(
                        future: _temDadosAntigos,
                        builder: (context, t) => t.data == true
                            ? Card(
                                color: Theme.of(context)
                                    .colorScheme
                                    .tertiaryContainer,
                                child: ListTile(
                                  leading: const Icon(Icons.move_down),
                                  title: const Text(
                                    'Dados da versão anterior encontrados',
                                  ),
                                  subtitle: const Text(
                                    'Copie os produtos, vendas e equipe já '
                                    'cadastrados para uma loja.',
                                  ),
                                  trailing: FilledButton(
                                    onPressed: _migrar,
                                    child: const Text('Migrar'),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      );
                    },
                  ),
                  if (lojas.isEmpty)
                    const EstadoVazio(
                      icone: Icons.storefront_outlined,
                      titulo: 'Nenhuma loja cadastrada',
                      mensagem:
                          'Toque em "Nova loja" para cadastrar o '
                          'primeiro cliente.',
                    ),
                  for (final l in lojas)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            l.nome.isEmpty
                                ? '?'
                                : l.nome.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(l.nome),
                        subtitle: Text(
                          [
                            l.ativa ? 'Ativa' : 'Bloqueada',
                            if (l.criadaEm != null)
                              'desde ${f.format(l.criadaEm!)}',
                          ].join(' · '),
                        ),
                        textColor: l.ativa
                            ? null
                            : Theme.of(context).colorScheme.error,
                        trailing: PopupMenuButton<String>(
                          onSelected: (op) => switch (op) {
                            'admin' => _adicionarAdmin(l),
                            'renomear' => _renomear(l),
                            _ => _alternarBloqueio(l),
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'admin',
                              child: Text('Adicionar administrador'),
                            ),
                            const PopupMenuItem(
                              value: 'renomear',
                              child: Text('Renomear'),
                            ),
                            PopupMenuItem(
                              value: 'bloqueio',
                              child: Text(l.ativa ? 'Bloquear' : 'Liberar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Cadastro de administrador (e da loja, quando [pedirNomeLoja]).
class _DialogAdministrador extends StatefulWidget {
  final String titulo;
  final bool pedirNomeLoja;
  final Future<Object?> Function(
    String loja,
    String nome,
    String email,
    String senha,
  )
  executar;

  const _DialogAdministrador({
    required this.titulo,
    required this.pedirNomeLoja,
    required this.executar,
  });

  @override
  State<_DialogAdministrador> createState() => _DialogAdministradorState();
}

class _DialogAdministradorState extends State<_DialogAdministrador> {
  final _form = GlobalKey<FormState>();
  final _loja = TextEditingController();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _loja.dispose();
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
      await widget.executar(
        _loja.text.trim(),
        _nome.text.trim(),
        _email.text.trim(),
        _senha.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _salvando = false;
        _erro = switch (e.code) {
          'email-already-in-use' =>
            'Este e-mail já tem conta, mas não está vinculado a nenhuma loja '
                'por este app. Use outro e-mail.',
          'invalid-email' => 'E-mail inválido.',
          'weak-password' => 'Senha fraca: use pelo menos 8 caracteres.',
          'network-request-failed' =>
            'Sem internet. Cadastrar lojas precisa de conexão.',
          _ => 'Não foi possível cadastrar (${e.code}).',
        };
      });
    } catch (e) {
      setState(() {
        _salvando = false;
        _erro = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.pedirNomeLoja) ...[
                  TextFormField(
                    controller: _loja,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Nome da loja',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Administrador da loja',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  controller: _nome,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  validator: (v) =>
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch((v ?? '').trim())
                      ? null
                      : 'Informe um e-mail válido',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _senha,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha inicial',
                    helperText:
                        'Se a pessoa já usa o app em outra loja, a '
                        'senha dela continua a mesma.',
                    helperMaxLines: 2,
                  ),
                  validator: (v) => (v ?? '').length < 8
                      ? 'Use pelo menos 8 caracteres'
                      : null,
                ),
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
