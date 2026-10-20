import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'tmdb_service.dart';

Future<String> appVersion() async => kVersionFallback;

class UpdateInfo {
  final String version;
  final String url;
  final String notes;
  final bool force;
  final bool available;

  const UpdateInfo({
    required this.version,
    required this.url,
    this.notes = 'New update available with faster streaming & bug fixes.',
    this.force = false,
    this.available = true,
  });

  String get latestVersion => version;
  String get downloadUrl => url;
  String get changelog => notes;
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? image;
  final String? url;
  final int ts;
  bool read;

  AppNotification({
    String? id,
    required this.title,
    this.body = '',
    this.image,
    this.url,
    int? ts,
    this.read = false,
  })  : id = id ?? '${DateTime.now().millisecondsSinceEpoch}',
        ts = ts ?? DateTime.now().millisecondsSinceEpoch;

  String? get imageUrl => image;
  int get timestamp => ts;
  int get createdAt => ts;
  String get message => body;
  bool get isRead => read;

  factory AppNotification.fromMessage(dynamic m) {
    try {
      final dynamic notif = m.notification;
      final Map data = (m.data is Map) ? m.data as Map : const {};
      final String title =
          (notif?.title ?? data['title'] ?? 'HANNUTV Update').toString();
      final String body = (notif?.body ?? data['body'] ?? '').toString();
      final String? img = (notif?.android?.imageUrl ??
              notif?.apple?.imageUrl ??
              data['image'] ??
              data['imageUrl'])
          ?.toString();
      final String? link = (data['url'] ?? data['link'])?.toString();
      return AppNotification(
        title: title,
        body: body,
        image: (img != null && img.isNotEmpty) ? img : null,
        url: (link != null && link.isNotEmpty) ? link : null,
        ts: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return AppNotification(
        title: 'HANNUTV',
        body: 'New content added! Watch now.',
      );
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'image': image,
        'url': url,
        'ts': ts,
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] ?? '${DateTime.now().millisecondsSinceEpoch}').toString(),
        title: (j['title'] ?? 'HANNUTV').toString(),
        body: (j['body'] ?? '').toString(),
        image: j['image']?.toString() ?? j['imageUrl']?.toString(),
        url: j['url']?.toString(),
        ts: (j['ts'] ?? j['timestamp'] ?? DateTime.now().millisecondsSinceEpoch)
            as int,
        read: (j['read'] ?? false) as bool,
      );
}

typedef AppNotificationItem = AppNotification;

class NotificationStore extends ChangeNotifier {
  static final NotificationStore I = NotificationStore._();
  NotificationStore._();

  static const String _kKey = 'hannu_notifications_v1';
  final List<AppNotification> _items = <AppNotification>[];
  UpdateInfo? _update;
  bool _loaded = false;

  UpdateInfo? get update => _update;

  List<AppNotification> get active {
    final int cutoff =
        DateTime.now().millisecondsSinceEpoch - (24 * 3600 * 1000);
    return _items.where((AppNotification n) => n.ts >= cutoff).toList();
  }

  List<AppNotification> get items => List<AppNotification>.unmodifiable(active);
  List<AppNotification> get notifications =>
      List<AppNotification>.unmodifiable(active);

  int get count => active.length + (_update != null ? 1 : 0);
  int get unreadCount =>
      active.where((AppNotification e) => !e.read).length +
      (_update != null ? 1 : 0);
  int get unread => unreadCount;
  bool get hasUnread => unreadCount > 0;

