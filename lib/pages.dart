import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'stores.dart';
import 'tmdb_service.dart';
import 'widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.children, this.lead, this.tint = HC.accent});
  final String title;
  final Widget? lead;
  final Color tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HC.bg,
      body: Stack(
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[alpha(tint, 0.55), HC.bg],
                ),
              ),
            ),
          ),
          CustomScrollView(
            cacheExtent: 800,
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                backgroundColor: alpha(HC.bg, 0.92),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                titleSpacing: 0,
                title: Row(
                  children: <Widget>[
                    if (lead != null) ...<Widget>[lead!, const SizedBox(width: 10)],
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  const SizedBox(height: 8),
                  ...children,
                  const SizedBox(height: 40),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _push(BuildContext c, Widget page, {bool dialog = false}) =>
    Navigator.of(c).push(MaterialPageRoute<void>(
      builder: (_) => Theme(data: hannuTheme(), child: page),
      fullscreenDialog: dialog,
    ));

void openGenre(BuildContext c, GenreDef g) => _push(c, GenrePage(g: g), dialog: true);
void openOtt(BuildContext c, Ott o) => _push(c, OttPage(ott: o));
void openCategory(BuildContext c, CategoryKind k) => _push(c, CategoryPage(kind: k), dialog: true);
void openWatchlist(BuildContext c) => _push(c, const WatchlistPage());
void openSearch(BuildContext c) => _push(c, const SearchPage());

class GenrePage extends StatelessWidget {
  const GenrePage({super.key, required this.g});
  final GenreDef g;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: g.label,
      tint: g.c1,
      lead: Icon(g.icon, color: Colors.white),
      children: <Widget>[
        PosterRow(
          title: 'Movies',
          subtitle: 'Top 50 ${g.label}',
          width: 118,
          hideIfEmpty: false,
          loader: () => Tmdb.I.genreRow(g, RowKind.movie),
        ),
        PosterRow(
          title: 'Web Series',
          subtitle: 'Top 50 ${g.label}',
          width: 118,
          loader: () => Tmdb.I.genreRow(g, RowKind.series),
        ),
        PosterRow(
          title: 'Anime',
          subtitle: 'Top 50 ${g.label}',
          width: 118,
          loader: () => Tmdb.I.genreRow(g, RowKind.anime),
        ),
        if (g.hasKdrama)
          PosterRow(
            title: 'K-Drama',
            subtitle: 'Top 50 Korean drama',
            width: 118,
            loader: () => Tmdb.I.genreRow(g, RowKind.kdrama),
          ),
      ],
    );
  }
}

enum CategoryKind { anime, movies, series, kids }

class CategoryPage extends StatelessWidget {
  const CategoryPage({super.key, required this.kind});
  final CategoryKind kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case CategoryKind.anime:
        return _Shell(
          title: 'Anime',
          tint: const Color(0xFF6D28D9),
          children: <Widget>[
            PosterRow(
              title: 'Trending Anime',
              width: 118,
              hideIfEmpty: false,
              loader: () => Tmdb.I.discover(tv: true, genres: '16', lang: 'ja', count: 30),
            ),
            PosterRow(
              title: 'Top Rated Anime',
              width: 118,
              loader: () => Tmdb.I.discover(
                  tv: true, genres: '16', lang: 'ja', sort: 'vote_average.desc', count: 30),
            ),
            PosterRow(
              title: 'Anime Movies',
              width: 118,
              loader: () => Tmdb.I.discover(tv: false, genres: '16', lang: 'ja', count: 30),
            ),
            for (final GenreDef g in kAllGenres)
              PosterRow(
                title: '${g.label} Anime',
                width: 118,
                loader: () => Tmdb.I.genreRow(g, RowKind.anime),
              ),
          ],
        );
      case CategoryKind.movies:
        return _Shell(
          title: 'Movies',
          tint: const Color(0xFFB91C1C),
          children: <Widget>[
            PosterRow(
              title: 'Trending Movies',
              width: 118,
              hideIfEmpty: false,
              loader: () => Tmdb.I.list('/trending/movie/week', <String, String>{}, count: 30, tv: false),
            ),
            PosterRow(
              title: 'Top Rated',
              width: 118,
              loader: () => Tmdb.I.list('/movie/top_rated', <String, String>{}, count: 30, tv: false),
            ),
            PosterRow(
              title: 'Hollywood',
              width: 118,
              loader: () => Tmdb.I.discover(tv: false, lang: 'en', count: 30),
            ),
            PosterRow(
              title: 'Bollywood',
              width: 118,
              loader: () => Tmdb.I.discover(tv: false, lang: 'hi', count: 30),
            ),
            for (final GenreDef g in kAllGenres)
              PosterRow(
                title: '${g.label} Movies',
                width: 118,
                loader: () => Tmdb.I.genreRow(g, RowKind.movie),
              ),
          ],
        );
      case CategoryKind.series:
        return _Shell(
          title: 'Web Series',
          tint: const Color(0xFF0369A1),
          children: <Widget>[
            PosterRow(
              title: 'Trending Series',
              width: 118,
              hideIfEmpty: false,
              loader: () => Tmdb.I.list('/trending/tv/week', <String, String>{}, count: 30, tv: true),
            ),
            for (final Ott o in kOtts)
              PosterRow(
                title: 'Top 10 on ${o.name}',
                leading: OttLogo(o, w: 46, h: 32, radius: 8),
                ranked: true,
                width: 124,
                loader: () => Tmdb.I.ottRow(o, tvOnly: true, count: 10),
              ),
            for (final GenreDef g in kAllGenres)
              PosterRow(
                title: '${g.label} Series',
                width: 118,
                loader: () => Tmdb.I.genreRow(g, RowKind.series),
              ),
          ],
        );
      case CategoryKind.kids:
        return _Shell(
          title: 'Kids',
          tint: const Color(0xFF16A34A),
          children: <Widget>[
            PosterRow(
              title: 'Kids Movies',
              width: 118,
              hideIfEmpty: false,
              loader: () => Tmdb.I.discover(
                tv: false,
                genres: '16|10751',
                count: 30,
                extra: <String, String>{'certification_country': 'US', 'certification.lte': 'PG'},
              ),
            ),
            PosterRow(
              title: 'Kids Shows',
              width: 118,
              loader: () => Tmdb.I.discover(tv: true, genres: '10762', count: 30),
            ),
            PosterRow(
              title: 'Family Series',
              width: 118,
              loader: () => Tmdb.I.discover(tv: true, genres: '10751', count: 30),
            ),
          ],
        );
    }
  }
}

