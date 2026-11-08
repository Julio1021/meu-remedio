import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/schedule_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Cadastro e edição de medicamento, dividido em etapas curtas.
class MedicationFormScreen extends StatefulWidget {
  final Medication? editing;
  const MedicationFormScreen({super.key, this.editing});

  @override
  State<MedicationFormScreen> createState() => _MedicationFormScreenState();
}

enum _Preset { once, twice, thrice, four, interval, custom }

class _MedicationFormScreenState extends State<MedicationFormScreen> {
  int _step = 0;
  bool _saving = false;

  // Etapa 1
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _ingredient = TextEditingController();
  final _qty = TextEditingController(text: '1');
  String _form = 'Comprimido';
  String _unit = 'comprimido(s)';
  int _color = AppColors.medPalette.first;
  String? _photo;
  bool _prn = false;

  // Etapa 2
  _Preset _preset = _Preset.once;
  List<String> _times = ['08:00'];
  double _intervalH = 8;
  String _intervalStart = '06:00';
  DaysMode _days = DaysMode.daily;
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  int _everyN = 2;
  DateTime _start = dayOnly(DateTime.now());
  bool _continuous = true;
  DateTime? _end;
  final _prnInterval = TextEditingController();
  final _prnMax = TextEditingController();

  // Etapa 3
  bool _stock = false;
  final _stockQty = TextEditingController();
  final _stockMin = TextEditingController();
  String _stockUnit = 'comprimido(s)';
  DateTime? _expiry;

