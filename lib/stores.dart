import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'tmdb_service.dart';

Future<String> appVersion() async {
  try {
    final PackageInfo i = await PackageInfo.fromPlatform();
    return i.version.isEmpty ? kVersionFallback : i.version;
  } catch (_) {
    return kVersionFallback;
  }
}

// ═════════════════════════════ WATCHLIST ═════════════════════════════
/// Player/details screen se bhi use karo:  WatchlistStore.I.toggle(item);
class WatchlistStore extends ChangeNotifier {
  WatchlistStore._();
  static final WatchlistStore I = WatchlistStore._();
  static const String _k = 'hannu_watchlist_v1';

  final List<TmdbItem> _items = <TmdbItem>[];
  bool _loaded = false;

  List<TmdbItem> get items => List<TmdbItem>.unmodifiable(_items);
  int get length => _items.length;
  bool contains(TmdbItem i) => _items.any((TmdbItem e) => e.key == i.key);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String? raw = p.getString(_k);
      if (raw == null) return;
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(list
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> m) => TmdbItem.fromStored(Map<String, dynamic>.from(m))));
      notifyListeners();
    } catch (e) {
      debugPrint('watchlist load error: $e');
    }
  }

  Future<void> toggle(TmdbItem i) async {
    if (contains(i)) {
      _items.removeWhere((TmdbItem e) => e.key == i.key);
    } else {
      _items.insert(0, i);
    }
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(_k, json.encode(_items.map((TmdbItem e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('watchlist save error: $e');
    }
  }
}

// ═════════════════════════════ CONTINUE WATCHING ═════════════════════════════
class CwEntry {
  final TmdbItem item;
  final int positionMs;
  final int durationMs;
  final int? season;
  final int? episode;
  final int updatedAt;
  const CwEntry({
    required this.item,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.season,
    this.episode,
  });

  double get progress =>
      durationMs <= 0 ? 0.0 : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

  String? get label => (season != null && episode != null) ? 'S$season · E$episode' : null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item': item.toJson(),
        'pos': positionMs,
        'dur': durationMs,
        's': season,
        'e': episode,
        'ts': updatedAt,
      };

  factory CwEntry.fromJson(Map<String, dynamic> j) => CwEntry(
        item: TmdbItem.fromStored(Map<String, dynamic>.from(j['item'] as Map<dynamic, dynamic>)),
        positionMs: (j['pos'] as num?)?.toInt() ?? 0,
        durationMs: (j['dur'] as num?)?.toInt() ?? 0,
        season: (j['s'] as num?)?.toInt(),
        episode: (j['e'] as num?)?.toInt(),
        updatedAt: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

/// PLAYER se call karo (har ~10 sec + pause/exit par):
///   ContinueWatchingStore.I.update(item, positionMs: p, durationMs: d,
///       season: s, episode: e, isLastEpisode: <series ka aakhri episode?>);
/// Movie 95% dekhne par, ya series ka aakhri episode 95% par → list se hat jati hai.
/// Adhi dekhi series tab tak rehti hai jab tak puri khatam na ho.
class ContinueWatchingStore extends ChangeNotifier {
  ContinueWatchingStore._();
  static final ContinueWatchingStore I = ContinueWatchingStore._();
  static const String _k = 'hannu_cw_v1';

  final List<CwEntry> _entries = <CwEntry>[];
  bool _loaded = false;

  List<CwEntry> get entries {
    final List<CwEntry> l = List<CwEntry>.of(_entries);
    l.sort((CwEntry a, CwEntry b) => b.updatedAt.compareTo(a.updatedAt));
    return l;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String? raw = p.getString(_k);
      if (raw == null) return;
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(list
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> m) => CwEntry.fromJson(Map<String, dynamic>.from(m))));
      notifyListeners();
    } catch (e) {
      debugPrint('cw load error: $e');
    }
  }

  Future<void> update(
    TmdbItem item, {
    required int positionMs,
    required int durationMs,
    int? season,
    int? episode,
    bool isLastEpisode = false,
  }) async {
    final bool done = durationMs > 0 && positionMs / durationMs >= 0.95;
    if (done && (!item.isTv || isLastEpisode)) {
      await remove(item);
      return;
    }
    _entries.removeWhere((CwEntry e) => e.item.key == item.key);
    _entries.add(CwEntry(
      item: item,
      positionMs: positionMs,
      durationMs: durationMs,
      season: season,
      episode: episode,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    notifyListeners();
    await _save();
  }

  Future<void> remove(TmdbItem item) async {
    _entries.removeWhere((CwEntry e) => e.item.key == item.key);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(_k, json.encode(_entries.map((CwEntry e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('cw save error: $e');
    }
  }
}

// ═════════════════════════════ NOTIFICATIONS (24h) + UPDATE ═════════════════════════════
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? url;
  final String? image;
  final int ts;
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.ts,
    this.url,
    this.image,
  });

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'id': id, 'title': title, 'body': body, 'url': url, 'image': image, 'ts': ts};

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        url: j['url'] as String?,
        image: j['image'] as String?,
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );

  static AppNotification? fromMessage(RemoteMessage m) {
    final String title = (m.notification?.title ?? m.data['title'] ?? '').toString();
    final String body = (m.notification?.body ?? m.data['body'] ?? '').toString();
    if (title.isEmpty && body.isEmpty) return null;
    final int ts = (m.sentTime ?? DateTime.now()).millisecondsSinceEpoch;
    final String? url = (m.data['url'] ?? m.data['link'])?.toString();
    final String? image = (m.notification?.android?.imageUrl ?? m.notification?.apple?.imageUrl ?? m.data['image'])?.toString();
    return AppNotification(
      id: m.messageId ?? '${ts}_$title',
      title: title.isEmpty ? 'HANNUTV' : title,
      body: body,
      ts: ts,
      url: url,
      image: image,
    );
  }
}

