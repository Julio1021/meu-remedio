# Meu Remédio — lembretes e gerenciamento de medicamentos (Flutter)

Aplicativo mobile em **Flutter/Dart**, em português (PT-BR), que funciona **100% offline**:
cadastro de medicamentos, horários flexíveis, notificações locais com ações (TOMADO / LEMBRAR EM X MIN / ADIAR),
histórico, calendário de adesão, relatórios PDF/CSV, estoque automático, uso eventual, múltiplos perfis,
backup/restauração e modo de privacidade. Prioridade para Android, compatível com iOS.

> O aplicativo **não prescreve, não recomenda doses e não define intervalos**. Tudo é informado pelo usuário
> conforme orientação profissional.

---

## 1. Requisitos

- Flutter **3.27 ou superior** (Dart 3.6+) — `flutter --version`
- Android Studio (SDK Android 35+) e um aparelho/emulador Android 8+
- Para iOS: macOS com Xcode 15+

## 2. Instalação

```bash
cd meu_remedio
# Gera as pastas nativas android/ e ios/ (não sobrescreve lib/)
flutter create --org br.com.meuremedio --project-name meu_remedio --platforms=android,ios .
# Aplica manifest, permissões, receivers, ícone de notificação, desugaring e AppDelegate
python3 tool/setup_platforms.py
flutter pub get
flutter run
```

Gerar APK de instalação: `flutter build apk --release` (arquivo em `build/app/outputs/flutter-apk/`).

### Se preferir configurar o Android manualmente
1. Copie `platform/android/AndroidManifest.xml` para `android/app/src/main/`.
2. Copie `platform/android/res/drawable/ic_stat_pill.xml` para `android/app/src/main/res/drawable/`.
3. Em `android/app/build.gradle(.kts)`:
   ```kotlin
   android {
       compileOptions { isCoreLibraryDesugaringEnabled = true /* + o que já existir */ }
   }
   dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
   ```
4. iOS: substitua `ios/Runner/AppDelegate.swift` por `platform/ios/AppDelegate.swift` e adicione
   `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` ao `Info.plist`.

## 3. Testes automatizados

```bash
flutter test
```
- `test/schedule_engine_test.dart` — regras de agendamento (horários fixos, dias da semana, dias alternados,
  intervalos que cruzam a meia-noite, vigência de regras), situação das doses e estimativa de estoque.
- `test/dose_service_test.dart` — registro de doses no SQLite (em memória): desconto de estoque,
  **prevenção de duplicidade** (notificação + app), desfazer, adiar, alteração de horários preservando
  histórico, pausar/retomar, adesão, backup/restauração e parâmetros de uso eventual.

## 4. Arquitetura

```
lib/
  main.dart / app.dart          Inicialização, tema, navegação (5 abas + botão de adicionar)
  core/                         Tema (verde‑petróleo, claro/escuro) e formatação PT‑BR (DD/MM/AAAA, 24 h)
  data/                         Modelos, SQLite (sqflite) e preferências
  domain/                       Regras puras e testáveis: motor de horários, situação, adesão, estoque
  services/                     Notificações, registro de doses, relatórios PDF/CSV, backup, demonstração
  state/app_state.dart          Estado global (Provider/ChangeNotifier)
  ui/screens, ui/widgets        Telas e componentes
```

**Banco de dados (SQLite):** `profiles`, `medications`, `schedules` (regras versionadas por vigência),
`dose_records` (UNIQUE medicamento+horário → sem duplicidade), `stock_movements`, `change_log`, `settings`.
Doses programadas são geradas a partir das regras; somente os registros (tomado, adiado, não tomado,
cancelado) são gravados. Ao editar um tratamento, a regra vigente é encerrada e outra é criada, de modo que
o histórico anterior permanece intacto.

**Situações da dose:** Pendente → Próximo horário → Atrasado (após 15 min) → Não registrado (após 4 h,
configurável). Tomado, Adiado, Não tomado (confirmado pelo usuário) e Cancelado vêm de registros explícitos.
Uma dose pendente **nunca** vira tomada automaticamente, e doses não confirmadas não descontam estoque.

