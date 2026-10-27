import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/update/update_checker.dart';
import 'data/config_repository.dart';
import 'models/config_loja.dart';
import 'pages/login_page.dart';
import 'pages/shell/sessao_gate.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // As cores e o nome vêm das Configurações da loja.
    return ValueListenableBuilder<ConfigLoja>(
      valueListenable: ConfigRepository.atual,
      builder: (context, config, _) => MaterialApp(
        title: config.nomeSistema,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: config.corPrimaria,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const _Inicio(),
      ),
    );
  }
}

/// Verifica atualização uma vez ao abrir o app e mostra login ou o sistema.
class _Inicio extends StatefulWidget {
  const _Inicio();

  @override
  State<_Inicio> createState() => _InicioState();
}

class _InicioState extends State<_Inicio> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => verificarAtualizacao(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    // O FirebaseAuth guarda a sessão no aparelho: depois do primeiro login,
    // o usuário continua logado mesmo sem internet.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final conta = snap.data;
        return conta == null
            ? const LoginPage()
            : SessaoGate(key: ValueKey(conta.uid), conta: conta);
      },
    );
  }
}
