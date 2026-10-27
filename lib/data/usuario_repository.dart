import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/permissoes.dart';
import '../models/usuario.dart';
import 'auditoria_repository.dart';
import 'offline.dart';

/// Equipe: perfis, permissões e contas de acesso.
class UsuarioRepository {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('usuarios');
  static DocumentReference<Map<String, dynamic>> get _sistema =>
      _db.collection('config').doc('sistema');

  Stream<Usuario?> watch(String uid) => _col
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? Usuario.fromDoc(d) : null);

  Stream<List<Usuario>> watchTodos() => _col
      .orderBy('nomeBusca')
      .snapshots()
      .map((s) => s.docs.map(Usuario.fromDoc).toList());

  /// true quando o sistema ainda não tem administrador (primeiro acesso).
  Future<bool> precisaConfiguracaoInicial() async {
    final doc = await _sistema.get(const GetOptions(source: Source.server));
    return !doc.exists;
  }

  /// Primeiro acesso: a conta logada vira o administrador do sistema.
  Future<void> configurarPrimeiroAdmin(String nome) async {
    final conta = FirebaseAuth.instance.currentUser!;
    final batch = _db.batch();
    batch.set(_col.doc(conta.uid), {
      ...Usuario(
        nome: nome,
        email: conta.email ?? '',
        papel: Usuario.papelAdmin,
      ).toMap(),
      'criadoEm': FieldValue.serverTimestamp(),
    });
    batch.set(_sistema, {
      'adminInicial': conta.uid,
      'configuradoEm': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Cria a conta de acesso de um funcionário. Precisa de internet.
  ///
  /// Usa uma segunda instância do Firebase para não deslogar o administrador
  /// (criar uma conta pelo SDK faz login automático nela).
  Future<void> criar({
    required String nome,
    required String email,
    required String senha,
    required String papel,
    required Set<String> permissoes,
  }) async {
    final app = await Firebase.initializeApp(
      name: 'cadastro-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    try {
      final cred = await FirebaseAuth.instanceFor(app: app)
          .createUserWithEmailAndPassword(email: email, password: senha);
      final usuario = Usuario(
        id: cred.user!.uid,
        nome: nome,
        email: email,
        papel: papel,
        permissoes: Permissao.normalizar(permissoes),
      );
      final batch = _db.batch();
      batch.set(_col.doc(usuario.id), {
        ...usuario.toMap(),
        'criadoEm': FieldValue.serverTimestamp(),
      });
      AuditoriaRepository.noBatch(batch, 'user.create', 'Funcionário cadastrado',
          entidade: 'usuario', entidadeId: usuario.id, depois: usuario.toMap());
      await batch.commit();
    } finally {
      await app.delete();
    }
  }

  /// Altera nome, papel, status ou permissões, protegendo o último admin.
  Future<void> salvar(Usuario antes, Usuario depois,
      {required List<Usuario> equipe}) async {
    final perdeAdmin = antes.isAdmin &&
        antes.ativo &&
        (!depois.isAdmin || !depois.ativo);
    if (perdeAdmin &&
        equipe.where((u) => u.isAdmin && u.ativo && u.id != antes.id).isEmpty) {
      throw StateError(
          'Não é possível remover ou bloquear o último administrador ativo.');
    }
    final normalizado = depois.copyWith(
        permissoes: Permissao.normalizar(depois.permissoes));
    final batch = _db.batch();
    batch.update(_col.doc(antes.id), {
      ...normalizado.toMap(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    AuditoriaRepository.noBatch(batch, 'user.update', 'Funcionário alterado',
        entidade: 'usuario',
        entidadeId: antes.id,
        antes: antes.toMap(),
        depois: normalizado.toMap());
    semAguardar(batch.commit(), 'usuário ${antes.nome}');
  }

  /// Envia o e-mail de redefinição de senha do Firebase.
  Future<void> enviarRedefinicaoSenha(Usuario usuario) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: usuario.email);
    AuditoriaRepository.registrar(
        'user.password_reset', 'E-mail de redefinição de senha enviado',
        entidade: 'usuario', entidadeId: usuario.id);
  }

  /// O próprio usuário altera o nome exibido.
  void alterarMeuNome(Usuario eu, String nome) {
    semAguardar(
      _col.doc(eu.id).update({
        'nome': nome,
        'nomeBusca': nome.toLowerCase(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      }),
      'perfil',
    );
    AuditoriaRepository.registrar('profile.update', 'Perfil alterado',
        entidade: 'usuario',
        entidadeId: eu.id,
        antes: {'nome': eu.nome},
        depois: {'nome': nome});
  }

  /// Troca a senha confirmando a senha atual. Precisa de internet.
  Future<void> alterarMinhaSenha(String senhaAtual, String novaSenha) async {
    final conta = FirebaseAuth.instance.currentUser!;
    await conta.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: conta.email!, password: senhaAtual),
    );
    await conta.updatePassword(novaSenha);
    AuditoriaRepository.registrar('profile.password', 'Senha alterada',
        entidade: 'usuario', entidadeId: conta.uid);
  }
}
