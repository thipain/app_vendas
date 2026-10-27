import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/regra_exception.dart';
import '../models/loja.dart';
import '../models/usuario.dart';
import 'banco.dart';
import 'usuario_repository.dart';

/// Administração do sistema multiloja: lojas, donos e migração.
class SistemaRepository {
  final _db = Banco.db;

  CollectionReference<Map<String, dynamic>> get _auditoria =>
      _db.collection('auditoriaSistema');

  /// Coleções de cada loja (usadas na migração da versão anterior).
  static const colecoesDaLoja = [
    'produtos',
    'clientes',
    'vendas',
    'caixas',
    'movimentosCaixa',
    'comandas',
    'movimentosEstoque',
    'notasEntrada',
    'receitas',
    'operacoesEstoque',
    'retiradas',
    'ponto',
    'auditoria',
  ];

  Stream<Sistema> watchSistema() => Banco.sistema
      .snapshots(includeMetadataChanges: true)
      .where((s) => s.exists || !s.metadata.isFromCache)
      .map(Sistema.fromDoc);

  /// Lojas em que o usuário é membro (consulta em todas as lojas).
  Stream<List<Vinculo>> watchVinculos(String uid) => _db
      .collectionGroup('membros')
      .where('uid', isEqualTo: uid)
      .snapshots(includeMetadataChanges: true)
      .where((s) => s.docs.isNotEmpty || !s.metadata.isFromCache)
      .map(
        (s) =>
            s.docs.map(Vinculo.fromDoc).toList()
              ..sort((a, b) => a.lojaNome.compareTo(b.lojaNome)),
      );

