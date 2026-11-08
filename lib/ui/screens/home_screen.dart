import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/schedule_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'medication_form_screen.dart';
import 'notification_center_screen.dart';
import 'prn_screen.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';
import 'stock_detail_screen.dart';

/// Tela inicial "Céu do dia": o topo muda de cor conforme a hora
/// (manhã, tarde, entardecer, noite), um relógio de 24 h mostra onde cada
/// dose cai no dia e a agenda vira uma linha do tempo com o marcador "agora".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Atualiza o ponteiro do relógio e as contagens regressivas.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final doses = app.today;
    final taken = doses.where((d) => d.status == DoseStatus.taken).length;
    final late = doses.where((d) => d.status == DoseStatus.late || d.status == DoseStatus.missed).length;
    final remaining = doses.where((d) => d.isOpen && d.status != DoseStatus.missed && d.status != DoseStatus.late).length;
    final permOk = app.permissions?.notificationsEnabled ?? true;
    final hasPrn = app.meds.any((m) => m.isPrn && m.status == MedStatus.active);
    final lowStock = app.meds.where((m) => m.stockEnabled && m.status != MedStatus.ended && m.stockQty <= m.stockMin).toList();

    // Destaque: a próxima dose; se não houver, a última que ficou sem registro.
    DoseView? spotlight = app.nextDose;
    if (spotlight == null) {
      for (final d in doses) {
        if (d.status == DoseStatus.missed) spotlight = d;
      }
    }

    final cs = Theme.of(context).colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () => app.refresh(),
          child: ListView(padding: EdgeInsets.zero, children: [
            _SkyHeader(
              now: now,
              doses: doses,
              taken: taken,
              remaining: remaining,
              late: late,
              permOk: permOk,
              spotlight: spotlight,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!permOk) ...[
                  const SizedBox(height: 16),
                  _Banner(
                    color: AppColors.danger,
                    icon: Icons.notifications_off_rounded,
                    title: 'Notificações desativadas',
                    text: 'Os lembretes não vão aparecer. Toque para corrigir.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
                  ),
                ],
                if (lowStock.isNotEmpty || hasPrn) ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (lowStock.isNotEmpty)
                      _QuickChip(
                        color: AppColors.pending,
                        icon: Icons.inventory_2_rounded,
                        label: lowStock.length == 1 ? 'Estoque baixo: ${lowStock.first.displayName}' : 'Estoque baixo em ${lowStock.length}',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockScreen())),
                      ),
                    if (hasPrn)
                      _QuickChip(
                        color: AppColors.info,
                        icon: Icons.back_hand_rounded,
                        label: 'Uso eventual',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrnScreen())),
                      ),
                  ]),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 26, 4, 14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('HOJE',
                              style: TextStyle(
                                  fontSize: 11.5, letterSpacing: 2.2, fontWeight: FontWeight.w800, color: cs.primary)),
                          const SizedBox(height: 2),
                          const Text('Linha do dia', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
                        ]),
                      ),
                    ),
                    if (doses.isNotEmpty)
                      Text('${doses.length} ${doses.length == 1 ? 'dose' : 'doses'}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ]),
                ),
                if (app.meds.isEmpty)
                  EmptyState(
                    icon: Icons.medication_rounded,
                    title: 'Vamos começar?',
                    message: 'Cadastre seu primeiro remédio e configure os horários dos lembretes.',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicationFormScreen())),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Cadastrar remédio'),
                    ),
                  )
                else if (doses.isEmpty)
                  const EmptyState(
                    icon: Icons.event_available_rounded,
                    title: 'Dia livre',
                    message: 'Não há doses programadas para hoje. Veja os próximos dias na Agenda.',
                  )
                else
                  ..._timeline(doses, now),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Monta a linha do tempo inserindo o marcador "agora" no ponto certo.
  List<Widget> _timeline(List<DoseView> doses, DateTime now) {
    var nowIndex = doses.indexWhere((d) => d.scheduledAt.isAfter(now));
    if (nowIndex < 0) nowIndex = doses.length;
    final count = doses.length + 1;
    final out = <Widget>[];
    var pos = 0;
    for (var i = 0; i <= doses.length; i++) {
      if (i == nowIndex) {
        out.add(_NowRow(now: now, first: pos == 0, last: pos == count - 1));
        pos++;
      }
      if (i < doses.length) {
        out.add(_TimelineRow(doses[i], first: pos == 0, last: pos == count - 1));
        pos++;
      }
    }
    return out;
  }
}