class UpdateInfo {
  final String version;
  final String url;
  const UpdateInfo(this.version, this.url);
}

const int _day = 24 * 60 * 60 * 1000;

/// main.dart me ek baar register karo:
///   FirebaseMessaging.onBackgroundMessage(hannuBackgroundHandler);
@pragma('vm:entry-point')
Future<void> hannuBackgroundHandler(RemoteMessage m) async {
  final AppNotification? n = AppNotification.fromMessage(m);
  if (n != null) await NotificationStore.appendRaw(n);
}

class NotificationStore extends ChangeNotifier {
  NotificationStore._();
  static final NotificationStore I = NotificationStore._();
  static const String _k = 'hannu_notifs_v1';

  final List<AppNotification> _all = <AppNotification>[];
  UpdateInfo? update;
  bool _inited = false;

  /// Sirf pichle 24 ghante ke notifications.
  List<AppNotification> get active {
    final int cut = DateTime.now().millisecondsSinceEpoch - _day;
    final List<AppNotification> l = _all.where((AppNotification n) => n.ts >= cut).toList();
    l.sort((AppNotification a, AppNotification b) => b.ts.compareTo(a.ts));
    return l;
  }

  int get badge => active.length + (update != null ? 1 : 0);

  static Future<void> appendRaw(AppNotification n) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.reload(); // background isolate ne likha ho to latest padho
      final List<AppNotification> list = _decode(p.getString(_k));
      if (list.any((AppNotification e) => e.id == n.id)) return;
      list.add(n);
      final int cut = DateTime.now().millisecondsSinceEpoch - _day;
      list.removeWhere((AppNotification e) => e.ts < cut);
      await p.setString(_k, json.encode(list.map((AppNotification e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('notif append error: $e');
    }
  }

  static List<AppNotification> _decode(String? raw) {
    if (raw == null) return <AppNotification>[];
    try {
      final List<dynamic> l = json.decode(raw) as List<dynamic>;
      return l
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> m) => AppNotification.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return <AppNotification>[];
    }
  }

  Future<void> _reload() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.reload();
      _all
        ..clear()
        ..addAll(_decode(p.getString(_k)));
      notifyListeners();
    } catch (e) {
      debugPrint('notif load error: $e');
    }
  }

  Future<void> _onMessage(RemoteMessage m) async {
    final AppNotification? n = AppNotification.fromMessage(m);
    if (n == null) return;
    await appendRaw(n);
    await _reload();
  }

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    await _reload();
    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen(_onMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessage);
      final RemoteMessage? first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) await _onMessage(first);
    } catch (e) {
      debugPrint('fcm listen error: $e');
    }
    unawaited(_checkUpdate());
  }

  /// Firebase Remote Config keys:  latest_version (e.g. "1.3.0")  &  update_url (hannutv direct link)
  Future<void> _checkUpdate() async {
    try {
      final FirebaseRemoteConfig rc = FirebaseRemoteConfig.instance;
      await rc.fetchAndActivate();
      final String latest = rc.getString('latest_version').trim();
      final String url = rc.getString('update_url').trim();
      final String cur = await appVersion();
      update = (latest.isNotEmpty && _cmp(latest, cur) > 0)
          ? UpdateInfo(latest, url.isEmpty ? kUpdateUrlFallback : url)
          : null;
      notifyListeners();
    } catch (e) {
      debugPrint('update check error: $e');
    }
  }

  static int _cmp(String a, String b) {
    List<int> parts(String s) => s
        .split('+')
        .first
        .split('.')
        .map((String e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final List<int> x = parts(a);
    final List<int> y = parts(b);
    for (int i = 0; i < 3; i++) {
      final int xi = i < x.length ? x[i] : 0;
      final int yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi.compareTo(yi);
    }
    return 0;
  }
}