  /// Todas as lojas (somente o dono do sistema consegue ler).
  Stream<List<Loja>> watchLojas() => Banco.lojas.snapshots().map(
    (s) => s.docs.map(Loja.fromDoc).toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase())),
  );

  Stream<Loja?> watchLoja(String id) => Banco.lojas
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Loja.fromDoc(d) : null);

  void _registrar(
    WriteBatch batch,
    String acao,
    String descricao, {
    String? lojaId,
    Object? dados,
  }) {
    final eu = FirebaseAuth.instance.currentUser;
    batch.set(_auditoria.doc(), {
      'acao': acao,
      'descricao': descricao,
      'lojaId': lojaId,
      'dados': dados,
      'usuario': {'uid': eu?.uid, 'email': eu?.email},
      'data': Timestamp.now(),
    });
  }

  static String _validarNomeLoja(String nome) {
    final n = nome.trim();
    if (n.isEmpty || n.length > 120) {
      throw const RegraException(
        'Informe o nome da loja (até 120 caracteres).',
      );
    }
    return n;
  }

  /// Primeiro acesso de uma instalação nova: cria o sistema, a primeira loja
  /// e torna a conta logada dona do sistema e administradora da loja.
  Future<String> configurarSistema({
    required String nomeLoja,
    required String nome,
  }) async {
    final conta = FirebaseAuth.instance.currentUser!;
    final n = _validarNomeLoja(nomeLoja);
    final loja = Banco.lojas.doc();
    final batch = _db.batch();
    batch.set(Banco.sistema, {
      'adminInicial': conta.uid,
      'superAdmins': [conta.uid],
      'configuradoEm': FieldValue.serverTimestamp(),
    });
    batch.set(loja, {
      'nome': n,
      'ativa': true,
      'criadaEm': FieldValue.serverTimestamp(),
    });
    final usuario = Usuario(
      id: conta.uid,
      nome: nome.trim(),
      email: (conta.email ?? '').toLowerCase(),
      papel: Usuario.papelAdmin,
    );
    batch.set(UsuarioRepository.membrosDa(loja.id).doc(conta.uid), {
      ...UsuarioRepository.dadosMembro(usuario, loja.id, n),
      'criadoEm': FieldValue.serverTimestamp(),
    });
    batch.set(Banco.contas.doc(usuario.email), {
      'uid': conta.uid,
      'nome': usuario.nome,
    });
    await batch.commit();
    return loja.id;
  }

  /// Cadastra uma loja e o administrador dela (conta nova ou já existente).
  /// Precisa de internet.
  Future<String> criarLoja({
    required String nomeLoja,
    required String nomeAdmin,
    required String emailAdmin,
    required String senhaAdmin,
  }) async {
    final n = _validarNomeLoja(nomeLoja);
    final conta = await UsuarioRepository.obterOuCriarConta(
      nome: nomeAdmin,
      email: emailAdmin,
      senha: senhaAdmin,
    );
    final loja = Banco.lojas.doc();
    final admin = Usuario(
      id: conta.uid,
      nome: nomeAdmin.trim(),
      email: emailAdmin.trim().toLowerCase(),
      papel: Usuario.papelAdmin,
    );
    final batch = _db.batch();
    batch.set(loja, {
      'nome': n,
      'ativa': true,
      'criadaEm': FieldValue.serverTimestamp(),
    });
    batch.set(UsuarioRepository.membrosDa(loja.id).doc(conta.uid), {
      ...UsuarioRepository.dadosMembro(admin, loja.id, n),
      'criadoEm': FieldValue.serverTimestamp(),
    });
    _registrar(
      batch,
      'store.create',
      'Loja cadastrada',
      lojaId: loja.id,
      dados: {'nome': n, 'admin': admin.email, 'contaExistente': !conta.nova},
    );
    await batch.commit();
    return loja.id;
  }

  /// Adiciona outro administrador a uma loja (ex.: o dono de duas lojas).
  Future<void> adicionarAdministrador(
    Loja loja, {
    required String nome,
    required String email,
    required String senha,
  }) async {
    final conta = await UsuarioRepository.obterOuCriarConta(
      nome: nome,
      email: email,
      senha: senha,
    );
    final ref = UsuarioRepository.membrosDa(loja.id).doc(conta.uid);
    final atual = await ref.get(const GetOptions(source: Source.server));
    final admin = Usuario(
      id: conta.uid,
      nome: nome.trim(),
      email: email.trim().toLowerCase(),
      papel: Usuario.papelAdmin,
    );
    final batch = _db.batch();
    if (atual.exists) {
      batch.update(ref, {'papel': Usuario.papelAdmin, 'ativo': true});
    } else {
      batch.set(ref, {
        ...UsuarioRepository.dadosMembro(admin, loja.id, loja.nome),
        'criadoEm': FieldValue.serverTimestamp(),
      });
    }
    _registrar(
      batch,
      'store.admin_add',
      'Administrador adicionado à loja',
      lojaId: loja.id,
      dados: {'email': admin.email},
    );
    await batch.commit();
  }

  Future<void> renomearLoja(Loja loja, String nome) async {
    final n = _validarNomeLoja(nome);
    final batch = _db.batch();
    batch.update(Banco.lojas.doc(loja.id), {'nome': n});
    _registrar(
      batch,
      'store.rename',
      'Loja renomeada',
      lojaId: loja.id,
      dados: {'antes': loja.nome, 'depois': n},
    );
    await batch.commit();
  }

  /// Bloqueia ou libera o acesso de toda a equipe da loja.
  Future<void> definirAtiva(Loja loja, bool ativa) async {
    final batch = _db.batch();
    batch.update(Banco.lojas.doc(loja.id), {'ativa': ativa});
    _registrar(
      batch,
      ativa ? 'store.unblock' : 'store.block',
      ativa ? 'Loja liberada' : 'Loja bloqueada',
      lojaId: loja.id,
    );
    await batch.commit();
  }

  /// true quando ainda há dados da versão anterior (sem lojas) para migrar.
  Future<bool> temDadosAntigos(Sistema sistema) async {
    if (sistema.migradoPara != null) return false;
    for (final c in ['produtos', 'vendas', 'usuarios']) {
      final s = await _db
          .collection(c)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (s.docs.isNotEmpty) return true;
    }
    return false;
  }

  /// Cria a loja [nomeLoja] e copia para ela os dados da versão anterior
  /// (coleções na raiz do banco). Os originais ficam intactos como cópia de
  /// segurança. A conta logada (dono do sistema) vira administradora da loja.
  Future<String> migrarDadosAntigos(
    String nomeLoja, {
    void Function(String etapa)? progresso,
  }) async {
    final n = _validarNomeLoja(nomeLoja);
    final conta = FirebaseAuth.instance.currentUser!;
    final lojaRef = Banco.lojas.doc();
    final destino = Loja(id: lojaRef.id, nome: n);
    progresso?.call('Criando a loja...');
    await lojaRef.set({
      'nome': n,
      'ativa': true,
      'criadaEm': FieldValue.serverTimestamp(),
    });
    var batch = _db.batch();
    var operacoes = 0;
    Future<void> gravar(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> d,
    ) async {
      batch.set(ref, d);
      if (++operacoes >= 400) {
        await batch.commit();
        batch = _db.batch();
        operacoes = 0;
      }
    }

    for (final c in colecoesDaLoja) {
      progresso?.call('Copiando $c...');
      final docs = await _db
          .collection(c)
          .get(const GetOptions(source: Source.server));
      for (final d in docs.docs) {
        await gravar(lojaRef.collection(c).doc(d.id), d.data());
      }
    }

    progresso?.call('Copiando configurações da loja...');
    final config = await _db
        .collection('config')
        .doc('loja')
        .get(const GetOptions(source: Source.server));
    if (config.exists) {
      await gravar(lojaRef.collection('config').doc('loja'), config.data()!);
    }

    progresso?.call('Copiando equipe...');
    final usuarios = await _db
        .collection('usuarios')
        .get(const GetOptions(source: Source.server));
    if (!usuarios.docs.any((d) => d.id == conta.uid)) {
      final eu = Usuario(
        id: conta.uid,
        nome: conta.email ?? 'Administrador',
        email: (conta.email ?? '').toLowerCase(),
        papel: Usuario.papelAdmin,
      );
      await gravar(
        UsuarioRepository.membrosDa(destino.id).doc(conta.uid),
        UsuarioRepository.dadosMembro(eu, destino.id, destino.nome),
      );
      await gravar(Banco.contas.doc(eu.email), {'uid': eu.id, 'nome': eu.nome});
    }
    for (final d in usuarios.docs) {
      final u = Usuario.fromDoc(d);
      await gravar(UsuarioRepository.membrosDa(destino.id).doc(u.id), {
        ...d.data(),
        ...UsuarioRepository.dadosMembro(u, destino.id, destino.nome),
      });
      if (u.email.isNotEmpty) {
        await gravar(Banco.contas.doc(u.email.toLowerCase()), {
          'uid': u.id,
          'nome': u.nome,
        });
      }
    }

    batch.update(Banco.sistema, {'migradoPara': destino.id});
    _registrar(
      batch,
      'store.migrate',
      'Dados da versão anterior migrados',
      lojaId: destino.id,
    );
    await batch.commit();
    return destino.id;
  }

  /// Nome da loja na versão anterior (para sugerir na migração).
  Future<String> nomeLojaAntiga() async {
    try {
      final d = await _db
          .collection('config')
          .doc('loja')
          .get(const GetOptions(source: Source.server));
      return d.data()?['nomeLoja'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }
}
