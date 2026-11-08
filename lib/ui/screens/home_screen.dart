import 'package:flutter/material.dart';
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final doses = app.today;
    final taken = doses.where((d) => d.status == DoseStatus.taken).length;
    final late = doses.where((d) => d.status == DoseStatus.late || d.status == DoseStatus.missed).length;
    final remaining = doses.where((d) => d.isOpen && d.status != DoseStatus.missed && d.status != DoseStatus.late).length;
    final next = app.nextDose;
    final profile = app.activeProfile!;
    final permOk = app.permissions?.notificationsEnabled ?? true;
    final hasPrn = app.meds.any((m) => m.isPrn && m.status == MedStatus.active);
    final lowStock = app.meds.where((m) => m.stockEnabled && m.status != MedStatus.ended && m.stockQty <= m.stockMin).toList();

    String headline;
    if (doses.isEmpty) {
      headline = 'Nenhuma dose programada para hoje.';
    } else if (late > 0) {
      headline = late == 1 ? 'Há 1 dose aguardando registro.' : 'Há $late doses aguardando registro.';
    } else if (remaining == 0) {
      headline = 'Tudo registrado por hoje!';
    } else {
      headline = 'Seu dia está em dia!';
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => app.refresh(),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 100), children: [
            // Cabeçalho
            Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilesScreen())),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(profile.color).withValues(alpha: 0.18),
                  child: Text(profile.name.characters.first.toUpperCase(),
                      style: TextStyle(color: Color(profile.color), fontWeight: FontWeight.w800, fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${greeting(now)}, ${profile.name.split(' ').first}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(fmtLongDate(now), style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              ),
              IconButton(
                tooltip: 'Central de notificações',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
                icon: Badge(isLabelVisible: !permOk || late > 0, child: const Icon(Icons.notifications_none_rounded)),
              ),
              IconButton(
                tooltip: 'Configurações',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                icon: const Icon(Icons.settings_outlined),
              ),
            ]),
            if (!permOk) ...[
              const SizedBox(height: 16),
              Card(
                color: AppColors.danger.withValues(alpha: 0.08),
                child: ListTile(
                  leading: const Icon(Icons.notifications_off_rounded, color: AppColors.danger),
                  title: const Text('Notificações desativadas'),
                  subtitle: const Text('Os lembretes não aparecerão. Toque para corrigir.'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Resumo diário
            Text(headline, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                StatCard(label: 'Programadas hoje', value: '${doses.length}', color: AppColors.info, icon: Icons.event_note_rounded),
                StatCard(label: 'Tomadas', value: '$taken', color: AppColors.success, icon: Icons.check_circle_rounded),
                StatCard(label: 'Restantes', value: '$remaining', color: AppColors.pending, icon: Icons.schedule_rounded),
                StatCard(label: 'Atrasadas / sem registro', value: '$late', color: AppColors.danger, icon: Icons.error_outline_rounded),
              ],
            ),
            if (doses.isNotEmpty) ...[
              const SizedBox(height: 14),
              Semantics(
                label: '$taken de ${doses.length} doses tomadas',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: doses.isEmpty ? 0 : taken / doses.length,
                    minHeight: 8,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.4),
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
            // Próximo medicamento
            if (next != null) ...[
              const SectionTitle('Próximo medicamento'),
              _NextDoseCard(next),
            ],
            if (lowStock.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: AppColors.pending.withValues(alpha: 0.08),
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_rounded, color: AppColors.pending),
                  title: Text(lowStock.length == 1 ? 'Estoque baixo: ${lowStock.first.displayName}' : 'Estoque baixo em ${lowStock.length} medicamentos'),
                  subtitle: const Text('Confira no controle de estoque.'),
                ),
              ),
            ],
            if (hasPrn) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.back_hand_rounded),
                  title: const Text('Uso eventual'),
                  subtitle: const Text('Registrar um medicamento usado quando necessário'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrnScreen())),
                ),
              ),
            ],
            // Agenda do dia
            const SectionTitle('Agenda de hoje'),
            if (app.meds.isEmpty)
              EmptyState(
                icon: Icons.medication_rounded,
                title: 'Vamos começar?',
                message: 'Cadastre seu primeiro medicamento e configure os horários dos lembretes.',
                action: FilledButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicationFormScreen())),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Cadastrar medicamento'),
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
      ),
    );
  }
}

class _NextDoseCard extends StatelessWidget {
  final DoseView d;
  const _NextDoseCard(this.d);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final target = d.status == DoseStatus.snoozed && d.record?.snoozedUntil != null ? parseDtKey(d.record!.snoozedUntil!) : d.scheduledAt;
    final diff = target.difference(now);
    final late = d.status == DoseStatus.late;
    final bg = late ? AppColors.pending : AppColors.primary;
    return Card(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
              child: Icon(iconForForm(d.med.form), color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.med.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                Text('${d.med.form} • ${d.med.doseDescription}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(fmtTime(d.scheduledAt), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                late ? 'Atrasado • ${fmtDuration(diff)}' : (d.status == DoseStatus.snoozed ? 'Adiado • ${fmtDuration(diff)}' : fmtDuration(diff)),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
            ),
          ]),
          if ((d.med.instructions ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(d.med.instructions!.trim(), style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: bg),
                onPressed: () => quickTake(context, d),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Registrar como tomado'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Mais opções',
              style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18), foregroundColor: Colors.white),
              onPressed: () => showDoseSheet(context, d),
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ]),
        ]),
      ),
    );
  }
}
