import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'download_manager.dart'; // Is line ko theek se joda hai
import 'downloads_page.dart';

const String _kDefaultUa =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Mobile Safari/537.36';

class SniffHit {
  const SniffHit(this.kind, this.url, this.ref, this.ua, this.cookie);
  final String kind; 
  final String url;
  final String ref;
  final String ua;
  final String cookie;
}

const String _kSniffJs = r'''
(function () {
  if (window.__hnInit) { if (window.__hnScan) window.__hnScan(); return; }
  window.__hnInit = true;
  var seen = {};
  function post(k, u) {
    try {
      if (!u || typeof u !== 'string') return;
      if (u.indexOf('blob:') === 0 || u.indexOf('data:') === 0 || u.indexOf('javascript:') === 0) return;
      var abs = new URL(u, location.href).href;
      var key = k + '|' + abs;
      if (seen[key]) return;
      seen[key] = 1;
      DlSniff.postMessage(JSON.stringify({ k: k, u: abs, ref: location.href, ua: navigator.userAgent, ck: document.cookie || '' }));
    } catch (e) {}
  }
  function check(u, ct) {
    try {
      if (!u) return;
      var s = String(u), low = s.toLowerCase(), c = String(ct || '').toLowerCase();
      if (/\.m3u8(\?|#|$)/.test(low) || c.indexOf('mpegurl') > -1) post('m3u8', s);
      else if (/\.mp4(\?|#|$)/.test(low) && !/(\/ads?\/|preroll|promo|trailer)/.test(low)) post('mp4', s);
      else if (/\.mpd(\?|#|$)/.test(low) || c.indexOf('dash+xml') > -1) post('mpd', s);
    } catch (e) {}
  }
  function scanText(t) {
    try {
      if (!t || t.length > 400000) return;
      t = String(t).replace(/\\\//g, '/');
      var re = /https?:\/\/[^"'\s\\<>]+?\.m3u8[^"'\s\\<>]*/gi, m;
      while ((m = re.exec(t)) !== null) post('m3u8', m[0]);
    } catch (e) {}
  }
  try { window.open = function () { return null; }; } catch (e) {}

  var _f = window.fetch;
  if (_f) {
    window.fetch = function () {
      var a = arguments, u = '';
      try { u = (a[0] && a[0].url) ? a[0].url : a[0]; check(u, ''); } catch (e) {}
      var p = _f.apply(this, a);
      try {
        p.then(function (r) {
          try {
            var ct = (r.headers && r.headers.get('content-type')) || '';
            check(r.url || u, ct);
            if (ct.indexOf('json') > -1 || ct.indexOf('text/plain') > -1) r.clone().text().then(scanText).catch(function () {});
          } catch (e) {}
        }).catch(function () {});
      } catch (e) {}
      return p;
    };
  }

  var _o = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    try {
      var self = this; check(u, '');
      this.addEventListener('load', function () {
        try {
          var ct = self.getResponseHeader('content-type') || '';
          check(self.responseURL || u, ct);
          if ((ct.indexOf('json') > -1 || ct.indexOf('text/plain') > -1) && (self.responseType === '' || self.responseType === 'text')) scanText(self.responseText);
        } catch (e) {}
      });
    } catch (e) {}
    return _o.apply(this, arguments);
  };

  try {
    var d = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (d && d.set) Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      get: d.get, configurable: true,
      set: function (v) { check(v, ''); return d.set.call(this, v); }
    });
  } catch (e) {}

  function hookHls() {
    try {
      if (window.Hls && window.Hls.prototype && !window.Hls.prototype.__hn) {
        var ls = window.Hls.prototype.loadSource;
        window.Hls.prototype.loadSource = function (u) { check(u, ''); return ls.apply(this, arguments); };
        window.Hls.prototype.__hn = 1;
      }
    } catch (e) {}
  }

  function scan() {
    try { if (performance.setResourceTimingBufferSize) performance.setResourceTimingBufferSize(20000); } catch (e) {}
    try {
      var es = performance.getEntriesByType('resource');
      for (var i = 0; i < es.length; i++) check(es[i].name, '');
    } catch (e) {}
    hookHls();
    try {
      var vs = document.querySelectorAll('video');
      for (var j = 0; j < vs.length; j++) {
        var v = vs[j];
        check(v.currentSrc || v.src, '');
        try { v.muted = true; v.volume = 0; if (v.paused) { var pr = v.play(); if (pr && pr.catch) pr.catch(function () {}); } } catch (e) {}
      }
      var ss = document.querySelectorAll('source');
      for (var s = 0; s < ss.length; s++) check(ss[s].src, '');
    } catch (e) {}
    try {
      var fr = document.getElementsByTagName('iframe');
      for (var f = 0; f < fr.length; f++) { var src = fr[f].src || ''; if (src.indexOf('http') === 0) post('frame', src); }
    } catch (e) {}
    try {
      var sels = ['.jw-icon-display', '.vjs-big-play-button', '.plyr__control--overlaid', '[class*="big-play" i]', '[class*="play-btn" i]', '[class*="playbtn" i]', '.play-button', '#play', '[aria-label="Play" i]'];
      for (var q = 0; q < sels.length; q++) {
        var els = document.querySelectorAll(sels[q]);
        for (var w = 0; w < els.length && w < 2; w++) {
          var el = els[w];
          if (!el.__hnc || el.__hnc < 3) { el.__hnc = (el.__hnc || 0) + 1; try { el.click(); } catch (e) {} }
        }
      }
      var bs = document.querySelectorAll('button, div[role="button"], a, span');
      for (var b = 0; b < bs.length && b < 400; b++) {
        var t = (bs[b].innerText || '').toLowerCase().trim();
        if (t === "i'm not a robot" || t === 'im not a robot' || t === 'continue' || t === 'verify' || t === 'play') {
          if (!bs[b].__hnc || bs[b].__hnc < 3) { bs[b].__hnc = (bs[b].__hnc || 0) + 1; try { bs[b].click(); } catch (e) {} }
        }
      }
    } catch (e) {}
  }
  window.__hnScan = scan;
  setInterval(scan, 700);
  scan();
})();
''';

