import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/autotest.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const MeuRemedioApp()));
  // Inicializa após o primeiro quadro para exibir a tela de abertura.
  await state.init();
  if (AutoTest.enabled) await AutoTest.run(state);
}
