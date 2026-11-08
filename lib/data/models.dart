// Modelos de dados do aplicativo.
//
// Datas de calendário são guardadas como 'yyyy-MM-dd' e horários de dose como
// horário de parede local 'yyyy-MM-ddTHH:mm' (sem fuso). Assim um remédio das
// 08:00 continua às 08:00 mesmo após troca de fuso ou horário de verão.

import '../core/formatters.dart';

class Profile {
  final int? id;
  final String name;
  final String relation; // Eu, Filho, Pai, Mãe, Familiar...
  final int color;

  const Profile({this.id, required this.name, this.relation = 'Eu', this.color = 0xFF0F6E6E});

  Profile copyWith({int? id, String? name, String? relation, int? color}) => Profile(
        id: id ?? this.id,
        name: name ?? this.name,
        relation: relation ?? this.relation,
        color: color ?? this.color,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'relation': relation,
        'color': color,
      };

  factory Profile.fromMap(Map<String, Object?> m) => Profile(
        id: m['id'] as int?,
        name: m['name'] as String,
        relation: (m['relation'] as String?) ?? 'Eu',
        color: (m['color'] as int?) ?? 0xFF0F6E6E,
      );
}

enum MedStatus { active, paused, ended }

const medForms = <String>[
  'Comprimido',
  'Cápsula',
  'Gotas',
  'Solução',
  'Xarope',
  'Pomada',
  'Spray',
  'Injetável',
  'Adesivo',
  'Inalador',
  'Outro',
];

const doseUnits = <String>[
  'comprimido(s)',
  'cápsula(s)',
  'gota(s)',
  'mL',
  'colher(es)',
  'jato(s)',
  'aplicação(ões)',
  'unidade(s)',
  'UI',
  'sachê(s)',
];

class Medication {
  final int? id;
  final int profileId;
  final String name;
  final String? activeIngredient;
  final String form;
  final String? strength; // ex.: 50 mg
  final double doseQty; // quantidade por administração
  final String doseUnit;
  final String? notes; // observações pessoais
  final String? instructions; // instruções do profissional
  final String? foodNote; // observação sobre alimentação, quando prescrita
  final String? photoPath;
  final int color;
  final bool isPrn; // uso eventual (quando necessário)
  final double? prnMinIntervalHours;
  final int? prnMaxPerDay;
  final MedStatus status;
  final bool stockEnabled;
  final double stockQty;
  final String stockUnit;
  final double stockMin;
  final String? expiryDate; // yyyy-MM-dd
  final bool silent; // notificação sem som
  final bool favorite;
  final String createdAt;

  const Medication({
    this.id,
    required this.profileId,
    required this.name,
    this.activeIngredient,
    this.form = 'Comprimido',
    this.strength,
    this.doseQty = 1,
    this.doseUnit = 'comprimido(s)',
    this.notes,
    this.instructions,
    this.foodNote,
    this.photoPath,
    this.color = 0xFF0F6E6E,
    this.isPrn = false,
    this.prnMinIntervalHours,
    this.prnMaxPerDay,
    this.status = MedStatus.active,
    this.stockEnabled = false,
    this.stockQty = 0,
    this.stockUnit = 'comprimido(s)',
    this.stockMin = 0,
    this.expiryDate,
    this.silent = false,
    this.favorite = false,
    this.createdAt = '',
  });

  String get displayName => strength == null || strength!.trim().isEmpty ? name : '$name ${strength!.trim()}';

  String get doseDescription => '${fmtQty(doseQty)} $doseUnit';

