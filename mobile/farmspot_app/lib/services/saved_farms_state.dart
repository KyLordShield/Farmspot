import 'package:flutter/foundation.dart';
import '../models/saved_farm.dart';
import 'saved_farms_service.dart';
import 'session_state.dart';

/// One account-scoped saved list shared by map, farm profile, and Saved Farms.
class SavedFarmsState extends ChangeNotifier {
  final SavedFarmsGateway gateway;
  SavedFarmsState({SavedFarmsGateway? gateway})
    : gateway = gateway ?? SavedFarmsService.instance {
    _owner = SessionState.instance.user?['USR_ID']?.toString();
    SessionState.instance.addListener(_syncOwner);
  }
  static final instance = SavedFarmsState();
  String? _owner;
  int _epoch = 0;
  int _revision = 0;
  List<SavedFarm> _farms = [];
  final Set<String> _busy = {};
  bool _loaded = false;
  Future<void>? _pending;
  List<SavedFarm> get farms => List.unmodifiable(_farms);
  bool isSaved(String id) => _farms.any((f) => f.id == id);
  bool isBusy(String id) => _busy.contains(id);

  void _syncOwner() {
    final owner = SessionState.instance.user?['USR_ID']?.toString();
    if (owner == _owner) return;
    _owner = owner;
    _epoch++;
    _farms = [];
    _busy.clear();
    _loaded = false;
    _pending = null;
    notifyListeners();
  }

  Future<void> load({bool refresh = false}) {
    _syncOwner();
    if (_owner == null)
      return Future.error(Exception('Please sign in to use Saved Farms.'));
    if (_pending != null) return _pending!;
    if (_loaded && !refresh) return Future.value();
    final epoch = _epoch;
    final task = _fetch(epoch);
    _pending = task;
    return task.whenComplete(() {
      if (epoch == _epoch) _pending = null;
    });
  }

  Future<void> _fetch(int epoch) async {
    final revision = _revision;
    final rows = await gateway.fetchSavedFarms();
    if (epoch != _epoch)
      throw Exception('Your account changed. Please try again.');
    if (revision != _revision) return;
    _farms = rows;
    _loaded = true;
    notifyListeners();
  }

  Future<bool> toggle(String id) async {
    _syncOwner();
    if (_busy.contains(id)) return isSaved(id);
    final epoch = _epoch;
    _busy.add(id);
    notifyListeners();
    try {
      await load();
      if (epoch != _epoch)
        throw Exception('Your account changed. Please try again.');
      final remove = isSaved(id);
      if (remove) {
        await gateway.removeFarm(id);
      } else {
        final farm = await gateway.saveFarm(id);
        if (epoch == _epoch)
          _farms = [farm, ..._farms.where((f) => f.id != id)];
      }
      if (epoch != _epoch)
        throw Exception('Your account changed. Please try again.');
      _revision++;
      if (remove) _farms = _farms.where((f) => f.id != id).toList();
      notifyListeners();
      return !remove;
    } finally {
      if (epoch == _epoch) {
        _busy.remove(id);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    SessionState.instance.removeListener(_syncOwner);
    _epoch++;
    super.dispose();
  }
}