// ───────────────────────── Paleta do céu ─────────────────────────

class _Sky {
  final List<Color> colors;
  final Color accent;
  final bool night;
  const _Sky(this.colors, this.accent, {this.night = false});

  static _Sky of(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 12) {
      return const _Sky([Color(0xFF13305A), Color(0xFF3567A0), Color(0xFFE5966A)], Color(0xFFFFD27A));
    }
    if (h >= 12 && h < 17) {
      return const _Sky([Color(0xFF043640), Color(0xFF0D6F6E), Color(0xFF35AE99)], Color(0xFFB8FFE4));
    }
    if (h >= 17 && h < 19) {
      return const _Sky([Color(0xFF240E3D), Color(0xFF762757), Color(0xFFE06E56)], Color(0xFFFFC08A));
    }
    return const _Sky([Color(0xFF060A22), Color(0xFF151647), Color(0xFF33256C)], Color(0xFF8CF0D2), night: true);
  }
}

/// Cores de status pensadas para fundo escuro (relógio e destaque).
Color _skyStatusColor(DoseStatus s) => switch (s) {
      DoseStatus.taken => const Color(0xFF7FE6A8),
      DoseStatus.late || DoseStatus.snoozed => const Color(0xFFFFB347),
      DoseStatus.missed || DoseStatus.skipped => const Color(0xFFFF8A7A),
      DoseStatus.cancelled => Colors.white38,
      _ => Colors.white,
    };

BoxDecoration _glass({double radius = 22, double alpha = 0.12}) => BoxDecoration(
      color: Colors.white.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
    );

// ───────────────────────── Cabeçalho ─────────────────────────