  Medication copyWith({
    int? id,
    int? profileId,
    String? name,
    String? activeIngredient,
    String? form,
    String? strength,
    double? doseQty,
    String? doseUnit,
    String? notes,
    String? instructions,
    String? foodNote,
    String? photoPath,
    int? color,
    bool? isPrn,
    double? prnMinIntervalHours,
    int? prnMaxPerDay,
    MedStatus? status,
    bool? stockEnabled,
    double? stockQty,
    String? stockUnit,
    double? stockMin,
    String? expiryDate,
    bool? silent,
    bool? favorite,
    String? createdAt,
  }) =>
      Medication(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        name: name ?? this.name,
        activeIngredient: activeIngredient ?? this.activeIngredient,
        form: form ?? this.form,
        strength: strength ?? this.strength,
        doseQty: doseQty ?? this.doseQty,
        doseUnit: doseUnit ?? this.doseUnit,
        notes: notes ?? this.notes,
        instructions: instructions ?? this.instructions,
        foodNote: foodNote ?? this.foodNote,
        photoPath: photoPath ?? this.photoPath,
        color: color ?? this.color,
        isPrn: isPrn ?? this.isPrn,
        prnMinIntervalHours: prnMinIntervalHours ?? this.prnMinIntervalHours,
        prnMaxPerDay: prnMaxPerDay ?? this.prnMaxPerDay,
        status: status ?? this.status,
        stockEnabled: stockEnabled ?? this.stockEnabled,
        stockQty: stockQty ?? this.stockQty,
        stockUnit: stockUnit ?? this.stockUnit,
        stockMin: stockMin ?? this.stockMin,
        expiryDate: expiryDate ?? this.expiryDate,
        silent: silent ?? this.silent,
        favorite: favorite ?? this.favorite,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'name': name,
        'active_ingredient': activeIngredient,
        'form': form,
        'strength': strength,
        'dose_qty': doseQty,
        'dose_unit': doseUnit,
        'notes': notes,
        'instructions': instructions,
        'food_note': foodNote,
        'photo_path': photoPath,
        'color': color,
        'is_prn': isPrn ? 1 : 0,
        'prn_min_interval_h': prnMinIntervalHours,
        'prn_max_per_day': prnMaxPerDay,
        'status': status.name,
        'stock_enabled': stockEnabled ? 1 : 0,
        'stock_qty': stockQty,
        'stock_unit': stockUnit,
        'stock_min': stockMin,
        'expiry_date': expiryDate,
        'silent': silent ? 1 : 0,
        'favorite': favorite ? 1 : 0,
        'created_at': createdAt,
      };

  factory Medication.fromMap(Map<String, Object?> m) => Medication(
        id: m['id'] as int?,
        profileId: m['profile_id'] as int,
        name: m['name'] as String,
        activeIngredient: m['active_ingredient'] as String?,
        form: (m['form'] as String?) ?? 'Comprimido',
        strength: m['strength'] as String?,
        doseQty: (m['dose_qty'] as num?)?.toDouble() ?? 1,
        doseUnit: (m['dose_unit'] as String?) ?? 'comprimido(s)',
        notes: m['notes'] as String?,
        instructions: m['instructions'] as String?,
        foodNote: m['food_note'] as String?,
        photoPath: m['photo_path'] as String?,
        color: (m['color'] as int?) ?? 0xFF0F6E6E,
        isPrn: (m['is_prn'] as int? ?? 0) == 1,
        prnMinIntervalHours: (m['prn_min_interval_h'] as num?)?.toDouble(),
        prnMaxPerDay: m['prn_max_per_day'] as int?,
        status: MedStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => MedStatus.active),
        stockEnabled: (m['stock_enabled'] as int? ?? 0) == 1,
        stockQty: (m['stock_qty'] as num?)?.toDouble() ?? 0,
        stockUnit: (m['stock_unit'] as String?) ?? 'comprimido(s)',
        stockMin: (m['stock_min'] as num?)?.toDouble() ?? 0,
        expiryDate: m['expiry_date'] as String?,
        silent: (m['silent'] as int? ?? 0) == 1,
        favorite: (m['favorite'] as int? ?? 0) == 1,
        createdAt: (m['created_at'] as String?) ?? '',
      );
}

enum ScheduleKind { fixed, interval }

