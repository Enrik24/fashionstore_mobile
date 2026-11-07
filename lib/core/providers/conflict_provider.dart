import 'package:flutter/material.dart';

import '../models/phase2_models.dart';
import '../services/conflict_service.dart';

/// [EXAMEN-2] Conflictos pendientes y acciones de resolución (CU09).
class ConflictProvider extends ChangeNotifier {
  ConflictProvider({required ConflictService service}) : _service = service;

  final ConflictService _service;
  List<ConflictModel> _conflicts = const [];
  bool _loading = false;
  String? _error;

  List<ConflictModel> get conflicts => _conflicts;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  int get pendingCount => _conflicts.where((c) => !c.resuelto).length;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _conflicts = await _service.pendientes();
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> resolver(int id, String accion) async {
    await _service.resolver(id, accion: accion);
    await load();
    return true;
  }

  Future<bool> descartar(int id) async {
    await _service.descartar(id);
    await load();
    return true;
  }

  String traducirMotivo(String motivo) => _service.traducirMotivo(motivo);
}
