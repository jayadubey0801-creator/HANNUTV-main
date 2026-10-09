import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Watchlist jo bina login ke kaam karti hai (phone me local save hoti hai).
/// Dashboard me dikhane ke liye:
///   ValueListenableBuilder<List<Map<String, dynamic>>>(
///     valueListenable: WatchlistService.instance.items,
///     builder: (context, list, _) => ... list ko grid/list me dikhao ...
///   )
/// Har item me: id, mediaType ('movie' / 'tv'), title, year, rating, overview, posterUrl, addedAt
class WatchlistService {
  WatchlistService._();
  static final WatchlistService instance = WatchlistService._();

  static const String _prefsKey = 'hannutv_watchlist_v1';

  final ValueNotifier<List<Map<String, dynamic>>> items =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);

  Future<void>? _loading;

  Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = json.decode(raw);
        if (decoded is List) {
          items.value = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, json.encode(items.value));
    } catch (_) {}
  }

  String _normType(dynamic t) => (t == 'tv' || t == 'series') ? 'tv' : 'movie';

  bool contains(int id, String mediaType) {
    final String type = _normType(mediaType);
    return items.value.any((e) => e['id'] == id && e['mediaType'] == type);
  }

  /// true = add ho gaya, false = remove ho gaya
  Future<bool> toggle(Map<String, dynamic> item) async {
    await ensureLoaded();
    final dynamic id = item['id'];
    final String type = _normType(item['mediaType']);
    final List<Map<String, dynamic>> list =
        List<Map<String, dynamic>>.from(items.value);
    final int idx =
        list.indexWhere((e) => e['id'] == id && e['mediaType'] == type);
    bool added;
    if (idx >= 0) {
      list.removeAt(idx);
      added = false;
    } else {
      final Map<String, dynamic> copy = Map<String, dynamic>.from(item);
      copy['mediaType'] = type;
      copy['addedAt'] = DateTime.now().millisecondsSinceEpoch;
      list.insert(0, copy);
      added = true;
    }
    items.value = list;
    await _save();
    return added;
  }

  Future<void> remove(int id, String mediaType) async {
    await ensureLoaded();
    final String type = _normType(mediaType);
    final List<Map<String, dynamic>> list =
        List<Map<String, dynamic>>.from(items.value);
    list.removeWhere((e) => e['id'] == id && e['mediaType'] == type);
    items.value = list;
    await _save();
  }
}
