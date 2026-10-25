import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_sheet.dart'; // 🔥 Import added for SniffHit dependencies

String dlBytes(num b) {
  if (b <= 0) return '0 MB';
  const List<String> u = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double v = b.toDouble();
  int i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final int dec = i >= 3 ? 2 : 0;
  return '${v.toStringAsFixed(dec)} ${u[i]}';
}

String dlDuration(double sec) {
  final int s = sec.round();
  if (s <= 0) return '';
  final int h = s ~/ 3600;
  final int m = (s % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

String dlEta(double sec) {
  if (sec.isNaN || sec.isInfinite || sec <= 0) return '';
  final int s = sec.round();
  if (s >= 3600) return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m left';
  if (s >= 60) return '${s ~/ 60}m ${s % 60}s left';
  return '${s}s left';
}

const Map<String, String> _l3 = <String, String>{
  'hi': 'hin', 'en': 'eng', 'ta': 'tam', 'te': 'tel', 'ml': 'mal', 'kn': 'kan',
  'bn': 'ben', 'mr': 'mar', 'pa': 'pan', 'gu': 'guj', 'ur': 'urd', 'es': 'spa',
  'fr': 'fra', 'de': 'deu', 'it': 'ita', 'pt': 'por', 'ru': 'rus', 'ja': 'jpn',
  'ko': 'kor', 'zh': 'zho', 'ar': 'ara', 'tr': 'tur', 'th': 'tha', 'id': 'ind',
  'pl': 'pol', 'nl': 'nld', 'vi': 'vie', 'fa': 'fas', 'he': 'heb',
};

String dlLang3(String code) {
  String c = code.trim().toLowerCase();
  if (c.isEmpty) return 'und';
  final int cut = c.indexOf(RegExp(r'[-_]'));
  if (cut > 0) c = c.substring(0, cut);
  if (c.length == 3) return c;
  return _l3[c] ?? 'und';
}

String _safeName(String s, {int max = 48}) {
  String o = s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  o = o.replaceAll(RegExp(r'^_+|_+$'), '');
  if (o.isEmpty) o = 'video';
  if (o.length > max) o = o.substring(0, max);
  return o;
}

String _metaSafe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '').trim();

String _q(String s) {
  if (s.isEmpty || s.contains(' ') || s.contains('"') || s.contains("'")) {
    return '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
  return s;
}

class HlsVariant {
  const HlsVariant({
    required this.url,
    this.bandwidth = 0,
    this.avg = 0,
    this.width = 0,
    this.height = 0,
    this.codecs = '',
    this.audioGroup = '',
  });
  final String url;
  final int bandwidth;
  final int avg;
  final int width;
  final int height;
  final String codecs;
  final String audioGroup;

  bool get isHevc {
    final String c = codecs.toLowerCase();
    return c.contains('hvc1') || c.contains('hev1') || c.contains('dvh1') || c.contains('av01');
  }

  int get bps => avg > 0 ? avg : bandwidth;

  String get label {
    if (height >= 2160) return '4K';
    if (height > 0) return '${height}p';
    if (bandwidth > 0) return '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps';
    return 'Original';
  }
}

class HlsAudio {
  const HlsAudio({
    required this.groupId,
    required this.name,
    required this.lang,
    required this.url,
    this.isDefault = false,
    this.channels = '',
  });
  final String groupId;
  final String name;
  final String lang;
  final String url; 
  final bool isDefault;
  final String channels;

  String get display {
    final String n = name.trim();
    if (n.isNotEmpty) return n;
    final String l = lang.trim();
    return l.isEmpty ? 'Audio' : l.toUpperCase();
  }
}

class HlsMaster {
  HlsMaster(this.variants, this.audios);
  final List<HlsVariant> variants;
  final List<HlsAudio> audios;
}

class HlsKey {
  const HlsKey(this.uri, this.iv);
  final String uri;
  final String iv;
}

class HlsSeg {
  HlsSeg(this.url, this.dur, this.keyIdx, this.rangeStart, this.rangeLen, this.disc);
  final String url;
  final double dur;
  final int keyIdx;
  final int rangeStart;
  final int rangeLen;
  final bool disc;
  String name = '';
}

class HlsMedia {
  HlsMedia();
  final List<HlsSeg> segs = <HlsSeg>[];
  final List<HlsKey> keys = <HlsKey>[];
  String mapUrl = '';
  String mapName = '';
  int mapStart = -1;
  int mapLen = -1;
  int mediaSeq = 0;
  double targetDur = 0;
  bool endList = false;
  bool unsupported = false;

  double get totalDur {
    double d = 0;
    for (final HlsSeg s in segs) {
      d += s.dur;
    }
    return d;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'seq': mediaSeq,
        'td': targetDur,
        'end': endList,
        'mu': mapUrl,
        'mn': mapName,
        'ms': mapStart,
        'ml': mapLen,
        'keys': keys.map((HlsKey k) => <String>[k.uri, k.iv]).toList(),
        'segs': segs
            .map((HlsSeg s) =>
                <dynamic>[s.url, s.dur, s.keyIdx, s.rangeStart, s.rangeLen, s.disc ? 1 : 0, s.name])
            .toList(),
      };

  static HlsMedia fromJson(Map<String, dynamic> j) {
    final HlsMedia m = HlsMedia();
    m.mediaSeq = (j['seq'] as num?)?.toInt() ?? 0;
    m.targetDur = (j['td'] as num?)?.toDouble() ?? 0;
    m.endList = j['end'] == true;
    m.mapUrl = (j['mu'] ?? '').toString();
    m.mapName = (j['mn'] ?? '').toString();
    m.mapStart = (j['ms'] as num?)?.toInt() ?? -1;
    m.mapLen = (j['ml'] as num?)?.toInt() ?? -1;
    for (final dynamic k in (j['keys'] as List<dynamic>? ?? <dynamic>[])) {
      final List<dynamic> a = k as List<dynamic>;
      m.keys.add(HlsKey(a[0].toString(), a[1].toString()));
    }
    for (final dynamic s in (j['segs'] as List<dynamic>? ?? <dynamic>[])) {
      final List<dynamic> a = s as List<dynamic>;
      final HlsSeg seg = HlsSeg(
        a[0].toString(),
        (a[1] as num).toDouble(),
        (a[2] as num).toInt(),
        (a[3] as num).toInt(),
        (a[4] as num).toInt(),
        (a[5] as num).toInt() == 1,
      );
      seg.name = a[6].toString();
      m.segs.add(seg);
    }
    return m;
  }
}

class HlsParser {
  static bool isPlaylist(String t) => t.trimLeft().startsWith('#EXTM3U');
  static bool isMaster(String t) => t.contains('#EXT-X-STREAM-INF');

  static String _after(String l) => l.substring(l.indexOf(':') + 1);

  static Map<String, String> attrs(String s) {
    final Map<String, String> m = <String, String>{};
    final RegExp re = RegExp(r'([A-Za-z0-9_-]+)=("[^"]*"|[^,]*)');
    for (final RegExpMatch x in re.allMatches(s)) {
      String v = x.group(2) ?? '';
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      m[(x.group(1) ?? '').toUpperCase()] = v;
    }
    return m;
  }

  static HlsMaster parseMaster(String text, Uri base) {
    final List<String> lines = const LineSplitter().convert(text);
    final List<HlsVariant> variants = <HlsVariant>[];
    final List<HlsAudio> audios = <HlsAudio>[];
    for (int i = 0; i < lines.length; i++) {
      final String l = lines[i].trim();
      if (l.startsWith('#EXT-X-STREAM-INF:')) {
        final Map<String, String> a = attrs(_after(l));
        String? uri;
        for (int j = i + 1; j < lines.length; j++) {
          final String n = lines[j].trim();
          if (n.isEmpty) continue;
          if (n.startsWith('#')) {
            if (n.startsWith('#EXT-X-STREAM-INF')) break;
            continue;
          }
          uri = n;
          break;
        }
        if (uri == null) continue;
        final List<String> res = (a['RESOLUTION'] ?? '').toLowerCase().split('x');
        variants.add(HlsVariant(
          url: base.resolve(uri).toString(),
          bandwidth: int.tryParse(a['BANDWIDTH'] ?? '') ?? 0,
          avg: int.tryParse(a['AVERAGE-BANDWIDTH'] ?? '') ?? 0,
          width: res.length == 2 ? (int.tryParse(res[0]) ?? 0) : 0,
          height: res.length == 2 ? (int.tryParse(res[1]) ?? 0) : 0,
          codecs: a['CODECS'] ?? '',
          audioGroup: a['AUDIO'] ?? '',
        ));
      } else if (l.startsWith('#EXT-X-MEDIA:')) {
        final Map<String, String> a = attrs(_after(l));
        if ((a['TYPE'] ?? '').toUpperCase() != 'AUDIO') continue;
        final String uri = a['URI'] ?? '';
        audios.add(HlsAudio(
          groupId: a['GROUP-ID'] ?? '',
          name: a['NAME'] ?? '',
          lang: a['LANGUAGE'] ?? '',
          url: uri.isEmpty ? '' : base.resolve(uri).toString(),
          isDefault: (a['DEFAULT'] ?? '').toUpperCase() == 'YES',
          channels: a['CHANNELS'] ?? '',
        ));
      }
    }
    return HlsMaster(variants, audios);
  }

  static HlsMedia parseMedia(String text, Uri base) {
    final List<String> lines = const LineSplitter().convert(text);
    final HlsMedia m = HlsMedia();
    double dur = 0;
    int keyIdx = -1;
    bool disc = false;
    int pendLen = -1;
    int pendStart = -1;
    final Map<String, int> lastEnd = <String, int>{};

    for (final String raw in lines) {
      final String l = raw.trim();
      if (l.isEmpty) continue;
      if (l.startsWith('#')) {
        if (l.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
          m.mediaSeq = int.tryParse(_after(l).trim()) ?? 0;
        } else if (l.startsWith('#EXT-X-TARGETDURATION:')) {
          m.targetDur = double.tryParse(_after(l).trim()) ?? 0;
        } else if (l.startsWith('#EXT-X-KEY:')) {
          final Map<String, String> a = attrs(_after(l));
          final String method = (a['METHOD'] ?? 'NONE').toUpperCase();
          if (method == 'NONE') {
            keyIdx = -1;
          } else if (method == 'AES-128') {
            final String uri = a['URI'] ?? '';
            if (uri.isEmpty) {
              m.unsupported = true;
            } else {
              m.keys.add(HlsKey(base.resolve(uri).toString(), a['IV'] ?? ''));
              keyIdx = m.keys.length - 1;
            }
          } else {
            m.unsupported = true; 
          }
        } else if (l.startsWith('#EXT-X-MAP:')) {
          final Map<String, String> a = attrs(_after(l));
          final String uri = a['URI'] ?? '';
          if (uri.isNotEmpty && m.mapUrl.isEmpty) {
            m.mapUrl = base.resolve(uri).toString();
            final String br = a['BYTERANGE'] ?? '';
            if (br.isNotEmpty) {
              final List<String> p = br.split('@');
              m.mapLen = int.tryParse(p[0]) ?? -1;
              m.mapStart = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
            }
          }
        } else if (l.startsWith('#EXTINF:')) {
          final String v = _after(l);
          final int c = v.indexOf(',');
          dur = double.tryParse((c >= 0 ? v.substring(0, c) : v).trim()) ?? 0;
        } else if (l.startsWith('#EXT-X-BYTERANGE:')) {
          final List<String> p = _after(l).trim().split('@');
          pendLen = int.tryParse(p[0]) ?? -1;
          pendStart = p.length > 1 ? (int.tryParse(p[1]) ?? -1) : -1;
        } else if (l.startsWith('#EXT-X-DISCONTINUITY')) {
          disc = true;
        } else if (l.startsWith('#EXT-X-ENDLIST')) {
          m.endList = true;
        }
        continue;
      }
      final String url = base.resolve(l).toString();
      int rs = -1;
      int rl = -1;
      if (pendLen > 0) {
        rl = pendLen;
        rs = pendStart >= 0 ? pendStart : (lastEnd[url] ?? 0);
        lastEnd[url] = rs + rl;
      }
      m.segs.add(HlsSeg(url, dur, keyIdx, rs, rl, disc));
      disc = false;
      dur = 0;
      pendLen = -1;
      pendStart = -1;
    }
    return m;
  }
}

enum DlState { queued, downloading, merging, done, failed, paused }

class DlAudioSel {
  const DlAudioSel(this.name, this.lang, this.url);
  final String name;
  final String lang;
  final String url;
  Map<String, dynamic> toJson() => <String, dynamic>{'n': name, 'l': lang, 'u': url};
  factory DlAudioSel.fromJson(Map<String, dynamic> j) =>
      DlAudioSel((j['n'] ?? '').toString(), (j['l'] ?? '').toString(), (j['u'] ?? '').toString());
}

class DlJob {
  DlJob({
    required this.id,
    required this.tmdbId,
    required this.isTv,
    required this.title,
    required this.year,
    required this.posterPath,
    required this.season,
    required this.episode,
    required this.qualityLabel,
    required this.langLabel,
    required this.videoUrl,
    required this.audios,
    required this.headers,
    required this.durationSec,
    required this.estBytes,
    required this.exportToGallery,
    required this.kind,
    required this.hevc,
    required this.audioNeedsAac,
    required this.createdAt,
    this.state = DlState.queued,
    this.progress = 0,
    this.bytesDone = 0,
    this.segDone = 0,
    this.segTotal = 0,
    this.speedBps = 0,
    this.stage = '',
    this.error = '',
    this.filePath = '',
    this.fileBytes = 0,
    this.positionMs = 0,
    this.galleryDone = false,
  });

  final String id;
  final int tmdbId;
  final bool isTv;
  final String title;
  final String year;
  final String posterPath;
  final int season;
  final int episode;
  final String qualityLabel;
  final String langLabel;
  final String videoUrl;
  final List<DlAudioSel> audios;
  final Map<String, String> headers;
  final double durationSec;
  final int estBytes;
  final bool exportToGallery;
  final String kind; 
  final bool hevc;
  final bool audioNeedsAac;
  final int createdAt;

  DlState state;
  double progress;
  int bytesDone;
  int segDone;
  int segTotal;
  double speedBps;
  String stage;
  String error;
  String filePath;
  int fileBytes;
  int positionMs;
  bool galleryDone;

  bool get isActive =>
      state == DlState.queued || state == DlState.downloading || state == DlState.merging;

  String get epLabel => isTv ? 'S$season · E$episode' : '';

  String get dupKey => '${isTv ? 'tv' : 'm'}_${tmdbId}_${season}_${episode}_${qualityLabel}_$langLabel';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'tmdb': tmdbId,
        'tv': isTv,
        'title': title,
        'year': year,
        'poster': posterPath,
        's': season,
        'e': episode,
        'q': qualityLabel,
        'lang': langLabel,
        'vu': videoUrl,
        'aud': audios.map((DlAudioSel a) => a.toJson()).toList(),
        'hd': headers,
        'dur': durationSec,
        'est': estBytes,
        'gal': exportToGallery,
        'kind': kind,
        'hevc': hevc,
        'aac': audioNeedsAac,
        'ts': createdAt,
        'st': state.name,
        'pr': progress,
        'bd': bytesDone,
        'sd': segDone,
        'stt': segTotal,
        'err': error,
        'fp': filePath,
        'fb': fileBytes,
        'pos': positionMs,
        'gd': galleryDone,
      };

  factory DlJob.fromJson(Map<String, dynamic> j) {
    final Map<String, String> hd = <String, String>{};
    final dynamic rawH = j['hd'];
    if (rawH is Map) {
      rawH.forEach((dynamic k, dynamic v) => hd[k.toString()] = v.toString());
    }
    DlState st = DlState.failed;
    final String sn = (j['st'] ?? '').toString();
    for (final DlState s in DlState.values) {
      if (s.name == sn) st = s;
    }
    return DlJob(
      id: (j['id'] ?? '').toString(),
      tmdbId: (j['tmdb'] as num?)?.toInt() ?? 0,
      isTv: j['tv'] == true,
      title: (j['title'] ?? '').toString(),
      year: (j['year'] ?? '').toString(),
      posterPath: (j['poster'] ?? '').toString(),
      season: (j['s'] as num?)?.toInt() ?? 1,
      episode: (j['e'] as num?)?.toInt() ?? 1,
      qualityLabel: (j['q'] ?? '').toString(),
      langLabel: (j['lang'] ?? '').toString(),
      videoUrl: (j['vu'] ?? '').toString(),
      audios: ((j['aud'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic a) => DlAudioSel.fromJson(Map<String, dynamic>.from(a as Map<dynamic, dynamic>)))
          .toList(),
      headers: hd,
      durationSec: (j['dur'] as num?)?.toDouble() ?? 0,
      estBytes: (j['est'] as num?)?.toInt() ?? 0,
      exportToGallery: j['gal'] == true,
      kind: (j['kind'] ?? 'hls').toString(),
      hevc: j['hevc'] == true,
      audioNeedsAac: j['aac'] == true,
      createdAt: (j['ts'] as num?)?.toInt() ?? 0,
      state: st,
      progress: (j['pr'] as num?)?.toDouble() ?? 0,
      bytesDone: (j['bd'] as num?)?.toInt() ?? 0,
      segDone: (j['sd'] as num?)?.toInt() ?? 0,
      segTotal: (j['stt'] as num?)?.toInt() ?? 0,
      error: (j['err'] ?? '').toString(),
      filePath: (j['fp'] ?? '').toString(),
      fileBytes: (j['fb'] as num?)?.toInt() ?? 0,
      positionMs: (j['pos'] as num?)?.toInt() ?? 0,
      galleryDone: j['gd'] == true,
    );
  }
}

class DownloadStore extends ChangeNotifier {
  DownloadStore._();
  static final DownloadStore I = DownloadStore._();
  static const String _k = 'hannu_downloads_v1';

  final List<DlJob> _jobs = <DlJob>[];
  final Map<String, _Runner> _runners = <String, _Runner>{};
  bool _loaded = false;
  Directory? _base;
  int _lastNotify = 0;
  Timer? _saveTimer;

  List<DlJob> get jobs => List<DlJob>.unmodifiable(_jobs);
  int get activeCount => _jobs.where((DlJob j) => j.isActive).length;
  int get doneCount => _jobs.where((DlJob j) => j.state == DlState.done).length;

  DlJob? find(String id) {
    for (final DlJob j in _jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  DlJob? duplicateOf(String dupKey) {
    for (final DlJob j in _jobs) {
      if (j.dupKey == dupKey && j.state != DlState.failed) return j;
    }
    return null;
  }

  Future<Directory> baseDir() async {
    if (_base != null) return _base!;
    Directory? d;
    try {
      d = await getExternalStorageDirectory();
    } catch (_) {}
    d ??= await getApplicationDocumentsDirectory();
    final Directory b = Directory('${d.path}/HANNUTV_downloads');
    if (!b.existsSync()) b.createSync(recursive: true);
    _base = b;
    return b;
  }

  Future<Directory> _jobDir(String id) async {
    final Directory b = await baseDir();
    final Directory d = Directory('${b.path}/work/$id');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<Directory> _movieDir() async {
    final Directory b = await baseDir();
    final Directory d = Directory('${b.path}/movies');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<bool> ensureStorageAccess() async {
    try {
      if (await Gal.hasAccess(toAlbum: true)) return true;
      return await Gal.requestAccess(toAlbum: true);
    } catch (_) {
      return false;
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String? raw = p.getString(_k);
      if (raw != null) {
        final List<dynamic> list = json.decode(raw) as List<dynamic>;
        for (final dynamic m in list) {
          if (m is Map) {
            try {
              _jobs.add(DlJob.fromJson(Map<String, dynamic>.from(m)));
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('downloads load error: $e');
    }
    for (final DlJob j in _jobs) {
      if (j.state == DlState.downloading || j.state == DlState.merging) {
        j.state = DlState.queued;
        j.speedBps = 0;
      }
      if (j.state == DlState.done && (j.filePath.isEmpty || !File(j.filePath).existsSync())) {
        j.state = DlState.failed;
        j.error = 'File phone se delete ho chuki hai.';
      }
    }
    notifyListeners();
    _pump();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(_k, json.encode(_jobs.map((DlJob j) => j.toJson()).toList()));
    } catch (e) {
      debugPrint('downloads save error: $e');
    }
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), _save);
  }

  void _tick({bool force = false}) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastNotify < 250) return;
    _lastNotify = now;
    notifyListeners();
    _saveSoon();
  }

  Future<void> enqueue(DlJob job) async {
    _jobs.insert(0, job);
    notifyListeners();
    await _save();
    _pump();
  }

  void _pump() {
    if (_runners.isNotEmpty) return;
    DlJob? next;
    for (final DlJob j in _jobs.reversed) {
      if (j.state == DlState.queued) {
        next = j;
        break;
      }
    }
    if (next == null) return;
    final DlJob job = next;
    final _Runner r = _Runner(job, this);
    _runners[job.id] = r;
    r.run().whenComplete(() {
      _runners.remove(job.id);
      _tick(force: true);
      _save();
      _pump();
    });
  }

  void pause(String id) {
    final DlJob? j = find(id);
    if (j == null) return;
    final _Runner? r = _runners[id];
    if (r != null) r.stop();
    if (j.state == DlState.queued || j.state == DlState.downloading) {
      j.state = DlState.paused;
      j.speedBps = 0;
      j.stage = '';
    }
    _tick(force: true);
  }

  void resume(String id) {
    final DlJob? j = find(id);
    if (j == null) return;
    if (j.state == DlState.paused || j.state == DlState.failed) {
      j.state = DlState.queued;
      j.error = '';
      j.stage = '';
      _tick(force: true);
      _pump();
    }
  }

  Future<void> remove(String id, {bool deleteFile = true}) async {
    final DlJob? j = find(id);
    if (j == null) return;
    final _Runner? r = _runners[id];
    if (r != null) {
      r.stop();
      try {
        await r.done.timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    _jobs.removeWhere((DlJob e) => e.id == id);
    notifyListeners();
    try {
      final Directory b = await baseDir();
      final Directory w = Directory('${b.path}/work/$id');
      if (w.existsSync()) await w.delete(recursive: true);
      if (deleteFile && j.filePath.isNotEmpty) {
        final File f = File(j.filePath);
        if (f.existsSync()) await f.delete();
      }
    } catch (e) {
      debugPrint('downloads remove error: $e');
    }
    await _save();
  }

  Future<void> savePosition(String id, int ms) async {
    final DlJob? j = find(id);
    if (j == null) return;
    j.positionMs = ms;
    _saveSoon();
  }
}

class _StopSignal implements Exception {}

class _DlFail implements Exception {
  _DlFail(this.msg);
  final String msg;
  @override
  String toString() => msg;
}

class _HttpStatus implements Exception {
  _HttpStatus(this.code);
  final int code;
}

class _TrackState {
  _TrackState(this.id, this.playlistUrl, this.dir);
  final String id;
  final String playlistUrl;
  final String dir;
  HlsMedia media = HlsMedia();
}

class _Task {
  _Task(this.url, this.path, this.rs, this.rl, this.ts);
  final String url;
  final String path;
  final int rs;
  final int rl;
  final bool ts;
}

class _Runner {
  _Runner(this.job, this.store);
  final DlJob job;
  final DownloadStore store;

  bool _stop = false;
  HttpClient? _client;
  final Completer<void> _doneC = Completer<void>();
  Future<void> get done => _doneC.future;

  int _bytes = 0;
  int _baseBytes = 0;
  int _lastBytes = 0;
  int _lastSpeedAt = 0;
  static const int _conc = 6;

  void stop() {
    _stop = true;
    try {
      _client?.close(force: true);
    } catch (_) {}
    try {
      FFmpegKit.cancel();
    } catch (_) {}
  }

  void _check() {
    if (_stop) throw _StopSignal();
  }

  HttpClient _http() {
    final HttpClient c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 20);
    c.idleTimeout = const Duration(seconds: 15);
    c.autoUncompress = true;
    final String ua = job.headers['User-Agent'] ?? '';
    if (ua.isNotEmpty) c.userAgent = ua;
    _client = c;
    return c;
  }

  Future<HttpClientResponse> _open(String url, {int rs = -1, int rl = -1, int from = -1}) async {
    final HttpClient c = _client ?? _http();
    final HttpClientRequest req =
        await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 25));
    job.headers.forEach((String k, String v) {
      if (v.isNotEmpty) req.headers.set(k, v);
    });
    if (rs >= 0 && rl > 0) {
      req.headers.set('Range', 'bytes=$rs-${rs + rl - 1}');
    } else if (from > 0) {
      req.headers.set('Range', 'bytes=$from-');
    }
    req.followRedirects = true;
    req.maxRedirects = 6;
    return req.close().timeout(const Duration(seconds: 30));
  }

  String _netMsg(Object? e) {
    if (e is _DlFail) return e.msg;
    if (e is SocketException) return 'Internet / server se connection toot gaya. Network check karke Resume dabao.';
    if (e is TimeoutException) return 'Server bahut slow hai (timeout). Resume dabao.';
    if (e is HandshakeException) return 'Secure connection fail hua. Resume dabao.';
    if (e is _HttpStatus) {
      if (e.code == 403 || e.code == 401 || e.code == 410) {
        return 'Server ne link reject kiya (HTTP ${e.code}) — link expire ho gaya. Movie ke player se dubara Download dabao.';
      }
      if (e.code == 404) return 'Server par segment nahi mila (HTTP 404). Dubara Download dabao.';
      if (e.code == 429) return 'Server ne rate-limit kiya (HTTP 429). Thodi der baad Resume dabao.';
      return 'Server error (HTTP ${e.code}). Resume dabao.';
    }
    if (e is HttpException) return 'Server connection error. Resume dabao.';
    return 'Download me error aaya: $e';
  }

  bool _noSpace(FileSystemException e) {
    final int c = e.osError?.errorCode ?? 0;
    return c == 28 || e.message.toLowerCase().contains('no space');
  }

  bool _fatalStatus(Object e) =>
      e is _HttpStatus && (e.code == 403 || e.code == 401 || e.code == 410);

  Future<void> run() async {
    try {
      await _body();
    } catch (e) {
      if (e is _StopSignal || _stop) {
      } else {
        job.state = DlState.failed;
        job.error = _netMsg(e);
        job.speedBps = 0;
        job.stage = '';
        debugPrint('download failed: $e');
      }
    } finally {
      try {
        _client?.close(force: true);
      } catch (_) {}
      if (!_doneC.isCompleted) _doneC.complete();
    }
  }

  Future<void> _body() async {
    job.state = DlState.downloading;
    job.error = '';
    job.stage = 'Starting…';
    store._tick(force: true);
    _baseBytes = job.bytesDone;
    _lastSpeedAt = DateTime.now().millisecondsSinceEpoch;
    final Directory root = await store._jobDir(job.id);
    if (job.kind == 'mp4') {
      await _runMp4(root);
    } else {
      await _runHls(root);
    }
  }

  Future<String> _getText(String url) async {
    Object? last;
    for (int i = 0; i < 4; i++) {
      _check();
      try {
        final HttpClientResponse r = await _open(url);
        if (r.statusCode != 200) {
          await r.drain<void>();
          throw _HttpStatus(r.statusCode);
        }
        final BytesBuilder bb = BytesBuilder();
        await for (final List<int> ch in r.timeout(const Duration(seconds: 30))) {
          bb.add(ch);
        }
        return utf8.decode(bb.takeBytes(), allowMalformed: true);
      } catch (e) {
        if (e is _StopSignal) rethrow;
        if (_stop) throw _StopSignal();
        last = e;
        if (_fatalStatus(e)) break;
        await Future<void>.delayed(Duration(milliseconds: 600 * (i + 1)));
      }
    }
    throw _DlFail(_netMsg(last));
  }

  String _ext(String url, bool fmp4) {
    final String p = (Uri.tryParse(url)?.path ?? '').toLowerCase();
    final int d = p.lastIndexOf('.');
    final String e = d >= 0 ? p.substring(d + 1) : '';
    const List<String> ok = <String>[
      'ts', 'aac', 'm4s', 'mp4', 'm4a', 'm4v', 'mp3', 'ac3', 'eac3', 'cmfv', 'cmfa'
    ];
    if (ok.contains(e)) return e;
    return fmp4 ? 'm4s' : 'ts';
  }

  void _assignNames(_TrackState t) {
    final HlsMedia m = t.media;
    final bool fmp4 = m.mapUrl.isNotEmpty;
    if (fmp4) m.mapName = '${t.id}_init.mp4';
    for (int i = 0; i < m.segs.length; i++) {
      m.segs[i].name = '${t.id}_${i.toString().padLeft(5, '0')}.${_ext(m.segs[i].url, fmp4)}';
    }
  }

  Future<List<_TrackState>> _prepare(Directory root) async {
    final File manifest = File('${root.path}/manifest.json');
    final List<_TrackState> tracks = <_TrackState>[];
    if (manifest.existsSync()) {
      try {
        final Map<String, dynamic> j =
            json.decode(await manifest.readAsString()) as Map<String, dynamic>;
        for (final dynamic t in (j['tracks'] as List<dynamic>)) {
          final Map<String, dynamic> tj = Map<String, dynamic>.from(t as Map<dynamic, dynamic>);
          final String id = tj['id'].toString();
          final Directory d = Directory('${root.path}/$id');
          if (!d.existsSync()) d.createSync(recursive: true);
          final _TrackState ts = _TrackState(id, tj['url'].toString(), d.path);
          ts.media = HlsMedia.fromJson(Map<String, dynamic>.from(tj['m'] as Map<dynamic, dynamic>));
          tracks.add(ts);
        }
        if (tracks.isNotEmpty) return tracks;
      } catch (_) {
        tracks.clear();
      }
    }

    job.stage = 'Playlist padh raha hai…';
    store._tick(force: true);
    final List<String> urls = <String>[job.videoUrl, ...job.audios.map((DlAudioSel a) => a.url)];
    for (int i = 0; i < urls.length; i++) {
      _check();
      final String id = i == 0 ? 'v' : 'a${i - 1}';
      final String text = await _getText(urls[i]);
      if (!HlsParser.isPlaylist(text)) {
        throw _DlFail('Server ne valid playlist nahi diya. Dubara Download dabao.');
      }
      final HlsMedia m = HlsParser.parseMedia(text, Uri.parse(urls[i]));
      if (m.unsupported) {
        throw _DlFail('Ye stream DRM / protected encryption use karti hai — download possible nahi.');
      }
      if (m.segs.isEmpty) {
        throw _DlFail('Playlist me koi video segment nahi mila.');
      }
      final Directory d = Directory('${root.path}/$id');
      if (!d.existsSync()) d.createSync(recursive: true);
      final _TrackState ts = _TrackState(id, urls[i], d.path);
      ts.media = m;
      _assignNames(ts);
      tracks.add(ts);
    }
    await manifest.writeAsString(json.encode(<String, dynamic>{
      'tracks': tracks
          .map((_TrackState t) => <String, dynamic>{'id': t.id, 'url': t.playlistUrl, 'm': t.media.toJson()})
          .toList(),
    }));
    return tracks;
  }

  bool _looksText(Uint8List d) {
    int i = 0;
    while (i < d.length && (d[i] == 0x20 || d[i] == 0x0a || d[i] == 0x0d || d[i] == 0x09)) {
      i++;
    }
    if (i >= d.length) return false;
    return d[i] == 0x3c /* < */ || d[i] == 0x7b /* { */;
  }

  Uint8List _stripJunk(Uint8List d) {
    if (d.length < 564) return d;
    if (d[0] == 0x47 && d[188] == 0x47 && d[376] == 0x47) return d;
    final int lim = math.min(d.length - 377, 8192);
    for (int i = 1; i < lim; i++) {
      if (d[i] == 0x47 && d[i + 188] == 0x47 && d[i + 376] == 0x47) {
        return Uint8List.sublistView(d, i);
      }
    }
    return d;
  }

  Future<void> _fetchKey(HlsKey k, String path) async {
    final File f = File(path);
    if (f.existsSync() && f.lengthSync() == 16) return;
    Object? last;
    for (int i = 0; i < 4; i++) {
      _check();
      try {
        final HttpClientResponse r = await _open(k.uri);
        if (r.statusCode != 200) {
          await r.drain<void>();
          throw _HttpStatus(r.statusCode);
        }
        final BytesBuilder bb = BytesBuilder();
        await for (final List<int> ch in r.timeout(const Duration(seconds: 20))) {
          bb.add(ch);
        }
        final Uint8List b = bb.takeBytes();
        if (b.length != 16) throw _DlFail('Encryption key invalid mili (${b.length} bytes).');
        await f.writeAsBytes(b, flush: true);
        return;
      } catch (e) {
        if (e is _StopSignal || e is _DlFail) rethrow;
        if (_stop) throw _StopSignal();
        last = e;
        if (_fatalStatus(e)) break;
        await Future<void>.delayed(Duration(milliseconds: 600 * (i + 1)));
      }
    }
    throw _DlFail(_netMsg(last));
  }

  Future<void> _fetchSeg(_Task t) async {
    Object? last;
    for (int i = 0; i < 6; i++) {
      _check();
      try {
        final HttpClientResponse r = await _open(t.url, rs: t.rs, rl: t.rl);
        if (r.statusCode != 200 && r.statusCode != 206) {
          await r.drain<void>();
          throw _HttpStatus(r.statusCode);
        }
        final BytesBuilder bb = BytesBuilder();
        await for (final List<int> ch in r.timeout(const Duration(seconds: 25))) {
          bb.add(ch);
          _bytes += ch.length;
        }
        Uint8List data = bb.takeBytes();
        if (data.isEmpty) throw _HttpStatus(0);
        if (t.rl > 0 && r.statusCode == 200 && data.length >= t.rs + t.rl) {
          data = Uint8List.sublistView(data, t.rs, t.rs + t.rl);
        }
        if (data.length < 800 && _looksText(data)) throw _HttpStatus(-1);
        if (t.ts) data = _stripJunk(data);
        final File part = File('${t.path}.part');
        await part.writeAsBytes(data, flush: false);
        await part.rename(t.path);
        return;
      } on FileSystemException catch (e) {
        if (_noSpace(e)) {
          throw _DlFail('Phone ki storage full ho gayi. Jagah khali karke Resume dabao.');
        }
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 400 * (i + 1)));
      } catch (e) {
        if (e is _StopSignal || e is _DlFail) rethrow;
        if (_stop) throw _StopSignal();
        last = e;
        if (_fatalStatus(e) && i >= 1) break;
        final int wait = math.min(8000, 700 * (1 << i));
        await Future<void>.delayed(Duration(milliseconds: wait));
      }
    }
    throw _DlFail(_netMsg(last));
  }

  void _speed() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int dt = now - _lastSpeedAt;
    if (dt >= 1000) {
      final double inst = (_bytes - _lastBytes) * 1000.0 / dt;
      job.speedBps = job.speedBps <= 0 ? inst : job.speedBps * 0.6 + inst * 0.4;
      _lastBytes = _bytes;
      _lastSpeedAt = now;
    }
    job.bytesDone = _baseBytes + _bytes;
  }

  Future<void> _runHls(Directory root) async {
    final List<_TrackState> tracks = await _prepare(root);
    _check();

    for (final _TrackState t in tracks) {
      for (int i = 0; i < t.media.keys.length; i++) {
        await _fetchKey(t.media.keys[i], '${t.dir}/key_$i.bin');
      }
    }

    final List<_Task> all = <_Task>[];
    for (final _TrackState t in tracks) {
      final HlsMedia m = t.media;
      if (m.mapUrl.isNotEmpty) {
        all.add(_Task(m.mapUrl, '${t.dir}/${m.mapName}', m.mapStart, m.mapLen, false));
      }
      for (final HlsSeg s in m.segs) {
        all.add(_Task(s.url, '${t.dir}/${s.name}', s.rangeStart, s.rangeLen,
            m.mapUrl.isEmpty && s.name.endsWith('.ts')));
      }
    }
    final List<_Task> todo = <_Task>[];
    int existing = 0;
    for (final _Task t in all) {
      final File f = File(t.path);
      if (f.existsSync() && f.lengthSync() > 0) {
        existing++;
      } else {
        todo.add(t);
      }
    }
    job.segTotal = all.length;
    job.segDone = existing;
    job.stage = '';
    job.progress = all.isEmpty ? 0 : 0.9 * existing / all.length;
    store._tick(force: true);

    if (todo.isNotEmpty) {
      final Queue<_Task> q = Queue<_Task>.from(todo);
      _DlFail? fatal;
      Future<void> worker() async {
        while (!_stop && fatal == null) {
          if (q.isEmpty) return;
          final _Task t = q.removeFirst();
          try {
            await _fetchSeg(t);
            job.segDone++;
            job.progress = 0.9 * job.segDone / math.max(1, job.segTotal);
            _speed();
            store._tick();
          } catch (e) {
            if (e is _StopSignal || _stop) return;
            fatal ??= e is _DlFail ? e : _DlFail(_netMsg(e));
            return;
          }
        }
      }

      await Future.wait(List<Future<void>>.generate(_conc, (int _) => worker()));
      _check();
      final _DlFail? f = fatal;
      if (f != null) throw f;
    }

    job.speedBps = 0;
    await _merge(root, tracks);
  }

  String _localPlaylist(_TrackState t) {
    final HlsMedia m = t.media;
    final StringBuffer sb = StringBuffer();
    sb.writeln('#EXTM3U');
    sb.writeln('#EXT-X-VERSION:${m.mapUrl.isNotEmpty ? 7 : 3}');
    sb.writeln('#EXT-X-TARGETDURATION:${math.max(1, m.targetDur.ceil())}');
    sb.writeln('#EXT-X-MEDIA-SEQUENCE:${m.mediaSeq}');
    sb.writeln('#EXT-X-PLAYLIST-TYPE:VOD');
    int cur = -2;
    bool mapWritten = false;
    for (final HlsSeg s in m.segs) {
      if (s.disc) sb.writeln('#EXT-X-DISCONTINUITY');
      if (s.keyIdx != cur) {
        cur = s.keyIdx;
        if (cur < 0) {
          sb.writeln('#EXT-X-KEY:METHOD=NONE');
        } else {
          final HlsKey k = m.keys[cur];
          sb.write('#EXT-X-KEY:METHOD=AES-128,URI="key_$cur.bin"');
          if (k.iv.isNotEmpty) sb.write(',IV=${k.iv}');
          sb.writeln();
        }
      }
      if (m.mapUrl.isNotEmpty && !mapWritten) {
        sb.writeln('#EXT-X-MAP:URI="${m.mapName}"');
        mapWritten = true;
      }
      sb.writeln('#EXTINF:${(s.dur > 0 ? s.dur : 6).toStringAsFixed(6)},');
      sb.writeln(s.name);
    }
    sb.writeln('#EXT-X-ENDLIST');
    return sb.toString();
  }

  Future<bool> _ffmpeg(List<String> args, void Function(double) onProgress) async {
    final Completer<bool> c = Completer<bool>();
    final String cmd = args.map(_q).join(' ');
    await FFmpegKit.executeAsync(
      cmd,
      (dynamic session) async {
        bool ok = false;
        try {
          final dynamic rc = await session.getReturnCode();
          ok = ReturnCode.isSuccess(rc as ReturnCode?);
        } catch (_) {}
        if (!c.isCompleted) c.complete(ok);
      },
      (dynamic log) {},
      (dynamic st) {
        try {
          final dynamic tt = st.getTime();
          final double ms = tt is num ? tt.toDouble() : 0;
          if (job.durationSec > 0 && ms > 0) {
            onProgress((ms / 1000.0 / job.durationSec).clamp(0.0, 1.0).toDouble());
          }
        } catch (_) {}
      },
    );
    return c.future;
  }

  Future<void> _merge(Directory root, List<_TrackState> tracks) async {
    _check();
    job.state = DlState.merging;
    job.stage = 'Converting (playable MP4 ban rahi hai)…';
    job.progress = 0.9;
    store._tick(force: true);

    for (final _TrackState t in tracks) {
      await File('${t.dir}/${t.id}.m3u8').writeAsString(_localPlaylist(t));
    }
    final String vPl = '${tracks.first.dir}/v.m3u8';
    final List<_TrackState> aTracks = tracks.sublist(1);

    final Directory movies = await store._movieDir();
    final String stem = '${_safeName(job.title)}'
        '${job.isTv ? '_S${job.season}E${job.episode}' : ''}'
        '_${_safeName(job.qualityLabel, max: 10)}_${job.createdAt % 100000}';

    final List<List<String>> variants = <List<String>>[
      <String>['mp4', job.audioNeedsAac ? 'aac' : 'copy'],
      <String>['mp4', 'aac'],
      <String>['mkv', job.audioNeedsAac ? 'aac' : 'copy'],
    ];

    String outPath = '';
    for (int a = 0; a < variants.length; a++) {
      _check();
      if (a == 1 && variants[0][1] == 'aac') continue; 
      final String ext = variants[a][0];
      final bool aac = variants[a][1] == 'aac';
      final String out = '${movies.path}/$stem.$ext';
      try {
        final File old = File(out);
        if (old.existsSync()) old.deleteSync();
      } catch (_) {}

      final List<String> args = <String>['-y', '-hide_banner'];
      void input(String p) {
        args.addAll(<String>[
          '-allowed_extensions', 'ALL',
          '-protocol_whitelist', 'file,crypto,data',
          '-fflags', '+genpts',
          '-i', p,
        ]);
      }

      input(vPl);
      for (final _TrackState t in aTracks) {
        input('${t.dir}/${t.id}.m3u8');
      }
      args.addAll(<String>['-map', '0:v:0']);
      if (aTracks.isEmpty) {
        args.addAll(<String>['-map', '0:a?']);
      } else {
        for (int i = 0; i < aTracks.length; i++) {
          args.addAll(<String>['-map', '${i + 1}:a:0']);
        }
        for (int i = 0; i < aTracks.length; i++) {
          final DlAudioSel sel = job.audios[i];
          final String nm = _metaSafe(sel.name).isEmpty ? 'Audio ${i + 1}' : _metaSafe(sel.name);
          args.addAll(<String>[
            '-metadata:s:a:$i', 'language=${dlLang3(sel.lang)}',
            '-metadata:s:a:$i', 'title=$nm',
            '-metadata:s:a:$i', 'handler_name=$nm',
            '-disposition:a:$i', i == 0 ? 'default' : '0',
          ]);
        }
      }
      args.addAll(<String>['-c:v', 'copy']);
      if (aac) {
        args.addAll(<String>['-c:a', 'aac', '-b:a', '192k']);
      } else {
        args.addAll(<String>['-c:a', 'copy']);
      }
      if (ext == 'mp4') {
        if (job.hevc) args.addAll(<String>['-tag:v', 'hvc1']);
        args.addAll(<String>['-movflags', '+faststart']);
      }
      args.addAll(<String>[
        '-avoid_negative_ts', 'make_zero',
        '-map_metadata', '-1',
        '-metadata', 'title=${_metaSafe(job.title)}',
        out,
      ]);

      final bool ok = await _ffmpeg(args, (double p) {
        job.progress = 0.9 + 0.1 * p;
        store._tick();
      });
      _check();
      final File of = File(out);
      if (ok && of.existsSync() && of.lengthSync() > 200 * 1024) {
        outPath = out;
        break;
      }
      try {
        if (of.existsSync()) of.deleteSync();
      } catch (_) {}
    }

    if (outPath.isEmpty) {
      throw _DlFail('Converter movie ko jod nahi paya. Dubara Download dabao (naya link).');
    }

    job.filePath = outPath;
    job.fileBytes = File(outPath).lengthSync();
    job.progress = 1;
    job.speedBps = 0;
    job.state = DlState.done;
    job.stage = job.exportToGallery ? 'Phone Movies folder me save ho raha hai…' : '';
    store._tick(force: true);

    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } catch (_) {}

    if (job.exportToGallery) await _exportGallery();
    job.stage = '';
    store._tick(force: true);
  }

  Future<void> _exportGallery() async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) return;
      }
      await Gal.putVideo(job.filePath, album: 'HANNUTV');
      job.galleryDone = true;
    } catch (e) {
      debugPrint('gallery export error: $e');
    }
  }

  Future<void> _runMp4(Directory root) async {
    final File part = File('${root.path}/video.mp4.part');
    int have = part.existsSync() ? part.lengthSync() : 0;
    int total = job.estBytes;
    Object? last;
    bool finished = false;
    job.stage = '';
    for (int attempt = 0; attempt < 25 && !finished; attempt++) {
      _check();
      try {
        final HttpClientResponse r = await _open(job.videoUrl, from: have);
        if (r.statusCode == 416 && have > 0) {
          await r.drain<void>();
          finished = true;
          break;
        }
        if (r.statusCode != 200 && r.statusCode != 206) {
          await r.drain<void>();
          throw _HttpStatus(r.statusCode);
        }
        bool append = false;
        if (r.statusCode == 206 && have > 0) {
          append = true;
          final String cr = r.headers.value('content-range') ?? '';
          final int slash = cr.lastIndexOf('/');
          if (slash > 0) total = int.tryParse(cr.substring(slash + 1)) ?? total;
        } else {
          have = 0;
          if (r.contentLength > 0) total = r.contentLength;
        }
        final IOSink sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
        try {
          await for (final List<int> ch in r.timeout(const Duration(seconds: 30))) {
            sink.add(ch);
            have += ch.length;
            _bytes += ch.length;
            if (total > 0) job.progress = 0.97 * have / total;
            job.segDone = have;
            job.segTotal = total;
            _speed();
            store._tick();
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        finished = true;
      } catch (e) {
        if (e is _StopSignal) rethrow;
        if (_stop) throw _StopSignal();
        if (e is FileSystemException && _noSpace(e)) {
          throw _DlFail('Phone ki storage full ho gayi. Jagah khali karke Resume dabao.');
        }
        last = e;
        if (_fatalStatus(e)) break;
        have = part.existsSync() ? part.lengthSync() : 0;
        await Future<void>.delayed(Duration(milliseconds: math.min(8000, 800 * (attempt + 1))));
      }
    }
    if (!finished) throw _DlFail(_netMsg(last));
    _check();

    final Directory movies = await store._movieDir();
    final String out = '${movies.path}/${_safeName(job.title)}'
        '${job.isTv ? '_S${job.season}E${job.episode}' : ''}_${job.createdAt % 100000}.mp4';
    try {
      final File old = File(out);
      if (old.existsSync()) old.deleteSync();
    } catch (_) {}
    await part.rename(out);
    job.filePath = out;
    job.fileBytes = File(out).lengthSync();
    job.progress = 1;
    job.speedBps = 0;
    job.state = DlState.done;
    job.stage = job.exportToGallery ? 'Phone Movies folder me save ho raha hai…' : '';
    store._tick(force: true);
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } catch (_) {}
    if (job.exportToGallery) await _exportGallery();
    job.stage = '';
    store._tick(force: true);
  }
}