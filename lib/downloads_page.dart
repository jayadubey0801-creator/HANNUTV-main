// ═══════════════════════════════════════════════════════════════════════════
//  HANNUTV  •  downloads_page.dart  (v1.4.0)
//
//  Dashboard ke header me jo Download icon hai (search / watchlist ke bagal me)
//  wo yahi page kholta hai:
//    • chal rahe downloads (progress, speed, pause / resume)
//    • complete movies  →  tap karo → seedha in-app OFFLINE player (net band ho tab bhi)
//    • "Open with" → VLC / MX Player / koi bhi player
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'config.dart';
import 'download_manager.dart';
import 'download_sheet.dart';
import 'tmdb_service.dart';
import 'widgets.dart';

TmdbItem _itemOf(DlJob j) => TmdbItem.fromStored(<String, dynamic>{
      'id': j.tmdbId,
      'is_tv': j.isTv,
      'title': j.title,
      'name': j.title,
      'release_date': j.year,
      'first_air_date': j.year,
      'vote_average': 0.0,
      'overview': '',
      'poster_path': j.posterPath.isEmpty ? null : j.posterPath,
    });

Future<void> openWithExternalPlayer(BuildContext context, DlJob j) async {
  try {
    final String low = j.filePath.toLowerCase();
    final OpenResult r = await OpenFilex.open(
      j.filePath,
      type: low.endsWith('.mkv') ? 'video/x-matroska' : 'video/mp4',
    );
    if (r.type != ResultType.done && context.mounted) {
      final String msg = r.type == ResultType.noAppToOpen
          ? 'No video player found. Install VLC or MX Player.'
          : (r.type == ResultType.fileNotFound ? 'File not found on the phone.' : 'Could not open the player: ${r.message}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the player: $e')));
    }
  }
}

