import '../core/dinheiro.dart';
import 'pedido.dart';

/// Linha de agrupamento (canal, bairro, motoboy, forma de pagamento).
class GrupoDelivery {
  final String nome;
  int pedidos = 0;
  int totalCentavos = 0;

  /// Soma dos minutos de entrega (saiu → entregue) e quantos têm a medida.
  int _minutosEntrega = 0;
  int _medidasEntrega = 0;

  GrupoDelivery(this.nome);

  double get total => deCentavos(totalCentavos);

  /// Tempo médio de entrega em minutos (null = sem medida).
  double? get mediaEntrega =>
      _medidasEntrega == 0 ? null : _minutosEntrega / _medidasEntrega;
}

/// Números do delivery num período, a partir dos pedidos registrados nele.
class ResumoDelivery {
  /// Pedidos registrados no período (todas as etapas).
  final int registrados;
  final int concluidos;
  final int cancelados;

  /// Pedidos da loja online recusados pela loja.
  final int recusadosOnline;
  final int faturamentoCentavos;
  final int taxasCentavos;
  final int descontosCentavos;

  /// Médias em minutos (null = sem pedidos com a medida).
  final double? mediaPreparo;
  final double? mediaEntrega;
  final double? mediaTotal;

  final List<GrupoDelivery> canais;
  final List<GrupoDelivery> bairros;
  final List<GrupoDelivery> motoboys;
  final List<GrupoDelivery> formas;

  const ResumoDelivery._({
    required this.registrados,
    required this.concluidos,
    required this.cancelados,
    required this.recusadosOnline,
    required this.faturamentoCentavos,
    required this.taxasCentavos,
    required this.descontosCentavos,
    required this.mediaPreparo,
    required this.mediaEntrega,
    required this.mediaTotal,
    required this.canais,
    required this.bairros,
    required this.motoboys,
    required this.formas,
  });

  double get faturamento => deCentavos(faturamentoCentavos);
  double get taxas => deCentavos(taxasCentavos);
  double get descontos => deCentavos(descontosCentavos);
  double get ticketMedio =>
      concluidos == 0 ? 0 : deCentavos(faturamentoCentavos ~/ concluidos);