class OttPage extends StatelessWidget {
  const OttPage({super.key, required this.ott});
  final Ott ott;

  @override
  Widget build(BuildContext context) {
    final Ott o = ott;
    return _Shell(
      title: o.name,
      lead: OttLogo(o, w: 56, h: 36, radius: 10),
      children: <Widget>[
        PosterRow(
          title: 'Top 10 on ${o.name}',
          ranked: true,
          width: 128,
          hideIfEmpty: false,
          loader: () => Tmdb.I.ottRow(o, count: 10),
        ),
        PosterRow(
          title: 'Top 10 Web Series',
          ranked: true,
          width: 124,
          loader: () => Tmdb.I.ottRow(o, tvOnly: true, count: 10),
        ),
        PosterRow(
          title: 'Top 10 Movies',
          ranked: true,
          width: 124,
          loader: () => Tmdb.I.ottRow(o, movieOnly: true, count: 10),
        ),
        PosterRow(title: 'Hollywood', loader: () => Tmdb.I.ottRow(o, lang: 'en', count: 30)),
        PosterRow(title: 'Bollywood', loader: () => Tmdb.I.ottRow(o, lang: 'hi', count: 30)),
        PosterRow(title: 'K-Drama', loader: () => Tmdb.I.ottRow(o, kdrama: true, count: 30)),
        PosterRow(title: 'Anime', loader: () => Tmdb.I.ottRow(o, animeOnly: true, count: 30)),
        for (final GenreDef g in kAllGenres)
          PosterRow(title: g.label, loader: () => Tmdb.I.ottRow(o, genre: g, count: 30)),
        _MatureGate(ott: o),
      ],
    );
  }
}

// 🔥 YAHAN POPUP TEXT PURI TARAH ENGLISH MEIN KAR DIYA HAI 🔥
class _MatureGate extends StatefulWidget {
  const _MatureGate({required this.ott});
  final Ott ott;
  @override
  State<_MatureGate> createState() => _MatureGateState();
}

class _MatureGateState extends State<_MatureGate> {
  bool _ok = false;