enum DaysMode { daily, weekdays, everyN }

/// Regra de horários de um tratamento. Cada alteração no tratamento fecha a
/// regra vigente (effectiveTo) e cria outra, preservando o histórico.
class Schedule {
  final int? id;
  final int medicationId;
  final ScheduleKind kind;
  final List<String> times; // 'HH:mm' (kind == fixed)
  final double intervalHours; // kind == interval
  final String intervalStart; // 'HH:mm'
  final DaysMode daysMode;
  final List<int> weekdays; // 1 = segunda ... 7 = domingo
  final int everyN;
  final String startDate; // yyyy-MM-dd
  final String? endDate; // yyyy-MM-dd, inclusive
  final String effectiveFrom; // yyyy-MM-ddTHH:mm
  final String? effectiveTo;

  const Schedule({
    this.id,
    required this.medicationId,
    this.kind = ScheduleKind.fixed,
    this.times = const ['08:00'],
    this.intervalHours = 8,
    this.intervalStart = '06:00',
    this.daysMode = DaysMode.daily,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.everyN = 2,
    required this.startDate,
    this.endDate,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  bool get isContinuous => endDate == null;

  Schedule copyWith({
    int? id,
    int? medicationId,
    ScheduleKind? kind,
    List<String>? times,
    double? intervalHours,
    String? intervalStart,
    DaysMode? daysMode,
    List<int>? weekdays,
    int? everyN,
    String? startDate,
    String? endDate,
    bool clearEndDate = false,
    String? effectiveFrom,
    String? effectiveTo,
    bool clearEffectiveTo = false,
  }) =>
      Schedule(
        id: id ?? this.id,
        medicationId: medicationId ?? this.medicationId,
        kind: kind ?? this.kind,
        times: times ?? this.times,
        intervalHours: intervalHours ?? this.intervalHours,
        intervalStart: intervalStart ?? this.intervalStart,
        daysMode: daysMode ?? this.daysMode,
        weekdays: weekdays ?? this.weekdays,
        everyN: everyN ?? this.everyN,
        startDate: startDate ?? this.startDate,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        effectiveFrom: effectiveFrom ?? this.effectiveFrom,
        effectiveTo: clearEffectiveTo ? null : (effectiveTo ?? this.effectiveTo),
      );

  /// Duas regras são equivalentes quando geram os mesmos horários.
  bool sameRuleAs(Schedule o) =>
      kind == o.kind &&
      times.join(',') == o.times.join(',') &&
      intervalHours == o.intervalHours &&
      intervalStart == o.intervalStart &&
      daysMode == o.daysMode &&
      weekdays.join(',') == o.weekdays.join(',') &&
      everyN == o.everyN &&
      startDate == o.startDate &&
      endDate == o.endDate;

  Map<String, Object?> toMap() => {
        'id': id,
        'medication_id': medicationId,
        'kind': kind.name,
        'times': times.join(','),
        'interval_hours': intervalHours,
        'interval_start': intervalStart,
        'days_mode': daysMode.name,
        'weekdays': weekdays.join(','),
        'every_n': everyN,
        'start_date': startDate,
        'end_date': endDate,
        'effective_from': effectiveFrom,
        'effective_to': effectiveTo,
      };

  factory Schedule.fromMap(Map<String, Object?> m) {
    List<String> splitS(String? s) => (s == null || s.isEmpty) ? <String>[] : s.split(',');
    return Schedule(
      id: m['id'] as int?,
      medicationId: m['medication_id'] as int,
      kind: ScheduleKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => ScheduleKind.fixed),
      times: splitS(m['times'] as String?),
      intervalHours: (m['interval_hours'] as num?)?.toDouble() ?? 8,
      intervalStart: (m['interval_start'] as String?) ?? '06:00',
      daysMode: DaysMode.values.firstWhere((d) => d.name == m['days_mode'], orElse: () => DaysMode.daily),
      weekdays: splitS(m['weekdays'] as String?).map(int.parse).toList(),
      everyN: (m['every_n'] as int?) ?? 2,
      startDate: m['start_date'] as String,
      endDate: m['end_date'] as String?,
      effectiveFrom: m['effective_from'] as String,
      effectiveTo: m['effective_to'] as String?,
    );
  }
}

/// Situação registrada de uma dose.
enum RecordStatus { taken, skipped, snoozed, cancelled }

class DoseRecord {
  final int? id;
  final int profileId;
  final int medicationId;
  final String medName; // cópia para preservar o histórico
  final String doseDesc;
  final String scheduledAt; // yyyy-MM-ddTHH:mm
  final RecordStatus status;
  final String actionAt; // momento do registro
  final String? snoozedUntil;
  final String source; // notificacao, aplicativo, eventual
  final String? note;

