import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/view_model.dart';

class LastLayout {
  LastLayout({required this.gridSize, required this.cells});
  final GridSize gridSize;
  final List<String?> cells;

  Map<String, dynamic> toJson() => {
        'gridSize': gridSize.count,
        'cells': cells,
      };

  factory LastLayout.fromJson(Map<String, dynamic> json) {
    final gridSize = GridSize.fromCount((json['gridSize'] as num?)?.toInt() ?? 4);
    final raw = (json['cells'] as List?) ?? const [];
    return LastLayout(
      gridSize: gridSize,
      cells: List<String?>.generate(
        gridSize.count,
        (i) => i < raw.length ? raw[i] as String? : null,
      ),
    );
  }
}

class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  SharedPreferences? _prefs;

  SharedPreferences get p {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('SettingsStore no inicializado');
    }
    return prefs;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---------- Devices (metadata; contraseñas van a SecureStore) ----------

  List<Map<String, dynamic>> get devices {
    final raw = p.getString('devices') ?? '[]';
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDevices(List<Map<String, dynamic>> devices) async {
    await p.setString('devices', jsonEncode(devices));
  }

  // ---------- Views ----------

  List<Map<String, dynamic>> get views {
    final raw = p.getString('views') ?? '[]';
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveViews(List<Map<String, dynamic>> views) async {
    await p.setString('views', jsonEncode(views));
  }

  // ---------- Last view (auto-restore) ----------

  LastLayout? get lastLayout {
    final raw = p.getString('lastLayout');
    if (raw == null) return null;
    try {
      return LastLayout.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastLayout(LastLayout layout) async {
    await p.setString('lastLayout', jsonEncode(layout.toJson()));
  }

  String? get activeViewId => p.getString('activeViewId');

  Future<void> saveActiveViewId(String? id) async {
    if (id == null) {
      await p.remove('activeViewId');
    } else {
      await p.setString('activeViewId', id);
    }
  }

  // ---------- Preferencias ----------

  bool get substreamsInGrid => p.getBool('substreamsInGrid') ?? true;

  Future<void> setSubstreamsInGrid(bool value) async {
    await p.setBool('substreamsInGrid', value);
  }
}