  /// Bairro sem a cidade ("Centro - Itu/SP" → "Centro"), para agrupar.
  static String bairroBase(String bairro) {
    final b = bairro.split(' - ').first.trim();
    if (b.isEmpty) return 'Sem bairro';
    return b
        .split(RegExp(r'\s+'))
        .map(
          (p) => p.isEmpty
              ? p
              : '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static int? _minutos(DateTime? de, DateTime? ate) {
    if (de == null || ate == null) return null;
    final m = ate.difference(de).inMinutes;
    // Descarta medidas impossíveis (relógio errado, pedido esquecido aberto).
    return m < 0 || m > 24 * 60 ? null : m;
  }

  factory ResumoDelivery.de(List<Pedido> pedidos, {int recusadosOnline = 0}) {
    var concluidos = 0, cancelados = 0;
    var faturamento = 0, taxas = 0, descontos = 0;
    var somaPreparo = 0, nPreparo = 0;
    var somaEntrega = 0, nEntrega = 0;
    var somaTotal = 0, nTotal = 0;
    final canais = <String, GrupoDelivery>{};
    final bairros = <String, GrupoDelivery>{};
    final motoboys = <String, GrupoDelivery>{};
    final formas = <String, GrupoDelivery>{};

    for (final p in pedidos) {
      if (p.status == Pedido.cancelado) {
        cancelados++;
        continue;
      }
      final preparo = _minutos(p.criadoEm, p.saiuEm);
      final entrega = _minutos(p.saiuEm, p.entregueEm);
      final total = _minutos(p.criadoEm, p.entregueEm);
      if (preparo != null) {
        somaPreparo += preparo;
        nPreparo++;
      }
      if (entrega != null) {
        somaEntrega += entrega;
        nEntrega++;
      }
      if (total != null) {
        somaTotal += total;
        nTotal++;
      }
      if (p.motoboyId != null || p.entregadorNome.isNotEmpty) {
        final m = motoboys.putIfAbsent(
          p.entregadorNome.isEmpty ? 'Sem nome' : p.entregadorNome,
          () => GrupoDelivery(p.entregadorNome),
        );
        if (p.status == Pedido.entregue || p.status == Pedido.concluido) {
          m.pedidos++;
          m.totalCentavos += p.totalCentavos;
          if (entrega != null) {
            m._minutosEntrega += entrega;
            m._medidasEntrega++;
          }
        }
      }
      if (p.status != Pedido.concluido) continue;

      concluidos++;
      faturamento += p.totalCentavos;
      taxas += centavos(p.taxaEntrega);
      descontos += centavos(p.desconto);
      void somar(Map<String, GrupoDelivery> mapa, String chave) {
        final g = mapa.putIfAbsent(chave, () => GrupoDelivery(chave));
        g.pedidos++;
        g.totalCentavos += p.totalCentavos;
      }

      somar(
        canais,
        p.pedidoOnlineId == null ? 'Balcão / WhatsApp' : 'Loja online',
      );
      somar(bairros, bairroBase(p.bairro));
      somar(
        formas,
        p.formaPagamento.isEmpty ? 'Não informado' : p.formaPagamento,
      );
    }

    List<GrupoDelivery> ordenar(Map<String, GrupoDelivery> m) =>
        m.values.where((g) => g.pedidos > 0).toList()..sort((a, b) {
          final c = b.pedidos.compareTo(a.pedidos);
          return c != 0 ? c : b.totalCentavos.compareTo(a.totalCentavos);
        });

    return ResumoDelivery._(
      registrados: pedidos.length,
      concluidos: concluidos,
      cancelados: cancelados,
      recusadosOnline: recusadosOnline,
      faturamentoCentavos: faturamento,
      taxasCentavos: taxas,
      descontosCentavos: descontos,
      mediaPreparo: nPreparo == 0 ? null : somaPreparo / nPreparo,
      mediaEntrega: nEntrega == 0 ? null : somaEntrega / nEntrega,
      mediaTotal: nTotal == 0 ? null : somaTotal / nTotal,
      canais: ordenar(canais),
      bairros: ordenar(bairros),
      motoboys: ordenar(motoboys),
      formas: ordenar(formas),
    );
  }
}

/// Cliente do delivery, juntando os pedidos concluídos pelo telefone.
class ClienteDelivery {
  final String chave;
  String nome;
  String telefone;
  String bairro;
  int pedidos = 0;
  int totalCentavos = 0;
  DateTime ultimoPedido;

  ClienteDelivery({
    required this.chave,
    required this.nome,
    required this.telefone,
    required this.bairro,
    required this.ultimoPedido,
  });

  double get total => deCentavos(totalCentavos);
  double get ticketMedio =>
      pedidos == 0 ? 0 : deCentavos(totalCentavos ~/ pedidos);

  int diasSemPedir(DateTime agora) => agora.difference(ultimoPedido).inDays;

  /// Agrupa por telefone (só dígitos; sem telefone, pelo nome). Os dados de
  /// contato vêm do pedido mais recente. Ordena por quem mais gastou.
  static List<ClienteDelivery> agrupar(List<Pedido> pedidos) {
    final mapa = <String, ClienteDelivery>{};
    final ordenados =
        pedidos.where((p) => p.status == Pedido.concluido).toList()
          ..sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
    for (final p in ordenados) {
      final digitos = p.telefone.replaceAll(RegExp(r'\D'), '');
      // Ignora o 55 do Brasil para juntar "11 9..." com "+55 11 9...".
      final fone = digitos.length > 11 && digitos.startsWith('55')
          ? digitos.substring(2)
          : digitos;
      final chave = fone.length >= 8
          ? fone
          : 'nome:${p.clienteNome.trim().toLowerCase()}';
      final c = mapa.putIfAbsent(
        chave,
        () => ClienteDelivery(
          chave: chave,
          nome: p.clienteNome,
          telefone: p.telefone,
          bairro: p.bairro,
          ultimoPedido: p.criadoEm,
        ),
      );
      c
        ..pedidos += 1
        ..totalCentavos += p.totalCentavos
        ..nome = p.clienteNome
        ..telefone = p.telefone
        ..bairro = p.bairro
        ..ultimoPedido = p.criadoEm;
    }
    return mapa.values.toList()
      ..sort((a, b) => b.totalCentavos.compareTo(a.totalCentavos));
  }
}

/// "12 min", "1h05".
String formatarMinutos(double? m) {
  if (m == null) return '—';
  final r = m.round();
  if (r < 60) return '$r min';
  return '${r ~/ 60}h${(r % 60).toString().padLeft(2, '0')}';
}