  // Etapa 4
  final _instructions = TextEditingController();
  final _food = TextEditingController();
  final _notes = TextEditingController();
  bool _silent = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.editing;
    if (m == null) return;
    _name.text = m.name;
    _strength.text = m.strength ?? '';
    _ingredient.text = m.activeIngredient ?? '';
    _qty.text = fmtQty(m.doseQty);
    _form = m.form;
    _unit = m.doseUnit;
    _color = m.color;
    _photo = m.photoPath;
    _prn = m.isPrn;
    _prnInterval.text = m.prnMinIntervalHours == null ? '' : fmtQty(m.prnMinIntervalHours!);
    _prnMax.text = m.prnMaxPerDay?.toString() ?? '';
    _stock = m.stockEnabled;
    _stockQty.text = fmtQty(m.stockQty);
    _stockMin.text = fmtQty(m.stockMin);
    _stockUnit = m.stockUnit;
    _expiry = m.expiryDate == null ? null : parseDateKey(m.expiryDate!);
    _instructions.text = m.instructions ?? '';
    _food.text = m.foodNote ?? '';
    _notes.text = m.notes ?? '';
    _silent = m.silent;
    final s = context.read<AppState>().currentSchedule(m.id!);
    if (s != null) {
      _times = [...s.times];
      _intervalH = s.intervalHours;
      _intervalStart = s.intervalStart;
      _days = s.daysMode;
      _weekdays = s.weekdays.toSet();
      _everyN = s.everyN;
      _start = parseDateKey(s.startDate);
      _continuous = s.endDate == null;
      _end = s.endDate == null ? null : parseDateKey(s.endDate!);
      if (s.kind == ScheduleKind.interval) {
        _preset = _Preset.interval;
      } else {
        _preset = switch (_times.length) {
          1 => _Preset.once,
          2 => _Preset.twice,
          3 => _Preset.thrice,
          4 => _Preset.four,
          _ => _Preset.custom,
        };
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _strength, _ingredient, _qty, _prnInterval, _prnMax, _stockQty, _stockMin, _instructions, _food, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(_Preset p) {
    setState(() {
      _preset = p;
      switch (p) {
        case _Preset.once:
          _times = ['08:00'];
        case _Preset.twice:
          _times = ['08:00', '20:00'];
        case _Preset.thrice:
          _times = ['07:00', '13:00', '19:00'];
        case _Preset.four:
          _times = ['06:00', '12:00', '18:00', '22:00'];
        case _Preset.interval:
        case _Preset.custom:
          break;
      }
    });
  }

  String? _validateStep(int step) {
    if (step == 0) {
      if (_name.text.trim().isEmpty) return 'Informe o nome do medicamento.';
      final q = parseQty(_qty.text);
      if (q == null || q <= 0) return 'Informe a quantidade por administração.';
    }
    if (step == 1 && !_prn) {
      if (_preset != _Preset.interval && _times.isEmpty) return 'Adicione pelo menos um horário.';
      if (_preset == _Preset.interval && (_intervalH <= 0 || _intervalH > 168)) return 'Informe um intervalo válido.';
      if (_days == DaysMode.weekdays && _weekdays.isEmpty) return 'Escolha pelo menos um dia da semana.';
      if (!_continuous && _end == null) return 'Informe a data de término ou marque como contínuo.';
      if (!_continuous && _end != null && _end!.isBefore(_start)) return 'A data de término é anterior ao início.';
    }
    if (step == 2 && _stock) {
      final q = parseQty(_stockQty.text);
      if (q == null || q < 0) return 'Informe a quantidade em estoque.';
    }
    return null;
  }

  void _next() {
    final err = _validateStep(_step);
    if (err != null) {
      showSnack(context, err);
      return;
    }
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _save();
    }
  }

  Future<void> _pickPhoto(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1024, imageQuality: 80);
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/med_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(x.path).copy(dest.path);
      setState(() => _photo = dest.path);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível obter a imagem.');
    }
  }

  Future<void> _save() async {
    for (var i = 0; i < 4; i++) {
      final err = _validateStep(i);
      if (err != null) {
        setState(() => _step = i);
        showSnack(context, err);
        return;
      }
    }
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final now = DateTime.now();
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final base = widget.editing ?? Medication(profileId: app.activeProfile!.id!, name: '');
    final med = base.copyWith(
      name: _name.text.trim(),
      strength: opt(_strength) ?? '',
      activeIngredient: opt(_ingredient) ?? '',
      form: _form,
      doseQty: parseQty(_qty.text)!,
      doseUnit: _unit,
      color: _color,
      photoPath: _photo ?? '',
      isPrn: _prn,
      prnMinIntervalHours: parseQty(_prnInterval.text) ?? 0,
      prnMaxPerDay: int.tryParse(_prnMax.text.trim()) ?? 0,
      stockEnabled: _stock,
      stockQty: _stock ? (parseQty(_stockQty.text) ?? 0) : 0,
      stockUnit: _stockUnit,
      stockMin: parseQty(_stockMin.text) ?? 0,
      expiryDate: _expiry == null ? '' : dateKey(_expiry!),
      instructions: opt(_instructions) ?? '',
      foodNote: opt(_food) ?? '',
      notes: opt(_notes) ?? '',
      silent: _silent,
    );
    // Campos vazios são gravados como nulos.
    final clean = Medication.fromMap(med.toMap().map((k, v) => MapEntry(k, v is String && v.isEmpty && k != 'created_at' ? null : v))
      ..['name'] = med.name
      ..['profile_id'] = med.profileId);

    Schedule? sched;
    if (!_prn) {
      final today = dayOnly(now);
      final effFrom = _start.isAfter(today) ? DateTime(_start.year, _start.month, _start.day) : today;
      sched = Schedule(
        medicationId: clean.id ?? 0,
        kind: _preset == _Preset.interval ? ScheduleKind.interval : ScheduleKind.fixed,
        times: ([..._times]..sort()),
        intervalHours: _intervalH,
        intervalStart: _intervalStart,
        daysMode: _preset == _Preset.interval ? DaysMode.daily : _days,
        weekdays: (_weekdays.toList()..sort()),
        everyN: _everyN,
        startDate: dateKey(_start),
        endDate: _continuous || _end == null ? null : dateKey(_end!),
        effectiveFrom: dtKey(effFrom),
      );
    }
    try {
      if (_isEdit) {
        await app.updateMedication(clean, sched);
      } else {
        await app.addMedication(clean, sched);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
          content: Text(_isEdit ? 'Alterações salvas. Lembretes reprogramados.' : '${clean.displayName} cadastrado. Lembretes programados.')));
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) showSnack(context, 'Não foi possível salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Remédio', 'Horários', 'Estoque', 'Detalhes'];
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Editar medicamento' : 'Novo medicamento'),
          leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Fechar', onPressed: () => Navigator.pop(context)),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (i < _step || _validateStep(_step) == null) setState(() => _step = i);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(children: [
                        Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i <= _step ? cs.primary : cs.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(titles[i],
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500,
                              color: i == _step ? cs.primary : cs.onSurfaceVariant,
                            )),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: switch (_step) {
                0 => _stepBasic(),
                1 => _prn ? _stepPrn() : _stepSchedule(),
                2 => _stepStock(),
                _ => _stepDetails(),
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(onPressed: () => setState(() => _step--), child: const Text('Voltar')),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _next,
                    child: _saving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(_step == 3 ? 'Salvar' : 'Continuar'),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- etapa 1
  List<Widget> _stepBasic() => [
        Center(
          child: Stack(clipBehavior: Clip.none, children: [
            _photo != null && File(_photo!).existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.file(File(_photo!), width: 96, height: 96, fit: BoxFit.cover),
                  )
                : Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(color: Color(_color).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(28)),
                    child: Icon(iconForForm(_form), size: 48, color: Color(_color)),
                  ),
            Positioned(
              right: -4,
              bottom: -4,
              child: IconButton.filled(
                tooltip: 'Adicionar foto',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  builder: (c) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                        leading: const Icon(Icons.photo_camera_rounded),
                        title: const Text('Fotografar embalagem'),
                        onTap: () {
                          Navigator.pop(c);
                          _pickPhoto(ImageSource.camera);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library_rounded),
                        title: const Text('Escolher da galeria'),
                        onTap: () {
                          Navigator.pop(c);
                          _pickPhoto(ImageSource.gallery);
                        },
                      ),
                      if (_photo != null)
                        ListTile(
                          leading: const Icon(Icons.delete_outline_rounded),
                          title: const Text('Remover foto'),
                          onTap: () {
                            Navigator.pop(c);
                            setState(() => _photo = null);
                          },
                        ),
                    ]),
                  ),
                ),
                icon: const Icon(Icons.photo_camera_rounded, size: 18),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome comercial *', hintText: 'Ex.: Losartana'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _strength,
              decoration: const InputDecoration(labelText: 'Concentração', hintText: 'Ex.: 50 mg'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _ingredient,
              decoration: const InputDecoration(labelText: 'Princípio ativo'),
            ),
          ),
        ]),
        const SectionTitle('Apresentação'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in medForms)
            ChoiceChip(
              label: Text(f),
              avatar: Icon(iconForForm(f), size: 18),
              selected: _form == f,
              onSelected: (_) => setState(() {
                _form = f;
                _unit = switch (f) {
                  'Comprimido' => 'comprimido(s)',
                  'Cápsula' => 'cápsula(s)',
                  'Gotas' => 'gota(s)',
                  'Solução' || 'Xarope' => 'mL',
                  'Spray' || 'Inalador' => 'jato(s)',
                  'Pomada' || 'Adesivo' => 'aplicação(ões)',
                  'Injetável' => 'mL',
                  _ => _unit,
                };
                _stockUnit = _unit;
              }),
            ),
        ]),
        const SectionTitle('Quantidade por administração'),
        Row(children: [
          SizedBox(
            width: 110,
            child: TextField(
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: doseUnits.contains(_unit) ? _unit : doseUnits.first,
              decoration: const InputDecoration(labelText: 'Unidade'),
              items: [for (final u in doseUnits) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (v) => setState(() {
                _unit = v!;
                _stockUnit = v;
              }),
            ),
          ),
        ]),
        const SectionTitle('Cor de identificação'),
        Wrap(spacing: 10, children: [
          for (final c in AppColors.medPalette)
            Semantics(
              selected: _color == c,
              label: 'Cor',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: _color == c ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
                  ),
                  child: _color == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _prn,
          onChanged: (v) => setState(() => _prn = v),
          title: const Text('Uso eventual (quando necessário)'),
          subtitle: const Text('Sem horários fixos. Você registra cada utilização.'),
        ),
      ];

  // ---------------------------------------------------------------- etapa 2
  Future<String?> _pickTime(String initial) async {
    final (h, m) = parseHm(initial);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return t == null ? null : hm(t.hour, t.minute);
  }

  Future<DateTime?> _pickDate(DateTime initial, {DateTime? first}) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first ?? DateTime(2000),
        lastDate: DateTime(2100),
      );

  List<Widget> _stepSchedule() {
    final cs = Theme.of(context).colorScheme;
    const labels = {
      _Preset.once: '1x ao dia',
      _Preset.twice: '2x ao dia',
      _Preset.thrice: '3x ao dia',
      _Preset.four: '4x ao dia',
      _Preset.interval: 'Intervalo (horas)',
      _Preset.custom: 'Personalizado',
    };
    final preview = _previewSchedule();
    return [
      Text('Os horários devem seguir a orientação do profissional de saúde.', style: TextStyle(color: cs.onSurfaceVariant)),
      const SectionTitle('Frequência'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in _Preset.values) ChoiceChip(label: Text(labels[p]!), selected: _preset == p, onSelected: (_) => _applyPreset(p)),
      ]),
      if (_preset != _Preset.interval) ...[
        const SectionTitle('Horários'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < _times.length; i++)
            InputChip(
              label: Text(_times[i], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              avatar: const Icon(Icons.schedule_rounded, size: 18),
              onPressed: () async {
                final t = await _pickTime(_times[i]);
                if (t != null) {
                  setState(() {
                    _times[i] = t;
                    _times = _times.toSet().toList()..sort();
                  });
                }
              },
              onDeleted: _times.length > 1 ? () => setState(() => _times.removeAt(i)) : null,
              deleteButtonTooltipMessage: 'Remover horário',
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Adicionar horário'),
            onPressed: () async {
              final t = await _pickTime('12:00');
              if (t != null) {
                setState(() {
                  _times = {..._times, t}.toList()..sort();
                  _preset = _Preset.custom;
                });
              }
            },
          ),
        ]),
        const SectionTitle('Dias'),
        SegmentedButton<DaysMode>(
          segments: const [
            ButtonSegment(value: DaysMode.daily, label: Text('Todos')),
            ButtonSegment(value: DaysMode.weekdays, label: Text('Semana')),
            ButtonSegment(value: DaysMode.everyN, label: Text('A cada N')),
          ],
          selected: {_days},
          onSelectionChanged: (v) => setState(() => _days = v.first),
        ),
        const SizedBox(height: 12),
        if (_days == DaysMode.weekdays)
          Wrap(spacing: 6, children: [
            for (var w = 1; w <= 7; w++)
              FilterChip(
                label: Text(weekdayNames[w - 1].substring(0, 3)),
                selected: _weekdays.contains(w),
                onSelected: (v) => setState(() => v ? _weekdays.add(w) : _weekdays.remove(w)),
              ),
          ]),
        if (_days == DaysMode.everyN)
          Row(children: [
            const Text('A cada'),
            IconButton(onPressed: _everyN > 2 ? () => setState(() => _everyN--) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$_everyN', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            IconButton(onPressed: () => setState(() => _everyN++), icon: const Icon(Icons.add_circle_outline)),
            Text(_everyN == 2 ? 'dias (dias alternados)' : 'dias'),
          ]),
      ] else ...[
        const SectionTitle('Intervalo'),
        Row(children: [
          const Text('A cada'),
          IconButton(
              onPressed: _intervalH > 1 ? () => setState(() => _intervalH = _intervalH - 1) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          Text('${fmtQty(_intervalH)} h', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          IconButton(onPressed: () => setState(() => _intervalH = _intervalH + 1), icon: const Icon(Icons.add_circle_outline)),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_rounded),
          title: const Text('Primeiro horário'),
          trailing: Text(_intervalStart, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          onTap: () async {
            final t = await _pickTime(_intervalStart);
            if (t != null) setState(() => _intervalStart = t);
          },
        ),
      ],
      const SectionTitle('Duração do tratamento'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_rounded),
        title: const Text('Início'),
        trailing: Text(fmtDate(_start), style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () async {
          final d = await _pickDate(_start);
          if (d != null) setState(() => _start = d);
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _continuous,
        onChanged: (v) => setState(() => _continuous = v),
        title: const Text('Uso contínuo'),
        subtitle: const Text('Desative para informar a data de término'),
      ),
      if (!_continuous)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_busy_rounded),
          title: const Text('Término (inclusive)'),
          trailing: Text(_end == null ? 'Escolher' : fmtDate(_end!), style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () async {
            final d = await _pickDate(_end ?? _start.add(const Duration(days: 7)), first: _start);
            if (d != null) setState(() => _end = d);
          },
        ),
      if (preview.isNotEmpty) ...[
        const SectionTitle('Próximos horários'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(preview.map((t) => '${fmtWeekdayShort(t)} ${fmtDate(t).substring(0, 5)} • ${fmtTime(t)}').join('\n'),
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.6)),
          ),
        ),
      ],
    ];
  }

  List<DateTime> _previewSchedule() {
    final s = Schedule(
      medicationId: 0,
      kind: _preset == _Preset.interval ? ScheduleKind.interval : ScheduleKind.fixed,
      times: _times,
      intervalHours: _intervalH,
      intervalStart: _intervalStart,
      daysMode: _preset == _Preset.interval ? DaysMode.daily : _days,
      weekdays: _weekdays.toList(),
      everyN: _everyN,
      startDate: dateKey(_start),
      endDate: _continuous || _end == null ? null : dateKey(_end!),
      effectiveFrom: '2000-01-01T00:00',
    );
    final now = DateTime.now();
    return ScheduleEngine.occurrencesBetween([s], now, now.add(const Duration(days: 14))).take(6).toList();
  }

  List<Widget> _stepPrn() => [
        Card(
          color: AppColors.info.withValues(alpha: 0.08),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
                'Medicamento de uso eventual não gera lembretes. Informe somente os limites indicados pelo profissional de saúde; '
                'o aplicativo apenas acompanha esses parâmetros e não recomenda doses.'),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _prnInterval,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Intervalo mínimo entre usos (horas)', hintText: 'Opcional'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _prnMax,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Limite máximo de usos em 24 h', hintText: 'Opcional'),
        ),
      ];

  // ---------------------------------------------------------------- etapa 3
  List<Widget> _stepStock() => [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _stock,
          onChanged: (v) => setState(() => _stock = v),
          title: const Text('Controlar estoque'),
          subtitle: const Text('O estoque é descontado a cada dose confirmada.'),
        ),
        if (_stock) ...[
          const SizedBox(height: 8),
          if (_isEdit && widget.editing!.stockEnabled)
            Text('Saldo atual: ${fmtQty(widget.editing!.stockQty)} ${widget.editing!.stockUnit}. '
                'Para alterá-lo, use Estoque > Ajuste manual.'),
          if (!(_isEdit && widget.editing!.stockEnabled))
            TextField(
              controller: _stockQty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantidade atual', suffixText: _stockUnit),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: doseUnits.contains(_stockUnit) ? _stockUnit : doseUnits.first,
            decoration: const InputDecoration(labelText: 'Unidade de estoque'),
            items: [for (final u in doseUnits) DropdownMenuItem(value: u, child: Text(u))],
            onChanged: (v) => setState(() => _stockUnit = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stockMin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Avisar quando restar', suffixText: _stockUnit),
          ),
        ],
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: const Text('Validade'),
          subtitle: const Text('Opcional — avisaremos 7 dias antes'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_expiry == null ? 'Informar' : fmtDate(_expiry!), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (_expiry != null)
              IconButton(tooltip: 'Remover validade', onPressed: () => setState(() => _expiry = null), icon: const Icon(Icons.close_rounded)),
          ]),
          onTap: () async {
            final d = await _pickDate(_expiry ?? DateTime.now().add(const Duration(days: 180)));
            if (d != null) setState(() => _expiry = d);
          },
        ),
      ];

  // ---------------------------------------------------------------- etapa 4
  List<Widget> _stepDetails() {
    final summary = _prn
        ? 'Uso eventual'
        : (_preset == _Preset.interval
            ? 'A cada ${fmtQty(_intervalH)} h a partir das $_intervalStart'
            : '${_times.length}x ao dia • ${_times.join(', ')}');
    return [
      TextField(
        controller: _instructions,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(labelText: 'Instruções do profissional de saúde', hintText: 'Como consta na prescrição'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _food,
        decoration: const InputDecoration(labelText: 'Observação sobre alimentação', hintText: 'Somente se prescrita'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _notes,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(labelText: 'Anotações pessoais'),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _silent,
        onChanged: (v) => setState(() => _silent = v),
        title: const Text('Lembrete discreto (sem som)'),
      ),
      const SectionTitle('Resumo'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            LabeledValue('Medicamento', [_name.text.trim(), _strength.text.trim()].where((s) => s.isNotEmpty).join(' ')),
            LabeledValue('Apresentação', _form),
            LabeledValue('Quantidade', '${_qty.text} $_unit'),
            LabeledValue('Horários', summary),
            if (!_prn) LabeledValue('Período', _continuous ? 'Desde ${fmtDate(_start)} (contínuo)' : '${fmtDate(_start)} a ${_end == null ? '-' : fmtDate(_end!)}'),
            LabeledValue('Estoque', _stock ? 'Controlado' : 'Não controlado'),
          ]),
        ),
      ),
    ];
  }
}