  const DoseRecord({
    this.id,
    required this.profileId,
    required this.medicationId,
    required this.medName,
    required this.doseDesc,
    required this.scheduledAt,
    required this.status,
    required this.actionAt,
    this.snoozedUntil,
    this.source = 'aplicativo',
    this.note,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'medication_id': medicationId,
        'med_name': medName,
        'dose_desc': doseDesc,
        'scheduled_at': scheduledAt,
        'status': status.name,
        'action_at': actionAt,
        'snoozed_until': snoozedUntil,
        'source': source,
        'note': note,
      };

  factory DoseRecord.fromMap(Map<String, Object?> m) => DoseRecord(
        id: m['id'] as int?,
        profileId: m['profile_id'] as int,
        medicationId: m['medication_id'] as int,
        medName: m['med_name'] as String,
        doseDesc: (m['dose_desc'] as String?) ?? '',
        scheduledAt: m['scheduled_at'] as String,
        status: RecordStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => RecordStatus.taken),
        actionAt: m['action_at'] as String,
        snoozedUntil: m['snoozed_until'] as String?,
        source: (m['source'] as String?) ?? 'aplicativo',
        note: m['note'] as String?,
      );
}

enum StockMoveType { initial, purchase, adjust, loss, dose, doseUndo }

const stockMoveLabels = {
  StockMoveType.initial: 'Estoque inicial',
  StockMoveType.purchase: 'Compra / entrada',
  StockMoveType.adjust: 'Ajuste manual',
  StockMoveType.loss: 'Perda ou descarte',
  StockMoveType.dose: 'Dose registrada',
  StockMoveType.doseUndo: 'Registro desfeito',
};

class StockMovement {
  final int? id;
  final int medicationId;
  final StockMoveType type;
  final double qty; // variação (+ entrada, - saída)
  final double balance; // saldo após a movimentação
  final String? note;
  final String createdAt;

  const StockMovement({
    this.id,
    required this.medicationId,
    required this.type,
    required this.qty,
    required this.balance,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'medication_id': medicationId,
        'type': type.name,
        'qty': qty,
        'balance': balance,
        'note': note,
        'created_at': createdAt,
      };

  factory StockMovement.fromMap(Map<String, Object?> m) => StockMovement(
        id: m['id'] as int?,
        medicationId: m['medication_id'] as int,
        type: StockMoveType.values.firstWhere((t) => t.name == m['type'], orElse: () => StockMoveType.adjust),
        qty: (m['qty'] as num).toDouble(),
        balance: (m['balance'] as num).toDouble(),
        note: m['note'] as String?,
        createdAt: m['created_at'] as String,
      );
}

class ChangeLogEntry {
  final int? id;
  final int medicationId;
  final String description;
  final String createdAt;

  const ChangeLogEntry({this.id, required this.medicationId, required this.description, required this.createdAt});

  factory ChangeLogEntry.fromMap(Map<String, Object?> m) => ChangeLogEntry(
        id: m['id'] as int?,
        medicationId: m['medication_id'] as int,
        description: m['description'] as String,
        createdAt: m['created_at'] as String,
      );
}
