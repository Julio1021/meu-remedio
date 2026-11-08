import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../data/models.dart';
import '../domain/analytics.dart';
import '../domain/schedule_engine.dart';

/// Gera e compartilha relatórios (PDF/CSV). O compartilhamento só acontece
/// por ação expressa do usuário.
class ReportService {
  static String _safe(String s) => s.replaceAll('•', '-').replaceAll('→', '->').replaceAll('…', '...');

  static Future<File> _tempFile(String name) async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$name');
  }

  static String _fileStamp(DateTime d) => dateKey(d).replaceAll('-', '');

  static Future<void> share(File f, String text) async {
    await Share.shareXFiles([XFile(f.path)], text: text);
  }

  // -------------------------------------------------------------------- CSV
  static Future<File> dosesCsv(Profile profile, List<DoseView> doses, DateTime from, DateTime to) async {
    final b = StringBuffer();
    b.write('﻿'); // BOM para o Excel reconhecer UTF-8
    b.writeln('Perfil;Medicamento;Dose;Data;Horário programado;Situação;Registrado em;Origem');
    for (final d in doses) {
      final r = d.record;
      final cells = [
        profile.name,
        r?.medName ?? d.med.displayName,
        r?.doseDesc ?? d.med.doseDescription,
        fmtDate(d.scheduledAt),
        fmtTime(d.scheduledAt),
        doseStatusLabels[d.status]!,
        r == null ? '' : fmtDateTime(parseDtKey(r.actionAt)),
        r?.source ?? '',
      ].map((c) => '"${c.replaceAll('"', '""')}"');
      b.writeln(cells.join(';'));
    }
    final f = await _tempFile('doses_${_fileStamp(from)}_${_fileStamp(to)}.csv');
    await f.writeAsString(b.toString(), encoding: utf8);
    return f;
  }

  // -------------------------------------------------------------------- PDF
  static Future<File> adherencePdf({
    required Profile profile,
    required List<DoseView> doses,
    required DateTime from,
    required DateTime to,
  }) async {
    final stats = AdherenceStats.from(doses);
    final byMed = <String, List<DoseView>>{};
    for (final d in doses) {
      byMed.putIfAbsent(d.record?.medName ?? d.med.displayName, () => []).add(d);
    }
    final pct = stats.adherence == null ? '-' : '${(stats.adherence! * 100).toStringAsFixed(0)}%';
    final doc = pw.Document(title: 'Relatório de doses', author: 'Meu Remédio');
    final teal = PdfColor.fromInt(0xFF0F6E6E);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (c) => pw.Text('Meu Remédio - Relatório de doses',
          style: pw.TextStyle(color: teal, fontSize: 10)),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${c.pageNumber} de ${c.pagesCount}', style: const pw.TextStyle(fontSize: 9)),
      ),
      build: (c) => [
        pw.Text(_safe(profile.name), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Período: ${fmtDate(from)} a ${fmtDate(to.subtract(const Duration(days: 1)))}'),
        pw.Text('Gerado em ${fmtDateTime(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Indicador', 'Valor'],
          data: [
            ['Doses programadas (vencidas)', '${stats.scheduled}'],
            ['Registradas como tomadas', '${stats.taken}'],
            ['Confirmadas como não tomadas', '${stats.skipped}'],
            ['Não registradas', '${stats.missed}'],
            ['Em aberto (atrasadas/adiadas)', '${stats.snoozedOrLate}'],
            ['Canceladas', '${stats.cancelled}'],
            ['Percentual registrado como tomado', pct],
          ],
          headerDecoration: pw.BoxDecoration(color: teal),
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '"Não registrada" significa que não houve resposta ao lembrete; é diferente de uma dose confirmada como não tomada.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 16),
        pw.Text('Por medicamento', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Medicamento', 'Tomadas', 'Não tomadas', 'Não registradas', '%'],
          data: byMed.entries.map((e) {
            final st = AdherenceStats.from(e.value);
            return [
              _safe(e.key),
              '${st.taken}',
              '${st.skipped}',
              '${st.missed}',
              st.adherence == null ? '-' : '${(st.adherence! * 100).toStringAsFixed(0)}%',
            ];
          }).toList(),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        ),
        pw.SizedBox(height: 16),
        pw.Text('Registros', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Data', 'Hora', 'Medicamento', 'Situação', 'Registro'],
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          data: doses
              .where((d) => d.status != DoseStatus.pending && d.status != DoseStatus.next)
              .map((d) => [
                    fmtDate(d.scheduledAt),
                    fmtTime(d.scheduledAt),
                    _safe(d.record?.medName ?? d.med.displayName),
                    doseStatusLabels[d.status]!,
                    d.record == null ? '' : fmtTime(parseDtKey(d.record!.actionAt)),
                  ])
              .toList(),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Relatório gerado a partir dos registros feitos pelo usuário. Não substitui orientação profissional.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ));
    final f = await _tempFile('relatorio_${_fileStamp(from)}_${_fileStamp(to)}.pdf');
    await f.writeAsBytes(await doc.save());
    return f;
  }

  /// Lista de medicamentos em uso, para compartilhar com familiares ou
  /// profissionais de saúde.
  static Future<File> medicationListPdf(Profile profile, List<Medication> meds, Map<int, List<Schedule>> schedules) async {
    final doc = pw.Document(title: 'Medicamentos em uso');
    final teal = PdfColor.fromInt(0xFF0F6E6E);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (c) => [
        pw.Text('Medicamentos em uso', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: teal)),
        pw.Text('${_safe(profile.name)} - ${fmtDate(DateTime.now())}'),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Medicamento', 'Apresentação', 'Quantidade', 'Horários', 'Instruções'],
          cellStyle: const pw.TextStyle(fontSize: 9),
          data: meds.map((m) {
            final cur = (schedules[m.id] ?? const <Schedule>[]).where((s) => s.effectiveTo == null).toList();
            final when = m.isPrn ? 'Uso eventual' : (cur.isEmpty ? '-' : _safe(ScheduleEngine.describe(cur.last)));
            return [
              _safe(m.displayName),
              m.form,
              m.doseDescription,
              when,
              _safe([m.instructions, m.foodNote].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ')),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text('Informações cadastradas pelo usuário. Confira sempre com a prescrição e a embalagem.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    final f = await _tempFile('medicamentos_${_fileStamp(DateTime.now())}.pdf');
    await f.writeAsBytes(await doc.save());
    return f;
  }

  static Future<File> medicationListCsv(Profile profile, List<Medication> meds) async {
    final b = StringBuffer('﻿');
    b.writeln('Perfil;Medicamento;Princípio ativo;Apresentação;Quantidade;Situação;Estoque');
    for (final m in meds) {
      b.writeln([
        profile.name,
        m.displayName,
        m.activeIngredient ?? '',
        m.form,
        m.doseDescription,
        m.status.name,
        m.stockEnabled ? '${fmtQty(m.stockQty)} ${m.stockUnit}' : '',
      ].map((c) => '"${c.replaceAll('"', '""')}"').join(';'));
    }
    final f = await _tempFile('medicamentos_${_fileStamp(DateTime.now())}.csv');
    await f.writeAsString(b.toString(), encoding: utf8);
    return f;
  }
}
