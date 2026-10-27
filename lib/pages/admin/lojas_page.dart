import 'package:flutter/material.dart';

import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import 'admin_comum.dart';
import 'loja_form_page.dart';

enum _Filtro {
  todas('Todas'),
  emDia('Em dia'),
  vencendo('Vencendo'),
  atrasadas('Atrasadas'),
  travadas('Travadas'),
  emTeste('Em teste'),
  semCobranca('Sem cobrança');

  final String rotulo;
  const _Filtro(this.rotulo);

  bool aceita(SituacaoLoja s) => switch (this) {
    todas => true,
    emDia => s == SituacaoLoja.emDia,
    vencendo => s == SituacaoLoja.vencendo,
    atrasadas => s == SituacaoLoja.atrasada,
    travadas => s.travada,
    emTeste => s == SituacaoLoja.emTeste,
    semCobranca => s == SituacaoLoja.semCobranca,
  };
}

/// Lista das lojas (clientes), com busca, filtro por situação, cadastro de
/// novas lojas e migração dos dados da versão anterior.
class LojasPage extends StatefulWidget {
  final ValueChanged<String> onEntrarLoja;

  const LojasPage({super.key, required this.onEntrarLoja});

  @override
  State<LojasPage> createState() => _LojasPageState();
}

class _LojasPageState extends State<LojasPage> {
  final _repo = SistemaRepository();
  late final Stream<List<Loja>> _lojas = _repo.watchLojas();
  late final Stream<Sistema> _sistema = _repo.watchSistema();
  Future<bool>? _temDadosAntigos;
  String _busca = '';
  _Filtro _filtro = _Filtro.todas;

  Future<void> _novaLoja() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const LojaFormPage()));
    if (ok == true && mounted) {
      avisar(
        context,
        'Loja cadastrada. O administrador já pode entrar no app.',
      );
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
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
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
      nav.pop();
      if (!mounted) return;
      setState(() => _temDadosAntigos = Future.value(false));
      avisar(context, 'Dados migrados para a loja $nome.');
    } catch (e) {
      nav.pop();
      if (mounted) mostrarErro(context, e);
    } finally {
      etapa.dispose();
    }
  }

  Widget _bannerMigracao() => StreamBuilder<Sistema>(
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
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.move_down),
                  title: const Text('Dados da versão anterior encontrados'),
                  subtitle: const Text(
                    'Copie os produtos, vendas e equipe já cadastrados para '
                    'uma loja.',
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
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novaLoja,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nova loja'),
      ),
      body: LarguraMaxima(
        largura: 900,
        child: StreamBuilder<List<Loja>>(
          stream: _lojas,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Erro: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final agora = DateTime.now();
            final lojas = snap.data!;
            final sit = {for (final l in lojas) l.id: l.situacao(agora)};
            final busca = _busca.toLowerCase();
            final visiveis = lojas.where((l) {
              if (!_filtro.aceita(sit[l.id]!)) return false;
              if (busca.isEmpty) return true;
              return [
                l.nome,
                l.responsavelNome,
                l.responsavelEmail,
                l.responsavelTelefone,
                l.documento,
              ].any((c) => c.toLowerCase().contains(busca));
            }).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _bannerMigracao(),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText:
                        'Buscar por loja, responsável, e-mail, telefone...',
                  ),
                  onChanged: (v) => setState(() => _busca = v.trim()),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _Filtro.values)
                      ChoiceChip(
                        label: Text(
                          '${f.rotulo} '
                          '(${lojas.where((l) => f.aceita(sit[l.id]!)).length})',
                        ),
                        selected: _filtro == f,
                        onSelected: (_) => setState(() => _filtro = f),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (lojas.isEmpty)
                  const EstadoVazio(
                    icone: Icons.storefront_outlined,
                    titulo: 'Nenhuma loja cadastrada',
                    mensagem:
                        'Toque em "Nova loja" para cadastrar o primeiro '
                        'cliente.',
                  )
                else if (visiveis.isEmpty)
                  const EstadoVazio(
                    icone: Icons.search_off,
                    titulo: 'Nenhuma loja encontrada',
                  ),
                for (final l in visiveis)
                  Card(
                    child: ListTile(
                      onTap: () => abrirLoja(context, l, widget.onEntrarLoja),
                      leading: CircleAvatar(
                        child: Text(
                          l.nome.isEmpty
                              ? '?'
                              : l.nome.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [Text(l.nome), SeloSituacao(sit[l.id]!)],
                      ),
                      subtitle: Text(
                        [
                          if (l.responsavelNome.isNotEmpty) l.responsavelNome,
                          resumoCobranca(l),
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
