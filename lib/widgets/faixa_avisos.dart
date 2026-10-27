import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/formatters.dart';
import '../core/sessao.dart';
import '../data/sistema_repository.dart';
import '../models/loja.dart';

/// Faixas no topo do app da loja: cobrança da mensalidade (vencendo, em
/// carência, fim do teste) e avisos publicados pelo dono do sistema.
class FaixaAvisos extends StatefulWidget {
  const FaixaAvisos({super.key});

  @override
  State<FaixaAvisos> createState() => _FaixaAvisosState();
}

class _FaixaAvisosState extends State<FaixaAvisos> {
  /// Avisos fechados nesta sessão (voltam a aparecer ao abrir o app).
  static final _fechados = <String>{};

  late final Stream<List<Aviso>> _avisos = SistemaRepository().watchAvisos(
    somenteAtivos: true,
  );

  String? _cobranca(Loja loja) {
    final f = DateFormat('dd/MM/yyyy');
    final dias = loja.diasParaVencer() ?? 0;
    final admin = Sessao.instancia.isAdmin;
    final quando = dias <= 0
        ? 'hoje'
        : dias == 1
        ? 'amanhã'
        : 'em $dias dias';
    return switch (loja.situacao()) {
      SituacaoLoja.emTeste when admin && dias <= 3 =>
        'Seu período de teste termina $quando (${f.format(loja.pagoAte!)}). '
            'Fale com o suporte para continuar usando o sistema.',
      SituacaoLoja.vencendo when admin =>
        'A mensalidade${loja.valorMensal > 0 ? ' de ${formatarMoeda(loja.valorMensal)}' : ''} '
            'vence $quando (${f.format(loja.pagoAte!)}).',
      SituacaoLoja.atrasada =>
        'Mensalidade vencida em ${f.format(loja.pagoAte!)}. O acesso será '
            'suspenso em ${f.format(loja.travaEm!)}. '
            '${admin ? 'Regularize com o suporte do sistema.' : 'Avise o administrador da loja.'}',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final loja = Sessao.instancia.loja;
    final cobranca = loja == null ? null : _cobranca(loja);
    final atrasada = loja?.situacao() == SituacaoLoja.atrasada;
    return StreamBuilder<List<Aviso>>(
      stream: _avisos,
      builder: (context, snap) {
        final avisos = (snap.data ?? const <Aviso>[])
            .where(
              (a) =>
                  (a.lojaId == null || a.lojaId == loja?.id) &&
                  !_fechados.contains(a.id),
            )
            .toList();
        if (cobranca == null && avisos.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cobranca != null)
              _Faixa(
                icone: atrasada ? Icons.warning_amber : Icons.event,
                cor: atrasada ? cores.errorContainer : cores.tertiaryContainer,
                texto: cobranca,
              ),
            for (final a in avisos)
              _Faixa(
                icone: Icons.campaign_outlined,
                cor: cores.secondaryContainer,
                titulo: a.titulo,
                texto: a.mensagem,
                onFechar: () => setState(() => _fechados.add(a.id)),
              ),
          ],
        );
      },
    );
  }
}

class _Faixa extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String? titulo;
  final String texto;
  final VoidCallback? onFechar;

  const _Faixa({
    required this.icone,
    required this.cor,
    this.titulo,
    required this.texto,
    this.onFechar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(icone, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (titulo != null)
                      TextSpan(
                        text: '$titulo  ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    TextSpan(text: texto),
                  ],
                ),
              ),
            ),
            if (onFechar != null)
              IconButton(
                tooltip: 'Fechar',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onFechar,
              ),
          ],
        ),
      ),
    );
  }
}
