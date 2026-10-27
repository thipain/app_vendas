import 'package:flutter/material.dart';

import '../../core/permissoes.dart';
import '../../core/sessao.dart';
import '../../data/dados.dart';
import '../../data/usuario_repository.dart';
import '../../models/usuario.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../inicio/comum.dart';
import 'usuario_dialogs.dart';

/// Equipe e acessos (somente administrador): cadastro de funcionários,
/// nível, módulos liberados e bloqueio de acesso.
class EquipePage extends StatelessWidget {
  const EquipePage({super.key});

  Future<void> _alternar(BuildContext context, Usuario u) async {
    try {
      await UsuarioRepository().salvar(
        u,
        u.copyWith(ativo: !u.ativo),
        equipe: Dados.equipe.value,
      );
      if (context.mounted) avisar(context, 'Status do acesso atualizado.');
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final eu = Sessao.instancia.atual;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => novoFuncionario(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Novo funcionário'),
      ),
      body: ValueListenableBuilder<List<Usuario>>(
        valueListenable: Dados.equipe,
        builder: (context, equipe, _) {
          final lista = [...equipe]
            ..sort(
              (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
            );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              LarguraMaxima(
                largura: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      color: t.colorScheme.secondaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: const Text(
                          'Vendas, Retiradas e Meu ponto ficam '
                          'sempre liberados para todos.',
                        ),
                        subtitle: const Text(
                          'Escolha abaixo os demais módulos de cada funcionário. '
                          'Administradores têm acesso total.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (lista.isEmpty)
                      const EstadoVazio(
                        icone: Icons.groups_outlined,
                        titulo: 'Nenhum funcionário cadastrado',
                      ),
                    for (final u in lista)
                      _CartaoUsuario(
                        usuario: u,
                        souEu: u.id == eu.id,
                        onAcessos: () => editarAcessos(context, u),
                        onAlternar: () => _alternar(context, u),
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
}

class _CartaoUsuario extends StatelessWidget {
  final Usuario usuario;
  final bool souEu;
  final VoidCallback onAcessos;
  final VoidCallback onAlternar;

  const _CartaoUsuario({
    required this.usuario,
    required this.souEu,
    required this.onAcessos,
    required this.onAlternar,
  });

  @override
  Widget build(BuildContext context) {
    final u = usuario;
    final t = Theme.of(context);
    final modulos = u.permissoes.where(Permissao.catalogo.containsKey).length;
    final papel = u.isAdmin
        ? 'Administrador — acesso total'
        : '$modulos módulos liberados';
    final acoes = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Acessos'),
          onPressed: onAcessos,
        ),
        if (!souEu)
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: u.ativo ? t.colorScheme.error : null,
            ),
            icon: Icon(
              u.ativo ? Icons.block : Icons.check_circle_outline,
              size: 18,
            ),
            label: Text(u.ativo ? 'Bloquear' : 'Ativar'),
            onPressed: onAlternar,
          ),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            final info = Row(
              children: [
                CircleAvatar(child: Text(iniciais(u.nome))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              souEu ? '${u.nome} (você)' : u.nome,
                              style: t.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Selo(
                            u.ativo ? 'Ativo' : 'Bloqueado',
                            positivo: u.ativo,
                          ),
                        ],
                      ),
                      Text(u.email, style: t.textTheme.bodySmall),
                      Text(papel, style: t.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            );
            if (c.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: acoes),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: info),
                acoes,
              ],
            );
          },
        ),
      ),
    );
  }
}