// ───────────────────────────── Downloads page ─────────────────────────────

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  @override
  void initState() {
    super.initState();
    DownloadStore.I.load();
  }

  List<DlJob> _sorted() {
    final List<DlJob> l = List<DlJob>.of(DownloadStore.I.jobs);
    int rank(DlJob j) {
      if (j.isActive) return 0;
      if (j.state == DlState.paused || j.state == DlState.failed) return 1;
      return 2;
    }

    l.sort((DlJob a, DlJob b) {
      final int r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return b.createdAt.compareTo(a.createdAt);
    });
    return l;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HC.bg,
      appBar: AppBar(
        backgroundColor: HC.bg,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Downloads', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
      ),
      body: AnimatedBuilder(
        animation: DownloadStore.I,
        builder: (BuildContext ctx, Widget? _) {
          final List<DlJob> jobs = _sorted();
          if (jobs.isEmpty) return _empty();
          int total = 0;
          int n = 0;
          for (final DlJob j in jobs) {
            if (j.state == DlState.done) {
              total += j.fileBytes;
              n++;
            }
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            itemCount: jobs.length + 1,
            separatorBuilder: (BuildContext _, int __) => const SizedBox(height: 12),
            itemBuilder: (BuildContext _, int i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.offline_pin_rounded, color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          n == 0
                              ? 'Plays from here even without internet'
                              : 'Offline library  •  $n video${n == 1 ? '' : 's'}  •  ${dlBytes(total)}',
                          style: const TextStyle(color: HC.dim, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _DlTile(job: jobs[i - 1]);
            },
          );
        },
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.download_for_offline_rounded, size: 90, color: Colors.redAccent.withOpacity(0.85)),
            const SizedBox(height: 20),
            const Text('No downloads yet',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text(
              'Kisi bhi movie / episode ke player me "Download" dabao.\nChoose quality and language, download, then watch offline from here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _DlTile extends StatelessWidget {
  const _DlTile({required this.job});
  final DlJob job;

  String _status() {
    final int pct = (job.progress * 100).clamp(0, 100).round();
    switch (job.state) {
      case DlState.queued:
        return 'Queued…';
      case DlState.downloading:
        if (job.stage.isNotEmpty) return job.stage;
        final StringBuffer sb = StringBuffer('$pct%');
        if (job.kind == 'hls' && job.estBytes > 0) {
          sb.write('  •  ${dlBytes(job.bytesDone)} / ~${dlBytes(job.estBytes)}');
        } else if (job.bytesDone > 0) {
          sb.write('  •  ${dlBytes(job.bytesDone)}');
        }
        if (job.speedBps > 0) {
          sb.write('  •  ${dlBytes(job.speedBps)}/s');
          if (job.estBytes > job.bytesDone) {
            final String eta = dlEta((job.estBytes - job.bytesDone) / job.speedBps);
            if (eta.isNotEmpty) sb.write('  •  $eta');
          }
        }
        return sb.toString();
      case DlState.merging:
        return '${job.stage.isEmpty ? 'Converting…' : job.stage}  $pct%';
      case DlState.paused:
        return 'Paused  •  $pct%';
      case DlState.failed:
        return job.error.isEmpty ? 'Download failed' : job.error;
      case DlState.done:
        final String g = job.galleryDone ? '  •  Also saved in Movies/HANNUTV' : '';
        final String st = job.stage.isNotEmpty ? '  •  ${job.stage}' : '';
        return '${dlBytes(job.fileBytes)}  •  Offline ready$g$st';
    }
  }

  Color _statusColor() {
    switch (job.state) {
      case DlState.failed:
        return Colors.redAccent;
      case DlState.done:
        return Colors.greenAccent;
      case DlState.paused:
        return Colors.orangeAccent;
      default:
        return Colors.white70;
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: HC.surface,
        title: const Text('Delete download?', style: TextStyle(color: Colors.white)),
        content: Text(
          job.state == DlState.done
              ? '"${job.title}" will be removed from the phone.'
              : 'This download will be cancelled and partial files will be removed.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) await DownloadStore.I.remove(job.id);
  }

  void _play(BuildContext context) {
    if (job.state != DlState.done) return;
    if (!File(job.filePath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File phone se delete ho chuki hai.')));
      return;
    }
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => OfflinePlayerPage(job: job)));
  }

  @override
  Widget build(BuildContext context) {
    final bool active = job.state == DlState.downloading || job.state == DlState.merging;
    final String meta = <String>[
      if (job.isTv) job.epLabel,
      job.qualityLabel,
      job.langLabel,
    ].where((String s) => s.isNotEmpty).join('  •  ');

    Widget action;
    switch (job.state) {
      case DlState.done:
        action = IconButton(
          tooltip: 'Play',
          icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.redAccent, size: 34),
          onPressed: () => _play(context),
        );
        break;
      case DlState.downloading:
      case DlState.queued:
        action = IconButton(
          tooltip: 'Pause',
          icon: const Icon(Icons.pause_circle_filled_rounded, color: Colors.white70, size: 32),
          onPressed: () => DownloadStore.I.pause(job.id),
        );
        break;
      case DlState.merging:
        action = const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.redAccent)),
        );
        break;
      case DlState.paused:
      case DlState.failed:
        action = IconButton(
          tooltip: job.state == DlState.paused ? 'Resume' : 'Retry',
          icon: Icon(job.state == DlState.paused ? Icons.play_circle_outline_rounded : Icons.refresh_rounded,
              color: Colors.orangeAccent, size: 32),
          onPressed: () => DownloadStore.I.resume(job.id),
        );
        break;
    }

    return Material(
      color: HC.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: job.state == DlState.done ? () => _play(context) : null,
        onLongPress: () => _confirmDelete(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              PosterImage(item: _itemOf(job), width: 58, size: 'w185'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(job.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: HC.dim, fontSize: 11.5)),
                    const SizedBox(height: 6),
                    if (job.state != DlState.done && job.state != DlState.failed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: job.state == DlState.queued ? null : job.progress.clamp(0.0, 1.0).toDouble(),
                            minHeight: 4,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(active ? Colors.redAccent : Colors.orangeAccent),
                          ),
                        ),
                      ),
                    Text(_status(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _statusColor(), fontSize: 11.5, height: 1.3)),
                  ],
                ),
              ),
              action,
              PopupMenuButton<String>(
                color: HC.surface,
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
                onSelected: (String v) async {
                  if (v == 'play') _play(context);
                  if (v == 'ext') await openWithExternalPlayer(context, job);
                  if (v == 'del') await _confirmDelete(context);
                  if (v == 'rescan') {
                    await showDownloadSheet(
                      context,
                      tmdbId: job.tmdbId,
                      mediaType: job.isTv ? 'tv' : 'movie',
                      season: job.season,
                      episode: job.episode,
                      title: job.title,
                      year: job.year,
                      posterPath: job.posterPath,
                      replaceJobId: job.id,
                    );
                  }
                },
                itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                  if (job.state == DlState.done)
                    const PopupMenuItem<String>(value: 'play', child: Text('Play (in-app)', style: TextStyle(color: Colors.white))),
                  if (job.state == DlState.done)
                    const PopupMenuItem<String>(
                        value: 'ext', child: Text('Open with VLC / MX Player…', style: TextStyle(color: Colors.white))),
                  if (job.state == DlState.failed)
                    const PopupMenuItem<String>(
                        value: 'rescan', child: Text('Get new link (re-scan)', style: TextStyle(color: Colors.white))),
                  const PopupMenuItem<String>(value: 'del', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Offline player ─────────────────────────────

class OfflinePlayerPage extends StatefulWidget {
  const OfflinePlayerPage({super.key, required this.job});
  final DlJob job;

  @override
  State<OfflinePlayerPage> createState() => _OfflinePlayerPageState();
}

class _OfflinePlayerPageState extends State<OfflinePlayerPage> {
  VideoPlayerController? _c;
  String? _err;
  bool _controls = true;
  bool _land = false;
  bool _dragging = false;
  double _dragMs = 0;
  Timer? _hide;
  Timer? _savePos;
  Offset _lastTap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _init();
    _savePos = Timer.periodic(const Duration(seconds: 5), (Timer _) => _persist());
  }

  void _persist() {
    final VideoPlayerController? c = _c;
    if (c == null || !c.value.isInitialized) return;
    DownloadStore.I.savePosition(widget.job.id, c.value.position.inMilliseconds);
  }

  Future<void> _init() async {
    final File f = File(widget.job.filePath);
    if (!f.existsSync()) {
      _err = 'Movie file not found on the phone (it may have been deleted).';
      return;
    }
    final VideoPlayerController c = VideoPlayerController.file(f);
    _c = c;
    try {
      await c.initialize();
      if (!mounted) return;
      final int dur = c.value.duration.inMilliseconds;
      final int pos = widget.job.positionMs;
      if (pos > 8000 && dur > 0 && pos < dur - 15000) {
        await c.seekTo(Duration(milliseconds: pos));
      }
      c.addListener(_onValue);
      await c.play();
      WakelockPlus.enable();
      if (mounted) setState(() {});
      _showControls();
    } catch (e) {
      if (mounted) setState(() => _err = 'The in-app player could not play this file.\n$e');
    }
  }

  void _onValue() {
    final VideoPlayerController? c = _c;
    if (c == null || !mounted) return;
    if (c.value.hasError && _err == null) {
      setState(() => _err = c.value.errorDescription ?? 'Playback error');
    }
  }

  void _showControls() {
    _hide?.cancel();
    if (!_controls && mounted) setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && (_c?.value.isPlaying ?? false) && !_dragging) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    if (_controls) {
      _hide?.cancel();
      setState(() => _controls = false);
    } else {
      _showControls();
    }
  }

  void _seekBy(int sec) {
    final VideoPlayerController? c = _c;
    if (c == null || !c.value.isInitialized) return;
    final int dur = c.value.duration.inMilliseconds;
    int t = c.value.position.inMilliseconds + sec * 1000;
    if (t < 0) t = 0;
    if (t > dur) t = dur;
    c.seekTo(Duration(milliseconds: t));
    _showControls();
  }

  void _togglePlay() {
    final VideoPlayerController? c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    _showControls();
  }

  void _toggleLand() {
    setState(() => _land = !_land);
    if (_land) {
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _showControls();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _savePos?.cancel();
    _persist();
    final VideoPlayerController? c = _c;
    c?.removeListener(_onValue);
    c?.dispose();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  String _fmt(double ms) {
    final int s = (ms / 1000).round();
    final int h = s ~/ 3600;
    final int m = (s % 3600) ~/ 60;
    final int sec = s % 60;
    final String mm = m.toString().padLeft(2, '0');
    final String ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final DlJob j = widget.job;
    final VideoPlayerController? c = _c;
    if (_err != null) return _errorView();

    return Scaffold(
      backgroundColor: Colors.black,
      body: (c == null || !c.value.isInitialized)
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (TapDownDetails d) => _lastTap = d.localPosition,
              onDoubleTap: () {
                final double w = MediaQuery.of(context).size.width;
                _seekBy(_lastTap.dx < w / 2 ? -10 : 10);
              },
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                  ),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (BuildContext _, VideoPlayerValue v, Widget? __) => v.isBuffering
                        ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                        : const SizedBox.shrink(),
                  ),
                  AnimatedOpacity(
                    opacity: _controls ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controls,
                      child: _overlay(c, j),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _overlay(VideoPlayerController c, DlJob j) {
    return Container(
      color: Colors.black45,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    j.isTv ? '${j.title}  •  ${j.epLabel}' : j.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                IconButton(
                  tooltip: 'Open in VLC / MX Player',
                  icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                  onPressed: () async {
                    c.pause();
                    await openWithExternalPlayer(context, j);
                  },
                ),
              ],
            ),
            const Spacer(),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (BuildContext _, VideoPlayerValue v, Widget? __) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                      onPressed: () => _seekBy(-10),
                    ),
                    const SizedBox(width: 18),
                    IconButton(
                      iconSize: 64,
                      icon: Icon(v.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                          color: Colors.white),
                      onPressed: _togglePlay,
                    ),
                    const SizedBox(width: 18),
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                      onPressed: () => _seekBy(10),
                    ),
                  ],
                );
              },
            ),
            const Spacer(),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (BuildContext _, VideoPlayerValue v, Widget? __) {
                final double dur = v.duration.inMilliseconds.toDouble();
                final double max = dur <= 0 ? 1 : dur;
                final double pos = (_dragging ? _dragMs : v.position.inMilliseconds.toDouble())
                    .clamp(0.0, max)
                    .toDouble();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 6, 8),
                  child: Row(
                    children: <Widget>[
                      Text(_fmt(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: pos,
                          max: max,
                          activeColor: Colors.redAccent,
                          inactiveColor: Colors.white24,
                          onChangeStart: (double x) => setState(() {
                            _dragging = true;
                            _dragMs = x;
                          }),
                          onChanged: (double x) => setState(() => _dragMs = x),
                          onChangeEnd: (double x) {
                            c.seekTo(Duration(milliseconds: x.round()));
                            setState(() => _dragging = false);
                            _showControls();
                          },
                        ),
                      ),
                      Text(_fmt(dur), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      IconButton(
                        icon: Icon(_land ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                        onPressed: _toggleLand,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    final DlJob j = widget.job;
    return Scaffold(
      backgroundColor: HC.bg,
      appBar: AppBar(backgroundColor: HC.bg, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.movie_filter_rounded, color: Colors.orangeAccent, size: 70),
              const SizedBox(height: 18),
              Text(_err ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => openWithExternalPlayer(context, j),
                icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                label: const Text('Open in VLC / MX Player',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