  @override
  Widget build(BuildContext context) {
    if (_ok) {
      return PosterRow(
        title: '18+ Mature',
        subtitle: 'R / A-rated movies',
        loader: () => Tmdb.I.ottRow(widget.ott, mature: true, count: 30),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HC.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.lock_outline_rounded, color: HC.dim),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('18+ Mature category', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            GestureDetector(
              onTap: () async {
                final bool? yes = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext c) => AlertDialog(
                    backgroundColor: HC.surface,
                    title: const Text('Age check'),
                    content: const Text('Are you 18 years of age or older?'),
                    actions: <Widget>[
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, 18+')),
                    ],
                  ),
                );
                if (yes == true && mounted) setState(() => _ok = true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(gradient: HC.primary, borderRadius: BorderRadius.circular(10)),
                child: const Text('Unlock', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WatchlistPage extends StatelessWidget {
  const WatchlistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HC.bg,
      appBar: AppBar(
        backgroundColor: HC.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('My Watchlist', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: AnimatedBuilder(
        animation: WatchlistStore.I,
        builder: (BuildContext ctx, Widget? _) {
          final List<TmdbItem> items = WatchlistStore.I.items;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Watchlist is empty.\nTap "My List" on any movie/series.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HC.dim, height: 1.5),
                ),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.52,
            ),
            itemCount: items.length,
            itemBuilder: (BuildContext _, int i) {
              final TmdbItem it = items[i];
              return LayoutBuilder(
                builder: (BuildContext _, BoxConstraints c) => Stack(
                  children: <Widget>[
                    PosterCard(item: it, width: c.maxWidth),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => WatchlistStore.I.toggle(it),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: alpha(Colors.black, 0.7), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _c = TextEditingController();
  Timer? _deb;
  List<TmdbItem> _res = const <TmdbItem>[];
  bool _busy = false;
  int _seq = 0;

  void _onChanged(String q) {
    _deb?.cancel();
    final String t = q.trim();
    if (t.length < 2) {
      _seq++; 
      setState(() {
        _res = const <TmdbItem>[];
        _busy = false;
      });
      return;
    }
    _deb = Timer(const Duration(milliseconds: 400), () async {
      final int my = ++_seq;
      setState(() => _busy = true);
      final List<TmdbItem> r = await Tmdb.I.search(t);
      if (!mounted || my != _seq) return; 
      setState(() {
        _res = r;
        _busy = false;
      });
    });
  }

  @override
  void dispose() {
    _deb?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HC.bg,
      appBar: AppBar(
        backgroundColor: HC.bg,
        surfaceTintColor: Colors.transparent,
        title: TextField(
          controller: _c,
          autofocus: true,
          onChanged: _onChanged,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search movies, series, anime...',
            hintStyle: TextStyle(color: HC.dim),
            border: InputBorder.none,
          ),
        ),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : (_res.isEmpty
              ? const Center(child: Text('Type to search', style: TextStyle(color: HC.dim)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.52,
                  ),
                  itemCount: _res.length,
                  itemBuilder: (BuildContext _, int i) => LayoutBuilder(
                    builder: (BuildContext _, BoxConstraints c) =>
                        PosterCard(item: _res[i], width: c.maxWidth),
                  ),
                )),
    );
  }
}

String _ago(int ts) {
  final Duration d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} mins ago';
  return '${d.inHours} hours ago';
}

void showNotifications(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: HC.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (BuildContext sheetCtx) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75),
        child: AnimatedBuilder(
          animation: NotificationStore.I,
          builder: (BuildContext _, Widget? __) {
            final NotificationStore s = NotificationStore.I;
            final List<AppNotification> list = s.active;
            final UpdateInfo? u = s.update;
            final List<Widget> tiles = <Widget>[
              if (u != null)
                _SheetTile(
                  icon: Icons.system_update_rounded,
                  color: HC.accent2,
                  title: 'Update your app',
                  sub: 'New version v${u.version} is available. Tap to update.',
                  onTap: () => openUrl(u.url),
                ),
              for (final AppNotification n in list)
                _SheetTile(
                  icon: Icons.notifications_active_rounded,
                  color: HC.gold,
                  title: n.title,
                  sub: n.body.isEmpty ? _ago(n.ts) : '${n.body}\n${_ago(n.ts)}',
                  onTap: n.url == null ? null : () => openUrl(n.url!),
                  imageUrl: n.imageUrl, // 🔥 IMAGE SUPPORT ADDED HERE 🔥
                ),
            ];
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                    child: Text('Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  // 🔥 NOTIFICATION TEXT ENGLISH MEIN 🔥
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Text('Notifications are kept for 24 hours',
                        style: TextStyle(color: HC.dim, fontSize: 12)),
                  ),
                  if (tiles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 40),
                      child: Text('No new notifications.', style: TextStyle(color: HC.dim)),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        children: tiles,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

// 🔥 _SheetTile MEIN IMAGE SUPPORT ADD KIYA GAYA HAI 🔥
class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.icon, required this.color, required this.title, required this.sub, this.onTap, this.imageUrl});
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback? onTap;
  final String? imageUrl; 

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: HC.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl!,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(color: alpha(color, 0.18), borderRadius: BorderRadius.circular(8)),
                        child: Icon(icon, color: color, size: 20),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: alpha(color, 0.18), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 20),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(sub, style: const TextStyle(color: HC.dim, fontSize: 12.5, height: 1.35)),
                    ],
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right_rounded, color: HC.dim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void showSupportSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: HC.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (BuildContext _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text('Support', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text('Join us for support and updates', style: TextStyle(color: HC.dim, fontSize: 12)),
            ),
            _SheetTile(
              icon: Icons.send_rounded,
              color: const Color(0xFF229ED9),
              title: 'Telegram',
              sub: 'Support & new releases',
              onTap: () => openUrl(kTelegramUrl),
            ),
            _SheetTile(
              icon: Icons.chat_rounded,
              color: const Color(0xFF25D366),
              title: 'WhatsApp Channel',
              sub: 'Latest updates directly on WhatsApp',
              onTap: () => openUrl(kWhatsappChannelUrl),
            ),
            const SizedBox(height: 6),
            Center(
              child: FutureBuilder<String>(
                future: appVersion(),
                builder: (BuildContext _, AsyncSnapshot<String> s) => Text(
                  'HANNUTV v${s.data ?? kVersionFallback}',
                  style: const TextStyle(color: HC.dim, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}