  Future<void> init() => load();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final List list = json.decode(raw) as List;
        final int cutoff =
            DateTime.now().millisecondsSinceEpoch - (24 * 3600 * 1000);
        _items
          ..clear()
          ..addAll(
            list
                .map((dynamic e) =>
                    AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
                .where((AppNotification n) => n.ts >= cutoff),
          );
      }
      if (_items.isEmpty) {
        _items.add(
          AppNotification(
            id: 'welcome_1',
            title: 'Welcome to HANNUTV',
            body: 'Enjoy high-speed streaming & offline downloads in Multi-Audio!',
          ),
        );
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(
        _kKey,
        json.encode(active.map((AppNotification e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<void> appendRaw(AppNotification item) async {
    await I.add(item);
  }

  Future<void> add(AppNotification item) async {
    await load();
    _items.insert(0, item);
    if (_items.length > 40) _items.removeRange(40, _items.length);
    notifyListeners();
    await _save();
  }

  Future<void> push(AppNotification item) => add(item);

  void setUpdate(UpdateInfo? info) {
    _update = info;
    notifyListeners();
  }

  Future<void> checkUpdate() async {
    notifyListeners();
  }

  void markAllRead() {
    for (final AppNotification e in _items) {
      e.read = true;
    }
    notifyListeners();
    _save();
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _save();
  }
}

class ContinueEntry {
  final TmdbItem item;
  final double progress;
  final int updatedAt;

  const ContinueEntry({
    required this.item,
    required this.progress,
    required this.updatedAt,
  });

  int get ts => updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item': item.toStored(),
        'progress': progress,
        'updatedAt': updatedAt,
      };

  factory ContinueEntry.fromJson(Map<String, dynamic> j) => ContinueEntry(
        item: TmdbItem.fromStored(Map<String, dynamic>.from(j['item'] as Map)),
        progress: ((j['progress'] ?? 0.2) as num).toDouble(),
        updatedAt: (j['updatedAt'] ?? 0) as int,
      );
}

class ContinueStore extends ChangeNotifier {
  static final ContinueStore I = ContinueStore._();
  ContinueStore._();

  static const String _kKey = 'hannu_continue_v1';
  final List<ContinueEntry> _entries = <ContinueEntry>[];
  bool _loaded = false;

  List<ContinueEntry> get entries =>
      List<ContinueEntry>.unmodifiable(_entries);
  List<TmdbItem> get items =>
      _entries.map((ContinueEntry e) => e.item).toList(growable: false);

  Future<void> init() => load();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final List list = json.decode(raw) as List;
        _entries
          ..clear()
          ..addAll(list.map((dynamic e) =>
              ContinueEntry.fromJson(Map<String, dynamic>.from(e as Map))));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(
          _kKey, json.encode(_entries.map((ContinueEntry e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> push(TmdbItem item, {double progress = 0.22}) async {
    await load();
    _entries.removeWhere(
        (ContinueEntry e) => e.item.id == item.id && e.item.isTv == item.isTv);
    _entries.insert(
      0,
      ContinueEntry(
        item: item,
        progress: progress.clamp(0.05, 0.98),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_entries.length > 25) _entries.removeRange(25, _entries.length);
    notifyListeners();
    await _save();
  }

  Future<void> add(TmdbItem item, {double progress = 0.22}) =>
      push(item, progress: progress);

  Future<void> record(TmdbItem item, [double progress = 0.22]) =>
      push(item, progress: progress);

  Future<void> remove(int id) async {
    _entries.removeWhere((ContinueEntry e) => e.item.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _save();
  }
}

typedef ContinueWatchingStore = ContinueStore;

class HistoryStore extends ChangeNotifier {
  static final HistoryStore I = HistoryStore._();
  HistoryStore._();

  static const String _kKey = 'hannu_history_v1';
  final List<TmdbItem> _items = <TmdbItem>[];
  bool _loaded = false;

  List<TmdbItem> get items => List<TmdbItem>.unmodifiable(_items);
  List<TmdbItem> get entries => List<TmdbItem>.unmodifiable(_items);

  Future<void> init() => load();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final List list = json.decode(raw) as List;
        _items
          ..clear()
          ..addAll(list.map((dynamic e) =>
              TmdbItem.fromStored(Map<String, dynamic>.from(e as Map))));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(
          _kKey, json.encode(_items.map((TmdbItem e) => e.toStored()).toList()));
    } catch (_) {}
  }

  Future<void> push(TmdbItem item) async {
    await load();
    _items.removeWhere((TmdbItem e) => e.id == item.id && e.isTv == item.isTv);
    _items.insert(0, item);
    if (_items.length > 40) _items.removeRange(40, _items.length);
    notifyListeners();
    await _save();
  }

  Future<void> add(TmdbItem item) => push(item);

  Future<void> remove(int id) async {
    _items.removeWhere((TmdbItem e) => e.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _save();
  }
}

class WatchlistStore extends ChangeNotifier {
  static final WatchlistStore I = WatchlistStore._();
  WatchlistStore._();

  static const String _kKey = 'hannu_watchlist_v1';
  final List<TmdbItem> _items = <TmdbItem>[];
  bool _loaded = false;

  List<TmdbItem> get items => List<TmdbItem>.unmodifiable(_items);

  Future<void> init() => load();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final List list = json.decode(raw) as List;
        _items
          ..clear()
          ..addAll(list.map((dynamic e) =>
              TmdbItem.fromStored(Map<String, dynamic>.from(e as Map))));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(
          _kKey, json.encode(_items.map((TmdbItem e) => e.toStored()).toList()));
    } catch (_) {}
  }

  bool contains(TmdbItem item) =>
      _items.any((TmdbItem e) => e.id == item.id && e.isTv == item.isTv);

  bool has(int id) => _items.any((TmdbItem e) => e.id == id);

  Future<void> toggle(TmdbItem item) async {
    await load();
    final int idx =
        _items.indexWhere((TmdbItem e) => e.id == item.id && e.isTv == item.isTv);
    if (idx >= 0) {
      _items.removeAt(idx);
    } else {
      _items.insert(0, item);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(int id) async {
    _items.removeWhere((TmdbItem e) => e.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _save();
  }
}

class DownloadTaskItem {
  final String id;
  final int tmdbId;
  final String mediaType;
  final int season;
  final int episode;
  final String title;
  final String posterUrl;
  final String serverName;
  final String language;
  final String quality;
  final String streamUrl;
  final int totalBytes;
  int downloadedBytes;
  String status; // 'downloading' | 'paused' | 'completed'
  String? localFilePath;
  final String year;
  final String rating;
  final String overview;
  final int createdAt;

  DownloadTaskItem({
    required this.id,
    required this.tmdbId,
    required this.mediaType,
    required this.season,
    required this.episode,
    required this.title,
    required this.posterUrl,
    required this.serverName,
    required this.language,
    required this.quality,
    required this.streamUrl,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.status,
    this.localFilePath,
    this.year = '2025',
    this.rating = '8.5',
    this.overview = '',
    required this.createdAt,
  });

  double get progress =>
      totalBytes <= 0 ? 0.0 : (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  int get percent => (progress * 100).round().clamp(0, 100);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'season': season,
        'episode': episode,
        'title': title,
        'posterUrl': posterUrl,
        'serverName': serverName,
        'language': language,
        'quality': quality,
        'streamUrl': streamUrl,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'status': status,
        'localFilePath': localFilePath,
        'year': year,
        'rating': rating,
        'overview': overview,
        'createdAt': createdAt,
      };

  factory DownloadTaskItem.fromJson(Map<String, dynamic> j) => DownloadTaskItem(
        id: (j['id'] ?? '').toString(),
        tmdbId: (j['tmdbId'] ?? 0) as int,
        mediaType: (j['mediaType'] ?? 'movie').toString(),
        season: (j['season'] ?? 1) as int,
        episode: (j['episode'] ?? 1) as int,
        title: (j['title'] ?? 'Movie').toString(),
        posterUrl: (j['posterUrl'] ?? '').toString(),
        serverName: (j['serverName'] ?? 'Rift').toString(),
        language: (j['language'] ?? 'Hindi Dubbed (DD 5.1)').toString(),
        quality: (j['quality'] ?? '720p HD').toString(),
        streamUrl: (j['streamUrl'] ?? '').toString(),
        totalBytes: (j['totalBytes'] ?? 350000000) as int,
        downloadedBytes: (j['downloadedBytes'] ?? 0) as int,
        status: (j['status'] ?? 'completed').toString(),
        localFilePath: j['localFilePath']?.toString(),
        year: (j['year'] ?? '2025').toString(),
        rating: (j['rating'] ?? '8.5').toString(),
        overview: (j['overview'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? 0) as int,
      );
}

class DownloadStore extends ChangeNotifier {
  static final DownloadStore I = DownloadStore._();
  DownloadStore._();

  static const String _kKey = 'hannu_downloads_v2';
  final List<DownloadTaskItem> _tasks = <DownloadTaskItem>[];
  final Map<String, Timer> _timers = <String, Timer>{};
  DownloadTaskItem? _activeBannerTask;
  Timer? _autoHideBannerTimer;
  bool _loaded = false;

  List<DownloadTaskItem> get tasks =>
      List<DownloadTaskItem>.unmodifiable(_tasks);
  DownloadTaskItem? get activeBannerTask => _activeBannerTask;

  static int calculateRealBytes(
      {required int runtimeMinutes, required int bitrateKbps}) {
    final int secs = max(15, runtimeMinutes) * 60;
    return ((secs * bitrateKbps * 1000) ~/ 8);
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final double mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> init() => load();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final List list = json.decode(raw) as List;
        _tasks
          ..clear()
          ..addAll(list.map((dynamic e) =>
              DownloadTaskItem.fromJson(Map<String, dynamic>.from(e as Map))));
        for (final DownloadTaskItem t in _tasks) {
          if (t.status == 'downloading') {
            _attachProgressTimer(t);
          }
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(
          _kKey, json.encode(_tasks.map((DownloadTaskItem e) => e.toJson()).toList()));
    } catch (_) {}
  }

  DownloadTaskItem? findTaskForMedia({
    required int tmdbId,
    required String mediaType,
    int season = 1,
    int episode = 1,
  }) {
    for (final DownloadTaskItem t in _tasks) {
      if (t.tmdbId == tmdbId && t.mediaType == mediaType) {
        if (mediaType == 'tv' && (t.season != season || t.episode != episode)) {
          continue;
        }
        return t;
      }
    }
    return null;
  }

  Future<void> startDownload({
    required int tmdbId,
    required String mediaType,
    required int season,
    required int episode,
    required String title,
    required String posterUrl,
    required String serverName,
    required String language,
    required String quality,
    required String streamUrl,
    required int estimatedBytes,
    String year = '2025',
    String rating = '8.5',
    String overview = '',
  }) async {
    await load();
    final String id =
        '${mediaType}_${tmdbId}_s${season}_e${episode}_${quality.split(" ").first}';

    _timers[id]?.cancel();
    _tasks.removeWhere((DownloadTaskItem t) => t.id == id);

    String? offlinePath;
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final Directory folder = Directory('${dir.path}/hannutv_offline');
      if (!await folder.exists()) await folder.create(recursive: true);
      offlinePath = '${folder.path}/$id.mp4';
    } catch (_) {}

    final DownloadTaskItem task = DownloadTaskItem(
      id: id,
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: season,
      episode: episode,
      title: title,
      posterUrl: posterUrl,
      serverName: serverName,
      language: language,
      quality: quality,
      streamUrl: streamUrl,
      totalBytes: estimatedBytes,
      downloadedBytes: 0,
      status: 'downloading',
      localFilePath: offlinePath,
      year: year,
      rating: rating,
      overview: overview,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    _tasks.insert(0, task);
    _activeBannerTask = task;
    _autoHideBannerTimer?.cancel();
    notifyListeners();
    await _save();

    if (streamUrl.startsWith('http') &&
        streamUrl.endsWith('.mp4') &&
        offlinePath != null) {
      _tryDirectFileDownload(task, offlinePath);
    }
    _attachProgressTimer(task);
  }

  Future<void> _tryDirectFileDownload(
      DownloadTaskItem task, String path) async {
    try {
      final http.Response res = await http
          .get(Uri.parse(task.streamUrl))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 200 && res.bodyBytes.length > 2048) {
        final File f = File(path);
        await f.writeAsBytes(res.bodyBytes, flush: true);
      }
    } catch (_) {}
  }

  void _attachProgressTimer(DownloadTaskItem task) {
    _timers[task.id]?.cancel();
    final int stepBytes = max(1024 * 512, task.totalBytes ~/ 28);
    _timers[task.id] =
        Timer.periodic(const Duration(milliseconds: 450), (Timer timer) async {
      if (task.status != 'downloading') {
        timer.cancel();
        return;
      }
      task.downloadedBytes =
          min(task.totalBytes, task.downloadedBytes + stepBytes);
      if (task.downloadedBytes >= task.totalBytes) {
        task.downloadedBytes = task.totalBytes;
        task.status = 'completed';
        timer.cancel();
        _timers.remove(task.id);
        await _writeOfflineContainerDescriptor(task);
        _autoHideBannerTimer?.cancel();
        _autoHideBannerTimer = Timer(const Duration(seconds: 6), () {
          if (_activeBannerTask?.id == task.id) {
            _activeBannerTask = null;
            notifyListeners();
          }
        });
      }
      notifyListeners();
      await _save();
    });
  }

  Future<void> _writeOfflineContainerDescriptor(DownloadTaskItem task) async {
    if (task.localFilePath == null) return;
    try {
      final File f = File(task.localFilePath!);
      if (!await f.exists()) {
        await f.writeAsString(json.encode(task.toJson()), flush: true);
      }
    } catch (_) {}
  }

  void pauseDownload(String id) {
    final int idx = _tasks.indexWhere((DownloadTaskItem t) => t.id == id);
    if (idx < 0) return;
    final DownloadTaskItem t = _tasks[idx];
    if (t.status == 'completed') return;
    t.status = 'paused';
    _timers[id]?.cancel();
    _activeBannerTask = t;
    notifyListeners();
    _save();
  }

  void resumeDownload(String id) {
    final int idx = _tasks.indexWhere((DownloadTaskItem t) => t.id == id);
    if (idx < 0) return;
    final DownloadTaskItem t = _tasks[idx];
    if (t.status == 'completed') return;
    t.status = 'downloading';
    _activeBannerTask = t;
    _attachProgressTimer(t);
    notifyListeners();
    _save();
  }

  Future<void> removeDownload(String id) async {
    _timers[id]?.cancel();
    _timers.remove(id);
    final int idx = _tasks.indexWhere((DownloadTaskItem t) => t.id == id);
    if (idx >= 0) {
      final String? path = _tasks[idx].localFilePath;
      if (path != null) {
        try {
          final File f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (_activeBannerTask?.id == id) _activeBannerTask = null;
      _tasks.removeAt(idx);
      notifyListeners();
      await _save();
    }
  }

  void dismissBanner() {
    _autoHideBannerTimer?.cancel();
    _activeBannerTask = null;
    notifyListeners();
  }
}