### Notificações (o ponto mais importante)
- Locais e nativas (`flutter_local_notifications`), com canais Android próprios (padrão, sem vibração, discreto,
  avisos, resumo diário) e ícone monocromático.
- Ações direto na notificação, executadas em segundo plano sem abrir o app: o tratador
  (`notificationTapBackground`) abre o SQLite no isolate de fundo, registra a dose com origem "notificacao",
  desconta o estoque, cancela as repetições e, se for o caso, avisa estoque baixo.
- Repetição se não houver resposta (intervalo e quantidade configuráveis), aviso antecipado opcional,
  avisos de vencimento (7 dias antes), término de tratamento (2 dias antes) e resumo diário.
- **Janela de agendamento**: 7 dias no Android e ~56 lembretes no iOS (limite de 64 do sistema). A janela é
  recalculada ao abrir o app, ao voltar do segundo plano, a cada alteração/registro e após troca de fuso.
  O plugin restaura os agendamentos após reiniciar o aparelho ou atualizar o app.
- Horários são guardados como "horário de parede" (08:00 continua 08:00 após mudar de fuso/horário de verão).
- Alarmes exatos: se a permissão for negada, o app usa o modo inexato e avisa o usuário.
- Modo de privacidade: notificações sem nome/dose e ocultas na tela bloqueada.

## 5. Mapa de telas

| # | Tela | Onde |
|---|------|------|
| 1 | Abertura | `app.dart` (`SplashScreen`) |
| 2–4 | Apresentação, perfil, permissões | `onboarding_screen.dart`, `permissions_screen.dart` |
| 5 | Dashboard (resumo, próximo medicamento, agenda do dia) | `home_screen.dart` |
| 6 | Lista de medicamentos (pesquisa, filtros, favoritos) | `medications_screen.dart` |
| 7, 8, 10 | Cadastro/edição em 4 etapas, configuração de horários | `medication_form_screen.dart` |
| 9 | Detalhes, pausar/retomar/encerrar/excluir, histórico de alterações | `medication_detail_screen.dart` |
| 11 | Agenda (qualquer dia, próximos 30 dias) | `agenda_screen.dart` |
| 12–13 | Calendário de administração e histórico com filtros | `history_screen.dart` |
| 14 | Relatórios (adesão, evolução semanal, pendências por dia, PDF/CSV) | `reports_screen.dart` |
| 15–16 | Estoque e detalhes (compras, ajustes, perdas, movimentações) | `stock_detail_screen.dart` |
| 17 | Uso eventual | `prn_screen.dart` |
| 18–19 | Perfis e compartilhamento/cuidadores | `profiles_screen.dart` |
| 20 | Central de notificações (diagnóstico, teste, programados) | `notification_center_screen.dart` |
| 21–23 | Configurações, privacidade/LGPD, backup | `settings_screen.dart`, `privacy_screen.dart`, `backup_screen.dart` |

## 6. Dados de demonstração
No primeiro acesso é possível incluir um perfil **"Demonstração"** com dados fictícios, separado do seu.
Remova em *Configurações > Remover dados de demonstração*.

## 7. Limitações conhecidas e próximos passos
- **Acompanhamento remoto por cuidador** em tempo real exige um servidor (ex.: Supabase/Firebase) com
  autenticação e consentimento; nesta versão o cuidador acompanha por perfis no mesmo aparelho ou por
  relatórios PDF enviados pelo usuário.
- **Som individual por medicamento**: no Android o som é definido por canal; o app oferece lembrete padrão ou
  discreto por medicamento. Para sons próprios, adicione arquivos em `android/app/src/main/res/raw/` e crie
  canais adicionais em `NotificationService`.
- Widget de tela inicial e pesquisa por voz não foram implementados (dependem de código nativo adicional).
- Nenhum sistema de notificação é infalível: economia de bateria de alguns fabricantes pode atrasar avisos —
  a tela de permissões orienta o usuário.