class _SkyHeader extends StatelessWidget {
  final DateTime now;
  final List<DoseView> doses;
  final int taken, remaining, late;
  final bool permOk;
  final DoseView? spotlight;
  const _SkyHeader({
    required this.now,
    required this.doses,
    required this.taken,
    required this.remaining,
    required this.late,
    required this.permOk,
    required this.spotlight,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final profile = app.activeProfile!;
    final sky = _Sky.of(now);
    final total = doses.length;
    final soft = Colors.white.withValues(alpha: 0.75);

    final String headline;
    if (total == 0) {
      headline = 'Nenhuma dose hoje';
    } else if (late > 0) {
      headline = late == 1 ? '1 dose aguardando' : '$late doses aguardando';
    } else if (remaining == 0) {
      headline = 'Tudo registrado!';
    } else {
      headline = 'Tudo em dia';
    }

    Widget roundBtn(IconData icon, String tip, VoidCallback onTap, {bool badge = false}) => Semantics(
          button: true,
          label: tip,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: Badge(
                  isLabelVisible: badge,
                  backgroundColor: AppColors.pending,
                  smallSize: 9,
                  child: Icon(icon, color: Colors.white, size: 23),
                ),
              ),
            ),
          ),
        );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _SkyPainter(sky))),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Barra superior
              Row(children: [
                Semantics(
                  button: true,
                  label: 'Trocar perfil',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilesScreen())),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                      decoration: _glass(radius: 30),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: sky.accent,
                          child: Text(profile.name.characters.first.toUpperCase(),
                              style: TextStyle(color: sky.colors.first, fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(profile.name.split(' ').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.expand_more_rounded, color: soft, size: 18),
                      ]),
                    ),
                  ),
                ),
                const Spacer(),
                roundBtn(
                  Icons.notifications_none_rounded,
                  'Central de notificações',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
                  badge: !permOk || late > 0,
                ),
                const SizedBox(width: 8),
                roundBtn(Icons.tune_rounded, 'Configurações',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              ]),
              const SizedBox(height: 22),
              // Saudação editorial
              Text(fmtLongDate(now).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sky.accent, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${greeting(now)},\n', style: const TextStyle(fontWeight: FontWeight.w300)),
                    TextSpan(text: '${profile.name.split(' ').first}.', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                  style: const TextStyle(color: Colors.white, fontSize: 34, height: 1.08, letterSpacing: -0.5),
                ),
              ),
              const SizedBox(height: 18),
              // Relógio do dia
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => Semantics(
                    label: '$taken de $total doses registradas hoje',
                    child: SizedBox(
                      width: 264,
                      height: 264,
                      child: Stack(alignment: Alignment.center, children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _DialPainter(doses: doses, now: now, t: t, accent: sky.accent, base: sky.colors[1])),
                        ),
                        SizedBox(
                          width: 150,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              if (total == 0)
                                Icon(sky.night ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded, color: sky.accent, size: 54)
                              else
                                Text.rich(TextSpan(children: [
                                  TextSpan(
                                      text: '$taken',
                                      style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, height: 1)),
                                  TextSpan(
                                      text: ' /$total',
                                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: soft, height: 1)),
                                ]), style: const TextStyle(color: Colors.white)),
                              const SizedBox(height: 6),
                              Text(total == 0 ? 'DIA LIVRE' : 'REGISTRADAS',
                                  style: TextStyle(color: soft, fontSize: 11, letterSpacing: 2.4, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(headline,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 16),
              // Faixa de números
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: _glass(radius: 22, alpha: 0.10),
                child: IntrinsicHeight(
                  child: Row(children: [
                    _Stat(value: taken, label: 'Tomadas', color: const Color(0xFF7FE6A8)),
                    VerticalDivider(color: Colors.white.withValues(alpha: 0.16), width: 1, thickness: 1),
                    _Stat(value: remaining, label: 'Restantes', color: Colors.white),
                    VerticalDivider(color: Colors.white.withValues(alpha: 0.16), width: 1, thickness: 1),
                    _Stat(value: late, label: 'Atrasadas', color: const Color(0xFFFFB347)),
                  ]),
                ),
              ),
              if (spotlight != null) ...[
                const SizedBox(height: 14),
                _Spotlight(spotlight!, sky: sky, key: ValueKey(spotlight!.key)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          label: '$value $label',
          excludeSemantics: true,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$value', style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900, height: 1.1)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label.toUpperCase(),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7), fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );
}

// ───────────────────────── Destaque ─────────────────────────

class _Spotlight extends StatelessWidget {
  final DoseView d;
  final _Sky sky;
  const _Spotlight(this.d, {super.key, required this.sky});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final snoozed = d.status == DoseStatus.snoozed && d.record?.snoozedUntil != null;
    final target = snoozed ? parseDtKey(d.record!.snoozedUntil!) : d.scheduledAt;
    final diff = target.difference(now);
    final overdue = d.status == DoseStatus.late || d.status == DoseStatus.missed;
    final tone = overdue || snoozed ? const Color(0xFFFFB347) : sky.accent;
    final label = switch (d.status) {
      DoseStatus.missed => 'FICOU SEM REGISTRO',
      DoseStatus.late => 'ATRASADA',
      DoseStatus.snoozed => 'ADIADA',
      _ => 'PRÓXIMA DOSE',
    };
    final when = overdue
        ? 'há ${fmtDuration(diff).replaceFirst('há ', '')}'
        : (snoozed ? 'adiada • ${fmtDuration(diff)}' : fmtDuration(diff));
    final soft = Colors.white.withValues(alpha: 0.75);
    final name = d.record?.medName ?? d.med.displayName;
    final instructions = (d.med.instructions ?? '').trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: _glass(radius: 28, alpha: 0.13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tone, fontSize: 11.5, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: Text(when,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: MedAvatar(d.med, size: 48),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 3),
              Text('${d.record?.doseDesc ?? d.med.doseDescription} • ${d.med.form}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: soft, fontSize: 13.5)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(fmtTime(d.scheduledAt),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        ]),
        if (instructions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: _glass(radius: 14, alpha: 0.08),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 18, color: sky.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(instructions, style: const TextStyle(color: Colors.white, fontSize: 13.5))),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _SlideToTake(onDone: () => quickTake(context, d), accent: sky.accent)),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Mais opções (adiar, outro horário, não tomei)',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => showDoseSheet(context, d),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 26),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Controle "deslize para registrar": evita toques acidentais.
class _SlideToTake extends StatefulWidget {
  final VoidCallback onDone;
  final Color accent;
  const _SlideToTake({required this.onDone, required this.accent});

  @override
  State<_SlideToTake> createState() => _SlideToTakeState();
}

class _SlideToTakeState extends State<_SlideToTake> {
  static const _h = 60.0;
  static const _thumb = 52.0;
  double _x = 0;
  bool _dragging = false;
  bool _done = false;

  void _finish() {
    if (_done) return;
    HapticFeedback.mediumImpact();
    _done = true;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Registrar como tomado',
      hint: 'Deslize para a direita',
      onTap: _finish,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        final max = math.max(0.0, c.maxWidth - _thumb - 8);
        final x = _done ? max : _x.clamp(0.0, max);
        final p = max == 0 ? 0.0 : x / max;
        return GestureDetector(
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (e) => setState(() => _x = (_x + e.delta.dx).clamp(0.0, max)),
          onHorizontalDragEnd: (_) {
            setState(() {
              _dragging = false;
              if (_x >= max * 0.82) {
                _x = max;
                _finish();
              } else {
                _x = 0;
              }
            });
          },
          child: Container(
            height: _h,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(_h / 2),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Stack(alignment: Alignment.centerLeft, children: [
              // Rastro preenchido atrás do botão
              AnimatedContainer(
                duration: _dragging ? Duration.zero : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: x + _thumb + 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_h / 2),
                  gradient: LinearGradient(colors: [
                    const Color(0xFF7FE6A8).withValues(alpha: 0.10),
                    const Color(0xFF7FE6A8).withValues(alpha: 0.45),
                  ]),
                ),
              ),
              Positioned.fill(
                left: _thumb + 12,
                right: 12,
                child: Center(
                  child: Opacity(
                    opacity: (1 - p * 1.6).clamp(0.0, 1.0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Deslize: tomei',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                        const SizedBox(width: 6),
                        Icon(Icons.keyboard_double_arrow_right_rounded, color: widget.accent, size: 20),
                      ]),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _dragging ? Duration.zero : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: 4 + x,
                top: 3,
                child: Container(
                  width: _thumb,
                  height: _thumb,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(Colors.white, const Color(0xFF7FE6A8), p),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  child: Icon(_done ? Icons.check_rounded : Icons.medication_rounded,
                      color: const Color(0xFF0D3B2A), size: 26),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

// ───────────────────────── Linha do tempo ─────────────────────────

class _Rail extends StatelessWidget {
  final bool first, last;
  final Widget node;
  final double nodeTop;
  const _Rail({required this.first, required this.last, required this.node, this.nodeTop = 16});

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    final mid = nodeTop + 7;
    return SizedBox(
      width: 30,
      child: Stack(alignment: Alignment.topCenter, children: [
        if (!first) Positioned(top: 0, height: mid, child: Container(width: 2, color: line)),
        if (!last) Positioned(top: mid, bottom: 0, child: Container(width: 2, color: line)),
        Positioned(top: nodeTop, child: node),
      ]),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final DoseView d;
  final bool first, last;
  const _TimelineRow(this.d, {required this.first, required this.last});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = d.status == DoseStatus.taken;
    final canAct = d.status != DoseStatus.taken && d.status != DoseStatus.cancelled && d.status != DoseStatus.skipped;
    final color = AppColors.forStatus(d.status);
    final name = d.record?.medName ?? d.med.displayName;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 50,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topRight,
              child: Text(fmtTime(d.scheduledAt),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: done ? cs.onSurfaceVariant : cs.onSurface,
                      fontFeatures: const [ui.FontFeature.tabularFigures()])),
            ),
          ),
        ),
        _Rail(
          first: first,
          last: last,
          node: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? color : bg,
              border: Border.all(color: color, width: 3),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => showDoseSheet(context, d),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Row(children: [
                    Opacity(opacity: done ? 0.55 : 1, child: MedAvatar(d.med, size: 42)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              color: done ? cs.onSurfaceVariant : cs.onSurface,
                              decoration: done ? TextDecoration.lineThrough : null,
                              decorationColor: cs.onSurfaceVariant,
                            )),
                        const SizedBox(height: 2),
                        Text(d.record?.doseDesc ?? d.med.doseDescription,
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        const SizedBox(height: 6),
                        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                          StatusChip(d.status),
                          if (d.status == DoseStatus.taken && d.record != null)
                            Text('às ${fmtTime(parseDtKey(d.record!.actionAt))}',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          if (d.status == DoseStatus.snoozed && d.record?.snoozedUntil != null)
                            Text('até ${fmtTime(parseDtKey(d.record!.snoozedUntil!))}',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ]),
                      ]),
                    ),
                    if (canAct)
                      IconButton.filledTonal(
                        tooltip: 'Registrar como tomado',
                        iconSize: 24,
                        onPressed: () => quickTake(context, d),
                        icon: const Icon(Icons.check_rounded),
                      )
                    else if (done)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.check_circle_rounded, color: AppColors.success),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _NowRow extends StatelessWidget {
  final DateTime now;
  final bool first, last;
  const _NowRow({required this.now, required this.first, required this.last});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = cs.primary;
    return Semantics(
      label: 'Agora, ${fmtTime(now)}',
      excludeSemantics: true,
      child: SizedBox(
        height: 44,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topRight,
                child: Text(fmtTime(now), style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
            ),
          ),
          _Rail(
            first: first,
            last: last,
            nodeTop: 13,
            node: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c,
                boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
                    child: Text('AGORA',
                        style: TextStyle(color: cs.onPrimary, fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [c.withValues(alpha: 0.6), c.withValues(alpha: 0)]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────── Avisos ─────────────────────────

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  const _Banner({required this.color, required this.icon, required this.title, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              CircleAvatar(radius: 20, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
                  Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                ]),
              ),
              Icon(Icons.arrow_forward_rounded, color: color),
            ]),
          ),
        ),
      );
}

class _QuickChip extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.color, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: color, size: 18),
            ]),
          ),
        ),
      );
}

