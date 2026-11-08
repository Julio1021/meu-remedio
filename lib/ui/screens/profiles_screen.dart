import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/report_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

const relations = ['Eu', 'Filho(a)', 'Pai', 'Mãe', 'Cônjuge', 'Avô/Avó', 'Familiar', 'Outro'];

/// Gerenciamento de perfis. Cada perfil tem medicamentos, horários, histórico,
/// estoque e lembretes próprios — nunca misturados.
class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  Future<void> _edit(BuildContext context, [Profile? p]) async {
    final name = TextEditingController(text: p?.name ?? '');
    var rel = p?.relation ?? 'Familiar';
    var color = p?.color ?? AppColors.medPalette[1];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(p == null ? 'Novo perfil' : 'Editar perfil'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: relations.contains(rel) ? rel : 'Outro',
                decoration: const InputDecoration(labelText: 'Relação'),
                items: [for (final r in relations) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => set(() => rel = v!),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final c in AppColors.medPalette)
                  GestureDetector(
                    onTap: () => set(() => color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: color == c ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    final app = context.read<AppState>();
    if (p == null) {
      await app.addProfile(Profile(name: name.text.trim(), relation: rel, color: color));
    } else {
      await app.updateProfile(p.copyWith(name: name.text.trim(), relation: rel, color: color));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Perfis')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Novo perfil'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 100), children: [
        Text('Toque para alternar. Cada perfil tem seus próprios medicamentos, histórico, estoque e lembretes.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        for (final p in app.profiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(p.color).withValues(alpha: 0.18),
                  child: Text(p.name.characters.first.toUpperCase(),
                      style: TextStyle(color: Color(p.color), fontWeight: FontWeight.w800)),
                ),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(p.relation),
                selected: p.id == app.activeProfile?.id,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (p.id == app.activeProfile?.id) const Icon(Icons.check_circle_rounded, color: AppColors.success),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') await _edit(context, p);
                      if (v == 'delete' && context.mounted) {
                        if (app.profiles.length == 1) {
                          showSnack(context, 'É preciso manter pelo menos um perfil.');
                          return;
                        }
                        final ok = await confirmDialog(context,
                            title: 'Excluir ${p.name}?',
                            message: 'Todos os medicamentos, históricos e estoques deste perfil serão apagados definitivamente.',
                            confirm: 'Excluir',
                            danger: true);
                        if (ok) await app.deleteProfile(p);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Excluir')),
                    ],
                  ),
                ]),
                onTap: () async {
                  await app.switchProfile(p);
                  if (context.mounted) showSnack(context, 'Perfil ativo: ${p.name}');
                },
              ),
            ),
          ),
      ]),
    );
  }
}

/// Compartilhamento com familiares, cuidadores ou profissionais de saúde.
class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key});

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível compartilhar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final p = app.activeProfile!;
    final inUse = app.meds.where((m) => m.status != MedStatus.ended).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Compartilhamento e cuidadores')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Text('Nada é enviado automaticamente. Os arquivos só são gerados e compartilhados quando você toca nos botões abaixo.',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SectionTitle('Lista de medicamentos em uso'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: Text('PDF — ${p.name}'),
              subtitle: Text('${inUse.length} medicamento(s), horários e instruções cadastradas'),
              enabled: !_busy,
              onTap: () => _run(() async {
                final f = await ReportService.medicationListPdf(p, inUse, app.schedules);
                await ReportService.share(f, 'Medicamentos em uso — ${p.name}');
              }),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_rounded),
              title: const Text('Planilha (CSV)'),
              enabled: !_busy,
              onTap: () => _run(() async {
                final f = await ReportService.medicationListCsv(p, app.meds);
                await ReportService.share(f, 'Medicamentos — ${p.name}');
              }),
            ),
          ]),
        ),
        const SectionTitle('Acompanhamento por cuidador'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('No mesmo aparelho', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Crie um perfil para cada pessoa cuidada (ex.: Pai, Mãe, Filho) em Perfis. '
                  'Os registros de cada perfil ficam separados.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              const Text('À distância', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Envie periodicamente o relatório em PDF (Histórico > Relatórios) ao cuidador autorizado. '
                  'A sincronização em tempo real entre aparelhos exige um servidor e ainda não está disponível nesta versão.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ]),
    );
  }
}