final RegExp _kBadUrl = RegExp(
    r'(doubleclick|adsterra|popads|highrevenue|profitablerate|omg10|1xbet|bet365|leela|thufd|googlesyndication|google\.com|facebook|recaptcha|analytics|(^|[./?=&_-])(ads?|pop|track)([./?=&_-]|$))');

class StreamSniffer {
  StreamSniffer({required this.onHit, required this.onStatus}) {
    _init();
  }

  final void Function(SniffHit) onHit;
  final void Function(String) onStatus;
  late final WebViewController controller;

  Timer? _timer;
  bool _disposed = false;
  bool gotStream = false;
  String _currentUrl = '';
  DateTime _lastNavAt = DateTime.now();
  int _hops = 0;
  final Set<String> _seen = <String>{};
  final Set<String> _visited = <String>{};
  final List<String> _frames = <String>[];

  void _init() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setOnJavaScriptAlertDialog((JavaScriptAlertDialogRequest request) async {})
      ..setOnJavaScriptConfirmDialog((JavaScriptConfirmDialogRequest request) async => true)
      ..setOnJavaScriptTextInputDialog((JavaScriptTextInputDialogRequest request) async => '')
      ..addJavaScriptChannel('DlSniff', onMessageReceived: _onMsg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String u) {
            _currentUrl = u;
            _inject();
          },
          onPageFinished: (String u) {
            _currentUrl = u;
            _inject();
          },
          onNavigationRequest: (NavigationRequest r) {
            final String u = r.url.toLowerCase();
            if (u.startsWith('intent://') ||
                u.startsWith('market://') ||
                u.startsWith('whatsapp://') ||
                u.startsWith('tg://') ||
                _kBadUrl.hasMatch(u)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    try {
      final dynamic p = controller.platform;
      if (p is AndroidWebViewController) {
        p.setMediaPlaybackRequiresUserGesture(false);
      }
    } catch (_) {}
  }

  void start(String url, {String? referer}) {
    _visited.add(url);
    _go(url, referer);
    _timer = Timer.periodic(const Duration(milliseconds: 900), (Timer _) => _onTick());
  }

  void _go(String url, String? referer) {
    _currentUrl = url;
    _lastNavAt = DateTime.now();
    try {
      controller.loadRequest(
        Uri.parse(url),
        headers: referer == null ? const <String, String>{} : <String, String>{'Referer': referer},
      );
    } catch (_) {}
  }

  void _inject() {
    if (_disposed) return;
    try {
      controller.runJavaScript(_kSniffJs).catchError((Object _) {});
    } catch (_) {}
  }

  void _onTick() {
    if (_disposed) return;
    _inject();
    final int idle = DateTime.now().difference(_lastNavAt).inMilliseconds;
    if (!gotStream && idle > 4500 && _hops < 3) {
      String? next;
      for (final String f in _frames) {
        if (!_visited.contains(f) && !_kBadUrl.hasMatch(f.toLowerCase())) {
          next = f;
          break;
        }
      }
      if (next != null) {
        _hops++;
        _visited.add(next);
        onStatus('Player server me ja raha hai…');
        _go(next, _currentUrl.startsWith('http') ? _currentUrl : null);
      }
    }
  }

  void _onMsg(JavaScriptMessage m) {
    if (_disposed) return;
    try {
      final Map<String, dynamic> j = json.decode(m.message) as Map<String, dynamic>;
      final String k = (j['k'] ?? '').toString();
      final String u = (j['u'] ?? '').toString();
      if (u.isEmpty) return;
      if (k == 'frame') {
        if (!_frames.contains(u)) _frames.add(u);
        return;
      }
      if (k != 'm3u8' && k != 'mp4') return;
      if (!_seen.add('$k|$u')) return;
      gotStream = true;
      onStatus('Stream link mil gaya ✓');
      onHit(SniffHit(k, u, (j['ref'] ?? '').toString(), (j['ua'] ?? '').toString(),
          (j['ck'] ?? '').toString()));
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    try {
      controller.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
  }
}

Future<void> showDownloadSheet(
  BuildContext context, {
  required int tmdbId,
  required String mediaType,
  required int season,
  required int episode,
  required String title,
  required String year,
  required String posterPath,
  String server = 'vidrift',
  String? replaceJobId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF151515),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (BuildContext _) => _DlSheet(
      host: context,
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: season,
      episode: episode,
      title: title,
      year: year,
      posterPath: posterPath,
      server: server,
      replaceJobId: replaceJobId,
    ),
  );
}

enum _Phase { scanning, ready, error }

class _DlSheet extends StatefulWidget {
  const _DlSheet({
    required this.host,
    required this.tmdbId,
    required this.mediaType,
    required this.season,
    required this.episode,
    required this.title,
    required this.year,
    required this.posterPath,
    required this.server,
    this.replaceJobId,
  });
  final BuildContext host;
  final int tmdbId;
  final String mediaType;
  final int season;
  final int episode;
  final String title;
  final String year;
  final String posterPath;
  final String server;
  final String? replaceJobId;

  @override
  State<_DlSheet> createState() => _DlSheetState();
}

class _DlSheetState extends State<_DlSheet> {
  _Phase phase = _Phase.scanning;
  String status = 'Server se connect ho raha hai…';
  String errorMsg = '';

  StreamSniffer? sniffer;
  int sniffGen = 0;
  final List<SniffHit> hits = <SniffHit>[];
  Timer? analyzeTimer;
  Timer? timeoutTimer;
  bool analyzing = false;
  List<List<String>> strategies = <List<String>>[]; 
  int strategyIdx = 0;

  DlSource? src;
  int qIdx = 0;
  Set<int> aSel = <int>{};
  bool exportGal = true;
  bool busy = false;

  final TextEditingController manual = TextEditingController();
  bool showManual = false;

  bool get _isTv => widget.mediaType == 'tv' || widget.mediaType == 'series';

  @override
  void initState() {
    super.initState();
    strategies = _buildStrategies();
    _startStrategy(0, notify: false);
  }

  @override
  void dispose() {
    analyzeTimer?.cancel();
    timeoutTimer?.cancel();
    sniffer?.dispose();
    manual.dispose();
    super.dispose();
  }

  List<List<String>> _buildStrategies() {
    final String tail = _isTv
        ? 'tv/${widget.tmdbId}/${widget.season}/${widget.episode}'
        : 'movie/${widget.tmdbId}';
    final String vid = 'https://embed.vidrift.in/embed/$tail';
    final String orig = _isTv
        ? 'https://pantyflix.com/watch/play/tv/${widget.tmdbId}?season=${widget.season}&episode=${widget.episode}&server=${widget.server}'
        : 'https://pantyflix.com/watch/play/movie/${widget.tmdbId}?server=${widget.server}';
    final String proxy =
        'https://hannutv-proxy-1.vercel.app/api/proxy?stream=${Uri.encodeComponent(orig)}';
    if (widget.server == 'vidrift') {
      return <List<String>>[
        <String>[vid, 'https://pantyflix.com/'],
        <String>[proxy, ''],
      ];
    }
    return <List<String>>[
      <String>[proxy, ''],
    ];
  }

  void _setStatus(String m) {
    if (mounted && phase == _Phase.scanning) setState(() => status = m);
  }

  void _startStrategy(int i, {bool notify = true}) {
    sniffer?.dispose();
    analyzeTimer?.cancel();
    timeoutTimer?.cancel();
    hits.clear();
    final StreamSniffer s = StreamSniffer(onHit: _onHit, onStatus: _setStatus);
    sniffer = s;
    sniffGen++;
    strategyIdx = i;
    phase = _Phase.scanning;
    status = i == 0 ? 'Server se connect ho raha hai…' : 'Dusre route se try ho raha hai…';
    final List<String> st = strategies[i];
    s.start(st[0], referer: st[1].isEmpty ? null : st[1]);
    timeoutTimer = Timer(const Duration(seconds: 32), _onTimeout);
    if (notify && mounted) setState(() {});
  }

  void _onHit(SniffHit h) {
    hits.add(h);
    analyzeTimer?.cancel();
    analyzeTimer = Timer(Duration(milliseconds: h.kind == 'm3u8' ? 2500 : 5000), _runAnalyze);
  }

  Future<void> _runAnalyze() async {
    if (analyzing || !mounted || phase != _Phase.scanning) return;
    analyzing = true;
    _setStatus('Stream analyze ho rahi hai…');
    DlSource? s;
    try {
      s = await DlAnalyzer.analyze(List<SniffHit>.of(hits), _setStatus);
    } catch (_) {}
    analyzing = false;
    if (!mounted) return;
    if (s == null) {
      _setStatus('Aur links ka wait…');
      return;
    }
    if (s.drm) {
      _fail('Ye stream DRM / protected encryption use karti hai — download possible nahi.');
      return;
    }
    if (s.live) {
      _fail('Ye live stream hai, isse download nahi kiya ja sakta.');
      return;
    }
    timeoutTimer?.cancel();
    sniffer?.dispose();
    sniffer = null;
    setState(() {
      src = s;
      qIdx = 0;
      _resetAudio(<String>[]);
      phase = _Phase.ready;
    });
  }

  Future<void> _onTimeout() async {
    if (!mounted || phase != _Phase.scanning) return;
    if (hits.isNotEmpty && !analyzing) {
      await _runAnalyze();
      if (!mounted || phase != _Phase.scanning) return;
    }
    if (strategyIdx + 1 < strategies.length) {
      _startStrategy(strategyIdx + 1);
    } else {
      _fail('Is server se stream link nahi mila. Dusra server chun kar try karo, '
          'ya niche "Link paste karo" se embed / m3u8 link daalo.');
    }
  }

  void _fail(String m) {
    timeoutTimer?.cancel();
    analyzeTimer?.cancel();
    sniffer?.dispose();
    sniffer = null;
    if (!mounted) return;
    setState(() {
      errorMsg = m;
      phase = _Phase.error;
    });
  }

  void _submitManual() {
    final String u = manual.text.trim();
    if (!u.toLowerCase().startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valid link daalo (http se shuru).')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final String low = u.toLowerCase();
    if (low.contains('.m3u8') || low.contains('.mp4')) {
      final Uri r = Uri.parse(u);
      final String origin = '${r.scheme}://${r.host}';
      sniffer?.dispose();
      timeoutTimer?.cancel();
      hits
        ..clear()
        ..add(SniffHit(low.contains('.m3u8') ? 'm3u8' : 'mp4', u, '$origin/', _kDefaultUa, ''));
      setState(() {
        phase = _Phase.scanning;
        status = 'Link analyze ho raha hai…';
        showManual = false;
      });
      timeoutTimer = Timer(const Duration(seconds: 40), () {
        if (mounted && phase == _Phase.scanning) _fail('Ye link analyze nahi ho paya.');
      });
      _runAnalyze();
    } else {
      strategies = <List<String>>[
        <String>[u, ''],
      ];
      setState(() => showManual = false);
      _startStrategy(0);
    }
  }

  List<HlsAudio> _audiosFor(HlsVariant v) {
    final DlSource s = src!;
    if (s.audios.isEmpty) return <HlsAudio>[];
    List<HlsAudio> g = v.audioGroup.isEmpty
        ? s.audios
        : s.audios.where((HlsAudio a) => a.groupId == v.audioGroup).toList();
    if (g.isEmpty) {
      final String first = s.audios.first.groupId;
      g = s.audios.where((HlsAudio a) => a.groupId == first).toList();
    }
    return g;
  }

  void _resetAudio(List<String> keepNames) {
    if (src == null) return;
    final List<HlsAudio> auds = _audiosFor(src!.variants[qIdx]);
    final Set<int> sel = <int>{};
    for (int i = 0; i < auds.length; i++) {
      if (keepNames.contains(auds[i].display)) sel.add(i);
    }
    if (sel.isEmpty && auds.isNotEmpty) {
      int d = auds.indexWhere((HlsAudio a) => a.isDefault);
      if (d < 0) d = 0;
      sel.add(d);
    }
    aSel = sel;
  }

  int _est(HlsVariant v, int nAud) {
    final DlSource s = src!;
    if (s.kind == 'mp4') return s.singleSize;
    if (v.bps <= 0) return s.singleSize;
    if (s.durationSec <= 0) return 0;
    return ((v.bps + 128000 * nAud) * s.durationSec / 8).round();
  }

  Future<void> _start() async {
    if (busy || src == null) return;
    final DlSource s = src!;
    final HlsVariant v = s.variants[qIdx];
    final List<HlsAudio> auds = _audiosFor(v);
    if (auds.isNotEmpty && aSel.isEmpty) return;
    setState(() => busy = true);

    final List<int> idx = aSel.where((int i) => i < auds.length).toList()..sort();
    final int def = idx.indexWhere((int i) => auds[i].isDefault);
    if (def > 0) {
      final int d = idx.removeAt(def);
      idx.insert(0, d);
    }
    final List<DlAudioSel> sel = <DlAudioSel>[
      for (final int i in idx) DlAudioSel(auds[i].display, auds[i].lang, auds[i].url),
    ];
    String langLabel;
    if (sel.isEmpty) {
      langLabel = 'Original audio';
    } else if (auds.length > 1 && sel.length == auds.length) {
      langLabel = 'All audio (${sel.length})';
    } else {
      langLabel = sel.map((DlAudioSel a) => a.name).join(' + ');
    }

    bool gal = exportGal;
    if (gal) {
      final bool ok = await DownloadStore.I.ensureStorageAccess();
      if (!ok) gal = false;
    }
    if (!mounted) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    final DlJob job = DlJob(
      id: now.toString(),
      tmdbId: widget.tmdbId,
      isTv: _isTv,
      title: widget.title,
      year: widget.year,
      posterPath: widget.posterPath,
      season: widget.season,
      episode: widget.episode,
      qualityLabel: v.label,
      langLabel: langLabel,
      videoUrl: v.url,
      audios: sel,
      headers: s.headers,
      durationSec: s.durationSec,
      estBytes: _est(v, sel.length),
      exportToGallery: gal,
      kind: s.kind,
      hevc: v.isHevc,
      audioNeedsAac: v.codecs.isNotEmpty && !v.codecs.toLowerCase().contains('mp4a'),
      createdAt: now,
    );

    final ScaffoldMessengerState sm = ScaffoldMessenger.of(context);
    final NavigatorState nav = Navigator.of(context);
    final BuildContext host = widget.host;

    if (widget.replaceJobId != null) {
      await DownloadStore.I.remove(widget.replaceJobId!);
    }
    final DlJob? dup = DownloadStore.I.duplicateOf(job.dupKey);
    if (dup != null) {
      nav.pop();
      sm.showSnackBar(SnackBar(
        content: Text(dup.state == DlState.done
            ? 'Ye pehle se downloaded hai — Downloads me dekho.'
            : 'Ye download pehle se chal raha hai.'),
        backgroundColor: Colors.orange[800],
      ));
      return;
    }

    await DownloadStore.I.enqueue(job);
    nav.pop();
    sm.showSnackBar(SnackBar(
      content: Text('Download shuru: ${widget.title} • ${v.label} • $langLabel'),
      backgroundColor: Colors.green[700],
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'OPEN',
        textColor: Colors.white,
        onPressed: () {
          if (host.mounted) {
            Navigator.of(host).push(MaterialPageRoute<void>(builder: (_) => const DownloadsPage()));
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final double maxH = MediaQuery.of(context).size.height * 0.88;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _header(),
                const SizedBox(height: 12),
                if (phase == _Phase.scanning) _scanning(),
                if (phase == _Phase.error) _error(),
                if (phase == _Phase.ready) _ready(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final String sub = _isTv
        ? '${widget.title}  •  S${widget.season.toString().padLeft(2, '0')} E${widget.episode.toString().padLeft(2, '0')}'
        : widget.title;
    return Row(
      children: <Widget>[
        const Icon(Icons.download_for_offline_rounded, color: Colors.redAccent, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Download',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _manualBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 10),
        TextField(
          controller: manual,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'https://embed.vidrift.in/embed/tv/1416/1/1  ya  .m3u8 / .mp4 link',
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded, color: Colors.redAccent),
              onPressed: _submitManual,
            ),
          ),
          onSubmitted: (String _) => _submitManual(),
        ),
      ],
    );
  }

  Widget _scanning() {
    final StreamSniffer? s = sniffer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (s != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 150,
              color: Colors.black,
              child: Stack(
                children: <Widget>[
                  IgnorePointer(child: WebViewWidget(key: ValueKey<int>(sniffGen), controller: s.controller)),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: const Text('LIVE SERVER SCAN',
                          style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        const LinearProgressIndicator(color: Colors.redAccent, backgroundColor: Colors.white12, minHeight: 3),
        const SizedBox(height: 12),
        Text(status, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'Isi server ki qualities, languages aur size dhundh raha hai (10-30 sec).',
          style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => setState(() => showManual = !showManual),
          icon: const Icon(Icons.link_rounded, size: 18, color: Colors.white70),
          label: const Text('Link paste karo', style: TextStyle(color: Colors.white70)),
        ),
        if (showManual) _manualBox(),
      ],
    );
  }

  Widget _error() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(errorMsg, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  strategies = _buildStrategies();
                  _startStrategy(0);
                },
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => showManual = !showManual),
                icon: const Icon(Icons.link_rounded, color: Colors.white70, size: 18),
                label: const Text('Link paste karo', style: TextStyle(color: Colors.white70)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
        if (showManual) _manualBox(),
      ],
    );
  }

  Widget _ready() {
    final DlSource s = src!;
    final HlsVariant cur = s.variants[qIdx];
    final List<HlsAudio> auds = _audiosFor(cur);
    final int nAud = auds.isEmpty ? 0 : aSel.length;
    final int est = _est(cur, nAud);
    final String dur = dlDuration(s.durationSec);

    final List<Widget> kids = <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: <Widget>[
          _pill(Icons.dns_rounded, s.host.isEmpty ? 'server' : s.host),
          if (dur.isNotEmpty) _pill(Icons.schedule_rounded, dur),
          _pill(Icons.movie_filter_rounded, s.kind == 'hls' ? 'HLS → MP4 converter' : 'Direct MP4'),
        ],
      ),
      const SizedBox(height: 16),
      const Text('Quality', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
    ];

    for (int i = 0; i < s.variants.length; i++) {
      final HlsVariant v = s.variants[i];
      final bool on = i == qIdx;
      final int e = _est(v, nAud);
      kids.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            final List<String> keep = auds
                .asMap()
                .entries
                .where((MapEntry<int, HlsAudio> en) => aSel.contains(en.key))
                .map((MapEntry<int, HlsAudio> en) => en.value.display)
                .toList();
            setState(() {
              qIdx = i;
              _resetAudio(keep);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? Colors.redAccent.withOpacity(0.14) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? Colors.redAccent : Colors.white12),
            ),
            child: Row(
              children: <Widget>[
                Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: on ? Colors.redAccent : Colors.white38, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(v.label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          if (v.height >= 1080) _tag('FULL HD', Colors.amber),
                          if (v.height >= 720 && v.height < 1080) _tag('HD', Colors.lightBlueAccent),
                          if (v.isHevc) _tag('HEVC', Colors.purpleAccent),
                        ],
                      ),
                      if (v.width > 0 && v.height > 0)
                        Text('${v.width}×${v.height}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                Text(e > 0 ? '~${dlBytes(e)}' : 'size ?',
                    style: TextStyle(
                        color: on ? Colors.white : Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ));
    }

    kids.add(const SizedBox(height: 10));
    kids.add(Row(
      children: <Widget>[
        const Expanded(
          child: Text('Audio / Language',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        if (auds.length > 1)
          TextButton(
            onPressed: () => setState(() {
              if (aSel.length == auds.length) {
                _resetAudio(<String>[]);
              } else {
                aSel = Set<int>.from(List<int>.generate(auds.length, (int i) => i));
              }
            }),
            child: Text(aSel.length == auds.length ? 'Sirf default' : 'Sab audio',
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
      ],
    ));
    if (auds.isEmpty) {
      kids.add(const Text(
        'Is stream me audio video ke saath hi judi hai (Original audio). Alag language track nahi mila.',
        style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
      ));
    } else {
      kids.add(Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List<Widget>.generate(auds.length, (int i) {
          final bool on = aSel.contains(i);
          return FilterChip(
            selected: on,
            showCheckmark: true,
            checkmarkColor: Colors.white,
            selectedColor: Colors.redAccent,
            backgroundColor: Colors.white10,
            side: BorderSide(color: on ? Colors.redAccent : Colors.white24),
            label: Text(
              auds[i].display + (auds[i].isDefault ? ' • default' : ''),
              style: TextStyle(color: Colors.white, fontWeight: on ? FontWeight.w800 : FontWeight.w500),
            ),
            onSelected: (bool v) => setState(() {
              if (v) {
                aSel.add(i);
              } else if (aSel.length > 1) {
                aSel.remove(i);
              }
            }),
          );
        }),
      ));
      kids.add(const SizedBox(height: 6));
      kids.add(Text(
        aSel.length > 1
            ? 'Sab selected audio ek hi movie file me judenge — VLC / MX Player me audio track badal sakte ho.'
            : 'Sirf selected language download hogi.',
        style: const TextStyle(color: Colors.grey, fontSize: 11.5, height: 1.4),
      ));
    }

    kids.add(const SizedBox(height: 10));
    kids.add(SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: Colors.redAccent,
      value: exportGal,
      onChanged: (bool v) => setState(() => exportGal = v),
      title: const Text('Phone ke Movies folder me bhi save karo',
          style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: const Text('VLC / MX Player / Gallery me dikhegi (thodi extra storage lagti hai).',
          style: TextStyle(color: Colors.grey, fontSize: 11.5)),
    ));

    final bool canGo = !busy && (auds.isEmpty || aSel.isNotEmpty);
    kids.add(const SizedBox(height: 6));
    kids.add(SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: canGo ? _start : null,
        icon: busy
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.download_rounded, color: Colors.white),
        label: Text(
          est > 0 ? 'Download  •  ${cur.label}  •  ~${dlBytes(est)}' : 'Download  •  ${cur.label}',
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          disabledBackgroundColor: Colors.white12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ));
    kids.add(const SizedBox(height: 6));
    kids.add(const Text(
      'Size HLS bitrate se estimate hota hai (~). Download Dashboard → Downloads me dikhega.',
      style: TextStyle(color: Colors.grey, fontSize: 11),
    ));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids);
  }

  Widget _pill(IconData i, String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(i, size: 14, color: Colors.white60),
          const SizedBox(width: 5),
          Text(t, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _tag(String t, Color c) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.7), width: 0.8),
      ),
      child: Text(t, style: TextStyle(color: c, fontSize: 9.5, fontWeight: FontWeight.w800)),
    );
  }
}