// ───────────────────────── Pintores ─────────────────────────

class _SkyPainter extends CustomPainter {
  final _Sky sky;
  _SkyPainter(this.sky);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: sky.colors).createShader(rect),
    );

    void orb(Offset c, double r, Color col) {
      canvas.drawCircle(
        c,
        r,
        Paint()..shader = RadialGradient(colors: [col, col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    orb(Offset(size.width * 0.95, 120), size.width * 0.75, sky.accent.withValues(alpha: 0.22));
    orb(Offset(size.width * 0.0, size.height * 0.62), size.width * 0.7, sky.colors.last.withValues(alpha: 0.5));
    orb(Offset(size.width * 0.9, size.height * 0.95), size.width * 0.5, sky.colors[1].withValues(alpha: 0.6));

    if (sky.night) {
      final rnd = math.Random(11);
      final star = Paint();
      for (var i = 0; i < 80; i++) {
        final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height * 0.75);
        star.color = Colors.white.withValues(alpha: 0.15 + rnd.nextDouble() * 0.6);
        canvas.drawCircle(p, 0.5 + rnd.nextDouble() * 1.1, star);
      }
      // Lua crescente
      final mc = Offset(size.width - 52, 150);
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: mc, radius: 17)),
        Path()..addOval(Rect.fromCircle(center: mc + const Offset(-8, -5), radius: 15)),
      );
      canvas.drawPath(
          moon,
          Paint()
            ..color = sky.accent.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawPath(moon, Paint()..color = const Color(0xFFF4F1DE));
    } else {
      // Sol suave
      final sc = Offset(size.width - 56, 150);
      canvas.drawCircle(
          sc,
          26,
          Paint()
            ..color = sky.accent.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
      canvas.drawCircle(sc, 14, Paint()..color = sky.accent.withValues(alpha: 0.9));
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.sky != sky;
}

/// Relógio de 24 h: 0 h no topo, sentido horário. Cada dose é um ponto no anel.
class _DialPainter extends CustomPainter {
  final List<DoseView> doses;
  final DateTime now;
  final double t;
  final Color accent;
  final Color base;
  _DialPainter({required this.doses, required this.now, required this.t, required this.accent, required this.base});

  static double _frac(DateTime d) => (d.hour * 60 + d.minute) / 1440.0;
  static double _angle(double f) => -math.pi / 2 + 2 * math.pi * f;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 30;
    const stroke = 12.0;
    final ringRect = Rect.fromCircle(center: c, radius: r);

    // Trilho
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = Colors.white.withValues(alpha: 0.10));

    // Parte do dia já percorrida
    final nowF = _frac(now);
    final sweep = 2 * math.pi * nowF * t;
    if (sweep > 0.001) {
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: 2 * math.pi,
            transform: const GradientRotation(-math.pi / 2),
            colors: [accent.withValues(alpha: 0.05), accent.withValues(alpha: 0.75)],
            stops: [0, math.max(nowF, 0.01)],
          ).createShader(ringRect),
      );
    }

    // Marcas das horas (por dentro) e rótulos (por fora)
    final tick = Paint()..strokeCap = StrokeCap.round;
    for (var h = 0; h < 24; h++) {
      final a = _angle(h / 24);
      final major = h % 6 == 0;
      final dir = Offset(math.cos(a), math.sin(a));
      tick
        ..strokeWidth = major ? 2.2 : 1.2
        ..color = Colors.white.withValues(alpha: major ? 0.6 : 0.28);
      canvas.drawLine(c + dir * (r - stroke / 2 - 5), c + dir * (r - stroke / 2 - (major ? 13 : 9)), tick);
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${h}h',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final p = c + dir * (r + 21);
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Doses
    for (final d in doses) {
      final f = _frac(d.scheduledAt);
      final a = _angle(f);
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      final col = _skyStatusColor(d.status);
      final appear = (t * 1.2 - f * 0.2).clamp(0.0, 1.0);
      if (appear <= 0) continue;
      canvas.drawCircle(
          p,
          13 * appear,
          Paint()
            ..color = col.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      final open = d.status != DoseStatus.taken;
      canvas.drawCircle(p, 8.5 * appear, Paint()..color = open ? base : col);
      canvas.drawCircle(
          p,
          8.5 * appear,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = col);
    }

    // Ponteiro "agora"
    final na = _angle(nowF * t);
    final nd = Offset(math.cos(na), math.sin(na));
    canvas.drawLine(
        c + nd * (r - stroke / 2 - 16),
        c + nd * (r + stroke / 2 + 4),
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Colors.white);
    final tip = c + nd * (r + stroke / 2 + 4);
    canvas.drawCircle(
        tip,
        9,
        Paint()
          ..color = accent.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(tip, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_DialPainter old) => true;
}
