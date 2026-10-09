import 'package:flutter/material.dart';

import 'config.dart';
import 'hero.dart';
import 'pages.dart';
import 'stores.dart';
import 'tmdb_service.dart';
import 'widgets.dart';

/// HANNUTV main dashboard.
///
/// Use:
///   HannuDashboard(hooks: DashboardHooks(
///     onOpenTitle: (ctx, item) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => YourPlayer(item))),
///     onOpenLiveTv: () => Navigator.push(context, ...LiveTvScreen),   // Live TV bilkul untouched
///   ))
class HannuDashboard extends StatefulWidget {
  const HannuDashboard({super.key, this.hooks = const DashboardHooks()});
  final DashboardHooks hooks;

  @override
  State<HannuDashboard> createState() => _HannuDashboardState();
}

class _HannuDashboardState extends State<HannuDashboard> {
  static const List<String> _tabs = <String>[
    'HANNU TRENDING',
    'Anime',
    'Movies',
    'Series',
    'Kids',
    'Live TV',
  ];

  final ScrollController _scroll = ScrollController();
  final ValueNotifier<Color> _ambient = ValueNotifier<Color>(HC.accent);
  late Future<List<TmdbItem>> _hero;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    Hooks.cfg = widget.hooks;
    WatchlistStore.I.load();
    ContinueWatchingStore.I.load();
    NotificationStore.I.init();
    _hero = Tmdb.I.heroItems();
  }

  @override
  void didUpdateWidget(covariant HannuDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    Hooks.cfg = widget.hooks;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    Tmdb.I.clearCache();
    final Future<List<TmdbItem>> f = Tmdb.I.heroItems();
    setState(() {
      _epoch++;
      _hero = f;
    });
    await f;
  }

  void _onTab(int i) {
    switch (i) {
      case 0:
        if (_scroll.hasClients) {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
        }
        break;
      case 1:
        openCategory(context, CategoryKind.anime);
        break;
      case 2:
        openCategory(context, CategoryKind.movies);
        break;
      case 3:
        openCategory(context, CategoryKind.series);
        break;
      case 4:
        openCategory(context, CategoryKind.kids);
        break;
      case 5:
        final VoidCallback? f = widget.hooks.onOpenLiveTv;
        if (f != null) {
          f();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Live TV: DashboardHooks.onOpenLiveTv me apni Live TV screen do.')),
          );
        }
        break;
    }
  }

  // ───────────────────────── build ─────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: hannuTheme(),
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Stack(
          children: <Widget>[
            _ambientBackground(),
            RefreshIndicator(
              color: HC.accent2,
              backgroundColor: HC.surface,
              onRefresh: _refresh,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                cacheExtent: 900,
                slivers: <Widget>[
                  SliverList(delegate: SliverChildListDelegate(_children())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _children() {
    final List<Widget> c = <Widget>[
      _header(),
      _tabsRow(),
      const SizedBox(height: 8),
      _heroSection(),
      const ContinueWatchingRow(),
      _ottSection(),
      PosterRow(
        key: ValueKey<String>('india$_epoch'),
        title: 'Top 10 in India',
        subtitle: 'India ke OTTs par abhi sabse zyada trending',
        ranked: true,
        width: 128,
        hideIfEmpty: false,
        loader: () => Tmdb.I.topIndia(),
      ),
      const AdSlot(),
      PosterRow(
        key: ValueKey<String>('world$_epoch'),
        title: 'Top 10 Worldwide',
        subtitle: 'Duniya bhar me trending',
        ranked: true,
        width: 128,
        hideIfEmpty: false,
        loader: () => Tmdb.I.topWorld(),
      ),
      _genreChips(),
    ];
    for (int i = 0; i < kDashGenres.length; i++) {
      final GenreDef g = kDashGenres[i];
      c.add(GenreBlock(
        key: ValueKey<String>('${g.key}$_epoch'),
        g: g,
        onSeeAll: () => openGenre(context, g),
      ));
      if (i == 2) c.add(const AdSlot());
    }
    c.add(const SizedBox(height: 40));
    return c;
  }

  // ───────────────────────── ambient background (poster ke hisaab se smooth color) ─────────────────────────
  Widget _ambientBackground() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 620,
      child: IgnorePointer(
        child: ValueListenableBuilder<Color>(
          valueListenable: _ambient,
          builder: (BuildContext _, Color target, Widget? __) {
            return TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: target),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeInOutCubic,
              builder: (BuildContext _, Color? v, Widget? __) {
                final Color col = v ?? target;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[alpha(col, 0.9), alpha(col, 0.35), HC.bg],
                      stops: const <double>[0.0, 0.5, 1.0],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ───────────────────────── header ─────────────────────────
  Widget _iconBtn(IconData icon, VoidCallback onTap, {int badge = 0}) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 26, color: Colors.white),
        ),
        if (badge > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: HC.accent2, borderRadius: BorderRadius.circular(9)),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _header() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  'assets/logo.png',
                  height: 34,
                  fit: BoxFit.contain,
                  errorBuilder: (BuildContext _, Object __, StackTrace? ___) => const Text(
                    'HANNUTV',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ),
              ),
            ),
            _iconBtn(Icons.search_rounded, () {
              final VoidCallback? f = widget.hooks.onOpenSearch;
              if (f != null) {
                f();
              } else {
                openSearch(context);
              }
            }),
            AnimatedBuilder(
              animation: WatchlistStore.I,
              builder: (BuildContext _, Widget? __) => _iconBtn(
                Icons.bookmark_border_rounded,
                () => openWatchlist(context),
                badge: WatchlistStore.I.length,
              ),
            ),
            AnimatedBuilder(
              animation: NotificationStore.I,
              builder: (BuildContext _, Widget? __) => _iconBtn(
                Icons.notifications_none_rounded,
                () => showNotifications(context),
                badge: NotificationStore.I.badge,
              ),
            ),
            // jaha pehle anime avatar tha → ab Support
            GestureDetector(
              onTap: () => showSupportSheet(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: HC.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.support_agent_rounded, size: 21, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabsRow() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: _tabs.length,
        separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 10),
        itemBuilder: (BuildContext _, int i) {
          final bool sel = i == 0; // dashboard hamesha HANNU TRENDING par hai
          return GestureDetector(
            onTap: () => _onTab(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: sel ? HC.primary : null,
                color: sel ? null : alpha(Colors.white, 0.06),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: sel ? Colors.transparent : Colors.white24),
              ),
              child: Text(
                _tabs[i],
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  color: sel ? Colors.white : Colors.white70,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────── hero ─────────────────────────
  Widget _heroSection() {
    return FutureBuilder<List<TmdbItem>>(
      future: _hero,
      builder: (BuildContext ctx, AsyncSnapshot<List<TmdbItem>> s) {
        if (s.connectionState != ConnectionState.done) return const HeroSkeleton();
        final List<TmdbItem> items = s.data ?? const <TmdbItem>[];
        if (items.isEmpty) return _heroError();
        return HeroCarousel(
          key: ValueKey<String>('hero$_epoch'),
          items: items,
          onColor: (Color c) => _ambient.value = c,
        );
      },
    );
  }

  Widget _heroError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: GestureDetector(
        onTap: _refresh,
        child: Container(
          height: 170,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: HC.surface, borderRadius: BorderRadius.circular(20)),
          child: Text(
            tmdbKeyMissing
                ? 'TMDB API key nahi mili.\nlib/dashboard/config.dart me paste karo.'
                : 'Trending load nahi hua.\nInternet check karo — tap karke retry karo.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: HC.dim, height: 1.5),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── OTT logos ─────────────────────────
  Widget _ottSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionTitle('Streaming on'),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: kOtts.length,
            separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 12),
            itemBuilder: (BuildContext _, int i) => GestureDetector(
              onTap: () => openOtt(context, kOtts[i]),
              child: OttLogo(kOtts[i], w: 96, h: 60),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ───────────────────────── genre chips ─────────────────────────
  Widget _genreChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionTitle('Genres'),
        SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: kAllGenres.length,
            separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 10),
            itemBuilder: (BuildContext _, int i) {
              final GenreDef g = kAllGenres[i];
              return GestureDetector(
                onTap: () => openGenre(context, g),
                child: Container(
                  width: 112,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[g.c1, g.c2],
                    ),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        right: -8,
                        bottom: -8,
                        child: Icon(g.icon, size: 52, color: alpha(Colors.white, 0.18)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            g.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
