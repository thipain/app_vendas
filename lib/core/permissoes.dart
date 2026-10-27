/// Módulos que o administrador pode liberar para cada funcionário.
///
/// Vendas, retiradas e meu ponto ficam disponíveis para todo usuário ativo;
/// o administrador tem acesso a tudo.
class Permissao {
  static const dashboard = 'dashboard';
  static const comandas = 'comandas';
  static const calculadora = 'calculadora';
  static const historico = 'historico';
  static const notificacoes = 'notificacoes';
  static const estoque = 'estoque';
  static const transformacoes = 'transformacoes';
  static const pontoEquipe = 'ponto_equipe';
  static const relatorios = 'relatorios';
  static const caixa = 'caixa';
  static const entradas = 'entradas';
  static const movimentacoes = 'movimentacoes';
  static const cancelarVendas = 'cancelar_vendas';
  static const auditoria = 'auditoria';
  static const clientes = 'clientes';

  /// Sempre liberados para qualquer funcionário ativo.
  static const vendas = 'vendas';
  static const meuPonto = 'meu_ponto';
  static const retiradas = 'retiradas';
  static const livres = {vendas, meuPonto, retiradas};

  /// Somente administradores (equipe, configurações).
  static const admin = 'admin';

  static const catalogo = {
    dashboard: 'Visão geral',
    comandas: 'Comandas',
    calculadora: 'Calculadora',
    historico: 'Histórico de vendas',
    clientes: 'Clientes',
    notificacoes: 'Notificações de estoque',
    estoque: 'Estoque',
    transformacoes: 'Montagem e desmanche de produtos',
    pontoEquipe: 'Controle de ponto da equipe',
    relatorios: 'Relatórios',
    caixa: 'Abertura e fechamento de caixa',
    entradas: 'Entrada de mercadorias',
    movimentacoes: 'Movimentações do estoque',
    cancelarVendas: 'Cancelar/estornar vendas',
    auditoria: 'Auditoria do sistema',
  };

  /// Permissões dadas a um funcionário novo.
  static const padraoNovoFuncionario = {comandas, calculadora};

  /// Ajusta dependências entre permissões (notificações exigem estoque).
  static Set<String> normalizar(Iterable<String> lista) {
    final p = lista.where(catalogo.containsKey).toSet();
    if (p.contains(notificacoes)) p.add(estoque);
    return p;
  }
}
