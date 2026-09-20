import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class HistoryEntry {
  final String input;
  final DateTime timestamp;

  const HistoryEntry({
    required this.input,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'input': input,
        'timestamp': timestamp.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      input: json['input'] as String? ?? '',
      timestamp: DateTime.tryParse(
            json['timestamp'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }
}

class HistoryStore {
  final String filePath;

  HistoryStore({String? filePath})
      : filePath = filePath ??
            p.join(
              Platform.environment['USERPROFILE'] ?? '.',
              '.levai_scout',
              'history.json',
            );

  Future<List<HistoryEntry>> load() async {
    final file = File(filePath);

    if (!await file.exists()) {
      return [];
    }

    try {
      final data = jsonDecode(
        await file.readAsString(),
      );

      if (data is! List) {
        return [];
      }

      return data
          .whereType<Map>()
          .map(
            (item) => HistoryEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(String input) async {
    final value = input.trim();

    if (value.isEmpty) {
      return;
    }

    final entries = await load();

    entries.add(
      HistoryEntry(
        input: value,
        timestamp: DateTime.now(),
      ),
    );

    final recent =
        entries.length > 100 ? entries.sublist(entries.length - 100) : entries;

    final file = File(filePath);
    await file.parent.create(recursive: true);

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        recent.map((e) => e.toJson()).toList(),
      ),
    );
  }

  Future<void> clear() async {
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }
  }
}
