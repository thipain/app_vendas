import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _carregando = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _senha.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(
        () => _erro = switch (e.code) {
          'invalid-credential' ||
          'wrong-password' ||
          'user-not-found' => 'E-mail ou senha incorretos',
          'network-request-failed' =>
            'Sem internet. O primeiro login precisa de conexão.',
          'too-many-requests' => 'Muitas tentativas. Aguarde um pouco.',
          _ => 'Não foi possível entrar (${e.code})',
        },
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Envia o e-mail de redefinição de senha do Firebase.
  Future<void> _esqueciSenha() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _EsqueciSenhaDialog(emailInicial: _email.text.trim()),
    );
    if (email == null || !mounted) return;
    try {
      await FirebaseAuth.instance.setLanguageCode('pt');
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      // Por segurança o Firebase pode não informar se o e-mail existe;
      // só mostramos os erros que o usuário consegue corrigir.
      if (e.code == 'invalid-email' || e.code == 'network-request-failed') {
        if (!mounted) return;
        setState(
          () => _erro = e.code == 'invalid-email'
              ? 'E-mail inválido.'
              : 'Sem internet. Tente novamente quando estiver conectado.',
        );
        return;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.mark_email_read_outlined),
        title: const Text('Verifique seu e-mail'),
        content: Text(
          'Se $email estiver cadastrado, você vai receber um link para criar '
          'uma nova senha. Confira também a caixa de spam.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.storefront,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'App Vendas',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Informe um e-mail válido'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _senha,
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Informe a senha' : null,
                    onFieldSubmitted: (_) => _entrar(),
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _carregando ? null : _entrar,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _carregando
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _carregando ? null : _esqueciSenha,
                    child: const Text('Esqueci minha senha'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EsqueciSenhaDialog extends StatefulWidget {
  final String emailInicial;
  const _EsqueciSenhaDialog({required this.emailInicial});

  @override
  State<_EsqueciSenhaDialog> createState() => _EsqueciSenhaDialogState();
}

class _EsqueciSenhaDialogState extends State<_EsqueciSenhaDialog> {
  late final _email = TextEditingController(text: widget.emailInicial);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _enviar() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _email.text.trim().toLowerCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Esqueci minha senha'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Informe o e-mail da sua conta. Enviaremos um link para você '
              'criar uma nova senha.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: (v) =>
                  RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                      .hasMatch((v ?? '').trim())
                  ? null
                  : 'Informe um e-mail válido',
              onFieldSubmitted: (_) => _enviar(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _enviar, child: const Text('Enviar link')),
      ],
    );
  }
}
