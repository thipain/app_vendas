import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/relatorio_erros.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // No Android o cache offline já vem ativado; aqui só garantimos que ele não
  // seja limitado, para que catálogo, clientes e vendas fiquem no aparelho.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Erros do app vão para o Firebase (painel administrativo → Erros do app).
  await RelatorioErros.iniciar();

  runApp(const App());
}
