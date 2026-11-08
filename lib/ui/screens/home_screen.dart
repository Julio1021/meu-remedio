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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final doses = app.today;
    final taken = doses.where((d) => d.status == DoseStatus.taken).length;
    final late = doses.where((d) => d.status == DoseStatus.late || d.status == DoseStatus.missed).length;
    final remaining = doses.where((d) => d.isOpen && d.status != DoseStatus.missed && d.status != DoseStatus.late).length;
    final next = app.nextDose;
    final permOk = app.permissions?.notificationsEnabled ?? true;
    final hasPrn = app.meds.any((m) => m.isPrn && m.status == MedStatus.active);
    final lowStock = app.meds.where((m) => m.stockEnabled && m.status != MedStatus.ended && m.stockQty <= m.stockMin).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      body: RefreshIndicator(
        onRefresh: () => app.refresh(),
        child: ListView(padding: EdgeInsets.zero, children: [
          _Hero(total: doses.length, taken: taken, remaining: remaining, late: late, permOk: permOk),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!permOk) ...[
                const SizedBox(height: 14),
                _Alert(
                  color: AppColors.danger,
                  icon: Icons.notifications_off_rounded,
                  title: 'Notificações desativadas',
                  text: 'Os lembretes não vão aparecer. Toque para corrigir.',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
                ),
              ],
              if (next != null) ...[
                const SectionTitle('Próximo medicamento'),
                _NextDoseCard(next),
              ],
              if (lowStock.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Alert(
                  color: AppColors.pending,
                  icon: Icons.inventory_2_rounded,
                  title: lowStock.length == 1 ? 'Estoque baixo: ${lowStock.first.displayName}' : 'Estoque baixo em ${lowStock.length} remédios',
                  text: 'Toque para ver o controle de estoque.',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockScreen())),
                ),
              ],
              if (hasPrn) ...[
                const SizedBox(height: 12),
                _Alert(
                  color: AppColors.info,
                  icon: Icons.back_hand_rounded,
                  title: 'Uso eventual',
                  text: 'Registrar um remédio usado quando necessário.',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrnScreen())),
                ),
              ],
              SectionTitle('Agenda de hoje', trailing: doses.isEmpty ? null : Text('${doses.length} dose(s)')),
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
                for (final d in doses) Padding(padding: const EdgeInsets.only(bottom: 10), child: DoseTile(d)),
            ]),
          ),
        ]),
      ),
    ),
    );
  }
}

/// Cabeçalho colorido com saudação e resumo do dia.
class _Hero extends StatelessWidget {
  final int total, taken, remaining, late;
  final bool permOk;
  const _Hero({required this.total, required this.taken, required this.remaining, required this.late, required this.permOk});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final profile = app.activeProfile!;
    final now = DateTime.now();
    final pct = total == 0 ? 0.0 : taken / total;
    final String headline;
    if (total == 0) {
      headline = 'Nenhuma dose hoje';
    } else if (late > 0) {
      headline = late == 1 ? '1 dose aguardando' : '$late doses aguardando';
    } else if (remaining == 0) {
      headline = 'Tudo registrado!';
    } else {
      headline = 'Seu dia está em dia';
    }
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.82);

    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilesScreen())),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Text(profile.name.characters.first.toUpperCase(),
                      style: const TextStyle(color: white, fontWeight: FontWeight.w800, fontSize: 19)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${greeting(now)}, ${profile.name.split(' ').first}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(fmtLongDate(now), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: soft)),
                ]),
              ),
              IconButton(
                tooltip: 'Central de notificações',
                color: white,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
                icon: Badge(
                  isLabelVisible: !permOk || late > 0,
                  backgroundColor: AppColors.pending,
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
              IconButton(
                tooltip: 'Configurações',
                color: white,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                icon: const Icon(Icons.settings_outlined),
              ),
            ]),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                Semantics(
                  label: '$taken de $total doses tomadas',
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: Stack(fit: StackFit.expand, children: [
                      CircularProgressIndicator(
                        value: pct,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        color: const Color(0xFF7FE6A8),
                      ),
                      Center(
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text('$taken/$total',
                                style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(headline,
                        maxLines: 2, style: const TextStyle(color: white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 4),
                    Text(total == 0 ? 'Aproveite o dia.' : '$total dose(s) programada(s) para hoje',
                        style: TextStyle(color: soft, fontSize: 13.5)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                _Pill(icon: Icons.check_circle_rounded, value: taken, label: 'Tomadas', color: const Color(0xFF7FE6A8)),
                const SizedBox(width: 8),
                _Pill(icon: Icons.schedule_rounded, value: remaining, label: 'Restantes', color: const Color(0xFF9FD3FF)),
                const SizedBox(width: 8),
                _Pill(icon: Icons.error_outline_rounded, value: late, label: 'Atrasadas', color: const Color(0xFFFFC266)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color color;
  const _Pill({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          label: '$value $label',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$value', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.1)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _Alert extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  const _Alert({required this.color, required this.icon, required this.title, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      );
}

class _NextDoseCard extends StatelessWidget {
  final DoseView d;
  const _NextDoseCard(this.d);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final snoozed = d.status == DoseStatus.snoozed && d.record?.snoozedUntil != null;
    final target = snoozed ? parseDtKey(d.record!.snoozedUntil!) : d.scheduledAt;
    final diff = target.difference(now);
    final late = d.status == DoseStatus.late;
    final accent = late ? AppColors.pending : Color(d.med.color);
    final when = late
        ? 'Atrasado • ${fmtDuration(diff).replaceFirst('há ', '')}'
        : (snoozed ? 'Adiado • ${fmtDuration(diff)}' : 'Faltam ${fmtDuration(diff).replaceFirst('em ', '')}');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule_rounded, color: accent, size: 22),
                    const SizedBox(width: 6),
                    Text(fmtTime(d.scheduledAt), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: accent, height: 1.1)),
                  ]),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(when, style: TextStyle(fontSize: 12.5, color: accent, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  MedAvatar(d.med, size: 50),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.med.displayName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
                      const SizedBox(height: 2),
                      Text('${d.med.form} • ${d.med.doseDescription}', style: TextStyle(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
                if ((d.med.instructions ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(d.med.instructions!.trim(), style: const TextStyle(fontSize: 13.5))),
                    ]),
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                      onPressed: () => quickTake(context, d),
                      icon: const Icon(Icons.check_rounded),
                      label: const FittedBox(child: Text('Registrar como tomado')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Mais opções (adiar, outro horário, não tomei)',
                    iconSize: 26,
                    style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                    onPressed: () => showDoseSheet(context, d),
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
