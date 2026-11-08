import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/formatters.dart';
import 'models.dart';
import 'settings.dart';

/// Acesso ao banco SQLite local. Funciona totalmente offline.
class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static AppDatabase? _instance;
  static const _version = 1;

  static Future<AppDatabase> open() async {
    if (_instance != null) return _instance!;
    final dir = await getDatabasesPath();
    final database = await openDatabase(
      p.join(dir, 'meu_remedio.db'),
      version: _version,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async => _create(db),
    );
    _instance = AppDatabase._(database);
    return _instance!;
  }

  /// Apenas para testes (sqflite_common_ffi / banco em memória).
  static AppDatabase forTesting(Database db) => _instance = AppDatabase._(db);
  static Future<void> createSchema(Database db) => _create(db);

  static Future<void> _create(Database db) async {
    final b = db.batch();
    b.execute('''CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)''');
    b.execute('''CREATE TABLE profiles(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      relation TEXT,
      color INTEGER
    )''');
    b.execute('''CREATE TABLE medications(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      active_ingredient TEXT,
      form TEXT,
      strength TEXT,
      dose_qty REAL,
      dose_unit TEXT,
      notes TEXT,
      instructions TEXT,
      food_note TEXT,
      photo_path TEXT,
      color INTEGER,
      is_prn INTEGER DEFAULT 0,
      prn_min_interval_h REAL,
      prn_max_per_day INTEGER,
      status TEXT,
      stock_enabled INTEGER DEFAULT 0,
      stock_qty REAL DEFAULT 0,
      stock_unit TEXT,
      stock_min REAL DEFAULT 0,
      expiry_date TEXT,
      silent INTEGER DEFAULT 0,
      favorite INTEGER DEFAULT 0,
      created_at TEXT
    )''');
    b.execute('''CREATE TABLE schedules(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      medication_id INTEGER NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
      kind TEXT,
      times TEXT,
      interval_hours REAL,
      interval_start TEXT,
      days_mode TEXT,
      weekdays TEXT,
      every_n INTEGER,
      start_date TEXT,
      end_date TEXT,
      effective_from TEXT,
      effective_to TEXT
    )''');
    b.execute('''CREATE TABLE dose_records(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
      medication_id INTEGER NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
      med_name TEXT,
      dose_desc TEXT,
      scheduled_at TEXT NOT NULL,
      status TEXT NOT NULL,
      action_at TEXT,
      snoozed_until TEXT,
      source TEXT,
      note TEXT,
      UNIQUE(medication_id, scheduled_at)
    )''');
    b.execute('CREATE INDEX idx_records_profile_time ON dose_records(profile_id, scheduled_at)');
    b.execute('''CREATE TABLE stock_movements(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      medication_id INTEGER NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
      type TEXT,
      qty REAL,
      balance REAL,
      note TEXT,
      created_at TEXT
    )''');
    b.execute('''CREATE TABLE change_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      medication_id INTEGER NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
      description TEXT,
      created_at TEXT
    )''');
    await b.commit(noResult: true);
  }

  static String nowKey() => dtKey(DateTime.now());

  // ---------------------------------------------------------------- settings
  Future<AppSettings> loadSettings() async {
    final rows = await db.query('settings');
    return AppSettings.fromKv({for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''});
  }

  Future<void> saveSettings(AppSettings s) async {
    final b = db.batch();
    s.toKv().forEach((k, v) => b.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace));
    await b.commit(noResult: true);
  }

  // ---------------------------------------------------------------- profiles
  Future<List<Profile>> profiles() async =>
      (await db.query('profiles', orderBy: 'id')).map(Profile.fromMap).toList();

  Future<int> insertProfile(Profile p) => db.insert('profiles', p.toMap()..remove('id'));

  Future<void> updateProfile(Profile p) => db.update('profiles', p.toMap(), where: 'id = ?', whereArgs: [p.id]);

  Future<void> deleteProfile(int id) => db.delete('profiles', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------- medications
  Future<List<Medication>> medications(int profileId) async => (await db.query('medications',
          where: 'profile_id = ?', whereArgs: [profileId], orderBy: 'name COLLATE NOCASE'))
      .map(Medication.fromMap)
      .toList();

  Future<List<Medication>> allMedications() async =>
      (await db.query('medications')).map(Medication.fromMap).toList();

  Future<Medication?> medication(int id) async {
    final r = await db.query('medications', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Medication.fromMap(r.first);
  }

  /// Cria medicamento, regra de horários e saldo inicial de estoque.
  Future<int> insertMedication(Medication m, Schedule? s) async {
    return db.transaction((txn) async {
      final now = nowKey();
      final map = m.copyWith(createdAt: now).toMap()..remove('id');
      final id = await txn.insert('medications', map);
      if (s != null && !m.isPrn) {
        await txn.insert('schedules', (s.copyWith(medicationId: id).toMap()..remove('id')));
      }
      if (m.stockEnabled) {
        await txn.insert('stock_movements', StockMovement(
          medicationId: id,
          type: StockMoveType.initial,
          qty: m.stockQty,
          balance: m.stockQty,
          createdAt: now,
        ).toMap()..remove('id'));
      }
      await txn.insert('change_log', {'medication_id': id, 'description': 'Medicamento cadastrado', 'created_at': now});
      return id;
    });
  }

  /// Atualiza dados. Se a regra de horários mudou, encerra a vigente e cria
  /// uma nova a partir de agora — o histórico anterior é preservado.
  Future<void> updateMedication(Medication m, Schedule? newSchedule) async {
    await db.transaction((txn) async {
      final now = nowKey();
      final oldRows = await txn.query('medications', where: 'id = ?', whereArgs: [m.id]);
      final old = Medication.fromMap(oldRows.first);
      // O saldo de estoque é alterado apenas por movimentações.
      final map = m.copyWith(stockQty: old.stockQty).toMap();
      await txn.update('medications', map, where: 'id = ?', whereArgs: [m.id]);

      final changes = <String>[];
      if (old.name != m.name || old.strength != m.strength) changes.add('nome/dosagem');
      if (old.doseQty != m.doseQty || old.doseUnit != m.doseUnit) {
        changes.add('quantidade por dose (${old.doseDescription} → ${m.doseDescription})');
      }
      if (old.instructions != m.instructions) changes.add('instruções');
      if (!old.stockEnabled && m.stockEnabled) {
        await txn.update('medications', {'stock_qty': m.stockQty}, where: 'id = ?', whereArgs: [m.id]);
        await txn.insert('stock_movements', StockMovement(
          medicationId: m.id!, type: StockMoveType.initial, qty: m.stockQty, balance: m.stockQty, createdAt: now,
        ).toMap()..remove('id'));
        changes.add('controle de estoque ativado');
      }

      if (newSchedule != null && !m.isPrn) {
        final cur = await txn.query('schedules',
            where: 'medication_id = ? AND effective_to IS NULL', whereArgs: [m.id], orderBy: 'id DESC', limit: 1);
        final current = cur.isEmpty ? null : Schedule.fromMap(cur.first);
        if (current == null || !current.sameRuleAs(newSchedule)) {
          if (current != null) {
            await txn.update('schedules', {'effective_to': now}, where: 'id = ?', whereArgs: [current.id]);
          }
          // Tratamento pausado/encerrado: a nova regra fica registrada, porém
          // fechada; ao retomar, ela é a regra reaberta.
          final active = m.status == MedStatus.active;
          await txn.insert(
              'schedules',
              newSchedule
                  .copyWith(medicationId: m.id, effectiveFrom: now, effectiveTo: active ? null : now, clearEffectiveTo: active)
                  .toMap()
                ..remove('id'));
          changes.add('horários (${ScheduleEngineDescribe.of(newSchedule)})');
        }
      }
      if (changes.isNotEmpty) {
        await txn.insert('change_log', {'medication_id': m.id, 'description': 'Alterado: ${changes.join('; ')}', 'created_at': now});
      }
    });
  }

  /// Pausa, retoma ou encerra o tratamento sem apagar o histórico.
  Future<void> setMedicationStatus(int medId, MedStatus status) async {
    await db.transaction((txn) async {
      final now = nowKey();
      final cur = await txn.query('schedules', where: 'medication_id = ?', whereArgs: [medId], orderBy: 'id DESC', limit: 1);
      if (status == MedStatus.active) {
        if (cur.isNotEmpty) {
          final last = Schedule.fromMap(cur.first);
          if (last.effectiveTo != null) {
            await txn.insert('schedules', (last.copyWith(effectiveFrom: now, clearEffectiveTo: true).toMap()..remove('id')));
          }
        }
      } else {
        await txn.update('schedules', {'effective_to': now},
            where: 'medication_id = ? AND effective_to IS NULL', whereArgs: [medId]);
      }
      await txn.update('medications', {'status': status.name}, where: 'id = ?', whereArgs: [medId]);
      const label = {MedStatus.active: 'Tratamento retomado', MedStatus.paused: 'Tratamento pausado', MedStatus.ended: 'Tratamento encerrado'};
      await txn.insert('change_log', {'medication_id': medId, 'description': label[status], 'created_at': now});
    });
  }

  Future<void> setFavorite(int medId, bool fav) =>
      db.update('medications', {'favorite': fav ? 1 : 0}, where: 'id = ?', whereArgs: [medId]);

  Future<void> deleteMedication(int id) => db.delete('medications', where: 'id = ?', whereArgs: [id]);

  // --------------------------------------------------------------- schedules
  Future<List<Schedule>> schedulesFor(int medId) async =>
      (await db.query('schedules', where: 'medication_id = ?', whereArgs: [medId], orderBy: 'id'))
          .map(Schedule.fromMap)
          .toList();

  Future<Map<int, List<Schedule>>> schedulesForProfile(int profileId) async {
    final rows = await db.rawQuery(
        'SELECT s.* FROM schedules s JOIN medications m ON m.id = s.medication_id WHERE m.profile_id = ? ORDER BY s.id',
        [profileId]);
    final out = <int, List<Schedule>>{};
    for (final r in rows) {
      final s = Schedule.fromMap(r);
      out.putIfAbsent(s.medicationId, () => []).add(s);
    }
    return out;
  }

  Future<Map<int, List<Schedule>>> allSchedules() async {
    final out = <int, List<Schedule>>{};
    for (final r in await db.query('schedules', orderBy: 'id')) {
      final s = Schedule.fromMap(r);
      out.putIfAbsent(s.medicationId, () => []).add(s);
    }
    return out;
  }

  // ----------------------------------------------------------------- records
  Future<List<DoseRecord>> recordsBetween(int profileId, DateTime from, DateTime to) async => (await db.query(
        'dose_records',
        where: 'profile_id = ? AND scheduled_at >= ? AND scheduled_at < ?',
        whereArgs: [profileId, dtKey(from), dtKey(to)],
        orderBy: 'scheduled_at',
      ))
          .map(DoseRecord.fromMap)
          .toList();

  Future<List<DoseRecord>> recordsForMed(int medId, {int limit = 200}) async => (await db.query('dose_records',
          where: 'medication_id = ?', whereArgs: [medId], orderBy: 'scheduled_at DESC', limit: limit))
      .map(DoseRecord.fromMap)
      .toList();

  Future<List<DoseRecord>> allRecordsBetween(DateTime from, DateTime to) async => (await db.query('dose_records',
          where: 'scheduled_at >= ? AND scheduled_at < ?', whereArgs: [dtKey(from), dtKey(to)]))
      .map(DoseRecord.fromMap)
      .toList();

  // ------------------------------------------------------------------- stock
  Future<List<StockMovement>> movements(int medId) async => (await db.query('stock_movements',
          where: 'medication_id = ?', whereArgs: [medId], orderBy: 'id DESC'))
      .map(StockMovement.fromMap)
      .toList();

  /// Aplica uma movimentação de estoque (delta positivo = entrada).
  static Future<double> applyStock(DatabaseExecutor ex, int medId, StockMoveType type, double delta, {String? note}) async {
    final r = await ex.query('medications', columns: ['stock_qty'], where: 'id = ?', whereArgs: [medId]);
    final cur = (r.first['stock_qty'] as num?)?.toDouble() ?? 0;
    var next = cur + delta;
    if (next < 0) next = 0;
    await ex.update('medications', {'stock_qty': next}, where: 'id = ?', whereArgs: [medId]);
    await ex.insert('stock_movements', StockMovement(
      medicationId: medId, type: type, qty: delta, balance: next, note: note, createdAt: nowKey(),
    ).toMap()..remove('id'));
    return next;
  }

  Future<double> addStockMovement(int medId, StockMoveType type, double delta, {String? note}) =>
      db.transaction((txn) => applyStock(txn, medId, type, delta, note: note));

  /// Define o saldo exato (ajuste manual).
  Future<void> setStockBalance(int medId, double balance, {String? note}) async {
    await db.transaction((txn) async {
      final r = await txn.query('medications', columns: ['stock_qty'], where: 'id = ?', whereArgs: [medId]);
      final cur = (r.first['stock_qty'] as num?)?.toDouble() ?? 0;
      await applyStock(txn, medId, StockMoveType.adjust, balance - cur, note: note);
    });
  }

  // --------------------------------------------------------------- changelog
  Future<List<ChangeLogEntry>> changeLog(int medId) async => (await db.query('change_log',
          where: 'medication_id = ?', whereArgs: [medId], orderBy: 'id DESC'))
      .map(ChangeLogEntry.fromMap)
      .toList();

  // ------------------------------------------------------- backup / exclusão
  static const _tables = ['profiles', 'medications', 'schedules', 'dose_records', 'stock_movements', 'change_log', 'settings'];

  Future<Map<String, Object?>> exportAll() async => {
        'app': 'meu_remedio',
        'format': 1,
        'exported_at': nowKey(),
        for (final t in _tables) t: await db.query(t),
      };

  Future<void> importAll(Map<String, Object?> data) async {
    if (data['app'] != 'meu_remedio') throw const FormatException('Arquivo de backup inválido.');
    await db.transaction((txn) async {
      for (final t in _tables.reversed) {
        await txn.delete(t);
      }
      for (final t in _tables) {
        final rows = (data[t] as List?) ?? const [];
        for (final r in rows) {
          await txn.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
    });
  }

  Future<void> wipeAll() async {
    await db.transaction((txn) async {
      for (final t in _tables.reversed) {
        await txn.delete(t);
      }
    });
  }
}

/// Pequena ponte para descrever a regra no log sem import circular.
class ScheduleEngineDescribe {
  static String of(Schedule s) {
    if (s.kind == ScheduleKind.interval) return 'a cada ${fmtQty(s.intervalHours)} h desde ${s.intervalStart}';
    return ([...s.times]..sort()).join(', ');
  }
}
