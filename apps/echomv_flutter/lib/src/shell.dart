import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_controller.dart';
import 'models.dart';
import 'visualizer.dart';

class EchoShell extends ConsumerStatefulWidget {
  const EchoShell({super.key});

  @override
  ConsumerState<EchoShell> createState() => _EchoShellState();
}

class _EchoShellState extends ConsumerState<EchoShell> {
  var _mobileIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 860;
    final state = ref.watch(echoControllerProvider);
    final controller = ref.read(echoControllerProvider.notifier);

    if (isCompact) {
      final pages = [
        SearchPane(state: state, controller: controller, compact: true),
        NowPlayingPane(state: state, controller: controller, compact: true),
        LibraryPane(state: state, controller: controller, compact: true),
      ];
      return Scaffold(
        body: SafeArea(child: pages[_mobileIndex]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _mobileIndex,
          onDestinationSelected: (index) =>
              setState(() => _mobileIndex = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.explore), label: '发现'),
            NavigationDestination(icon: Icon(Icons.graphic_eq), label: '播放'),
            NavigationDestination(icon: Icon(Icons.library_music), label: '曲库'),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Sidebar(state: state, controller: controller),
            Expanded(
              flex: 7,
              child: state.selectedCollectionView == CollectionView.discover
                  ? SearchPane(state: state, controller: controller)
                  : LibraryPane(state: state, controller: controller),
            ),
            Expanded(
              flex: 5,
              child: NowPlayingPane(state: state, controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.state,
    required this.controller,
  });

  final EchoState state;
  final EchoController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 224,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.equalizer, color: Colors.black),
              ),
              const SizedBox(width: 12),
              const Text(
                'EchoMV',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _NavItem(
            icon: Icons.explore,
            label: '发现',
            active: state.selectedCollectionView == CollectionView.discover,
            onTap: () =>
                controller.selectCollectionView(CollectionView.discover),
          ),
          _NavItem(
            icon: Icons.queue_music,
            label: '我的歌单',
            active: state.selectedCollectionView == CollectionView.playlists,
            onTap: () =>
                controller.selectCollectionView(CollectionView.playlists),
          ),
          _NavItem(
            icon: Icons.history,
            label: '最近播放',
            active: state.selectedCollectionView == CollectionView.history,
            onTap: () =>
                controller.selectCollectionView(CollectionView.history),
          ),
          _NavItem(
            icon: Icons.favorite,
            label: '收藏',
            active: state.selectedCollectionView == CollectionView.favorites,
            onTap: () =>
                controller.selectCollectionView(CollectionView.favorites),
          ),
          const Spacer(),
          Text('最近播放', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          ...state.history.take(4).map(
                (item) =>
                    _MiniTrack(item: item, onTap: () => controller.play(item)),
              ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 44,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20, color: active ? colors.primary : Colors.white70),
            const SizedBox(width: 12),
            Text(label,
                style:
                    TextStyle(color: active ? colors.primary : Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class SearchPane extends StatefulWidget {
  const SearchPane({
    super.key,
    required this.state,
    required this.controller,
    this.compact = false,
  });

  final EchoState state;
  final EchoController controller;
  final bool compact;

  @override
  State<SearchPane> createState() => _SearchPaneState();
}

class _SearchPaneState extends State<SearchPane> {
  final _searchController = TextEditingController(text: '晴天');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.compact ? 16.0 : 26.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: widget.controller.search,
            decoration: InputDecoration(
              hintText: '搜索歌曲、歌手或歌词',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: '搜索',
                icon: widget.state.isSearching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                onPressed: () =>
                    widget.controller.search(_searchController.text),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('搜索结果', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: 12),
              if (widget.state.query.isNotEmpty)
                Chip(
                    label: Text(widget.state.query),
                    visualDensity: VisualDensity.compact),
            ],
          ),
          if (widget.state.error != null) ...[
            const SizedBox(height: 10),
            Text(widget.state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: widget.state.results.isEmpty
                ? EmptySearch(
                    onSearch: () =>
                        widget.controller.search(_searchController.text))
                : ListView.separated(
                    itemCount: widget.state.results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = widget.state.results[index];
                      return SearchResultCard(
                        item: item,
                        selected: widget.state.current?.id == item.id,
                        onPlay: () => widget.controller.play(item),
                        onAddToPlaylist: () => _showAddToPlaylistSheet(
                          context,
                          widget.controller,
                          widget.state.playlists,
                          item,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class EmptySearch extends StatelessWidget {
  const EmptySearch({super.key, required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined, size: 56, color: colors.primary),
          const SizedBox(height: 16),
          const Text('输入歌曲名称开始搜索'),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.play_arrow),
            label: const Text('搜索 晴天'),
          ),
        ],
      ),
    );
  }
}

class SearchResultCard extends StatelessWidget {
  const SearchResultCard({
    super.key,
    required this.item,
    required this.selected,
    required this.onPlay,
    required this.onAddToPlaylist,
  });

  final SearchResult item;
  final bool selected;
  final VoidCallback onPlay;
  final VoidCallback onAddToPlaylist;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 116,
                  height: 68,
                  color: Colors.black26,
                  child: item.thumbnailUrl == null
                      ? const Icon(Icons.music_video)
                      : Image.network(
                          item.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.music_video),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (item.artist != null) item.artist!,
                        item.source,
                        if (item.duration != null)
                          _formatDuration(item.duration!),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: item.confidence.clamp(0, 1),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: '添加到歌单',
                onPressed: onAddToPlaylist,
                icon: const Icon(Icons.playlist_add),
              ),
              FilledButton.icon(
                onPressed: onPlay,
                icon: Icon(selected ? Icons.graphic_eq : Icons.play_arrow),
                label: const Text('播放'),
                style: FilledButton.styleFrom(
                  backgroundColor: selected ? colors.tertiary : colors.primary,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NowPlayingPane extends StatelessWidget {
  const NowPlayingPane({
    super.key,
    required this.state,
    required this.controller,
    this.compact = false,
  });

  final EchoState state;
  final EchoController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding:
          EdgeInsets.fromLTRB(compact ? 16 : 22, 20, compact ? 16 : 22, 12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: compact ? 0 : 0.44),
        border: compact
            ? null
            : Border(
                left: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('正在播放', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: '添加到歌单',
                onPressed: state.current == null
                    ? null
                    : () => _showAddToPlaylistSheet(
                          context,
                          controller,
                          state.playlists,
                          state.current!,
                        ),
                icon: const Icon(Icons.playlist_add),
              ),
              IconButton(
                tooltip: '收藏',
                onPressed:
                    state.current == null ? null : controller.toggleFavorite,
                icon: Icon(state.isCurrentFavorite
                    ? Icons.favorite
                    : Icons.favorite_border),
                color:
                    state.isCurrentFavorite ? colors.secondary : Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: state.current == null
                ? const Center(child: Text('选择一个 MV 开始播放'))
                : ListView(
                    children: [
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AudioVisualizer(
                              isPlaying: state.isPlaying,
                              position: state.position,
                              duration: state.duration,
                              peaks: state.media?.waveformPeaks,
                            ),
                            _CoverArt(
                              item: state.current!,
                              isPlaying: state.isPlaying,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        state.current!.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.current!.artist ?? state.current!.source,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 18),
                      LyricPanel(state: state, controller: controller),
                    ],
                  ),
          ),
          PlayerControls(state: state, controller: controller),
        ],
      ),
    );
  }
}

class _CoverArt extends StatefulWidget {
  const _CoverArt({
    required this.item,
    required this.isPlaying,
  });

  final SearchResult item;
  final bool isPlaying;

  @override
  State<_CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<_CoverArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant _CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _rotationController.value = 0;
    }
    _syncPlayback();
  }

  void _syncPlayback() {
    if (widget.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      key: const ValueKey('cover-rotation'),
      turns: _rotationController,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(71),
        child: Container(
          width: 142,
          height: 142,
          color: const Color(0xFF252B30),
          child: widget.item.thumbnailUrl == null
              ? const Icon(Icons.album, size: 56)
              : Image.network(
                  widget.item.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.album, size: 56),
                ),
        ),
      ),
    );
  }
}

class LyricPanel extends StatefulWidget {
  const LyricPanel({
    super.key,
    required this.state,
    required this.controller,
  });

  final EchoState state;
  final EchoController controller;

  @override
  State<LyricPanel> createState() => _LyricPanelState();
}

class _LyricPanelState extends State<LyricPanel> {
  static const _panelHeight = 190.0;
  static const _lineHeight = 38.0;
  static const _manualHold = Duration(seconds: 5);

  final _scrollController = ScrollController();
  Timer? _manualHoldTimer;
  var _autoScrolling = false;
  var _manualHoldActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _centerActiveLine(animated: false));
  }

  @override
  void didUpdateWidget(covariant LyricPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final songChanged = oldWidget.state.current?.id != widget.state.current?.id;
    final lyricsChanged =
        oldWidget.state.lyrics.length != widget.state.lyrics.length;
    final activeChanged =
        oldWidget.state.activeLyricIndex != widget.state.activeLyricIndex;
    if (songChanged) {
      _clearManualHold();
    }
    if (songChanged || lyricsChanged || activeChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_manualHoldActive) {
          _centerActiveLine(animated: !songChanged);
        }
      });
    }
  }

  @override
  void dispose() {
    _manualHoldTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleManualScroll() {
    if (_autoScrolling) return;
    _manualHoldActive = true;
    _manualHoldTimer?.cancel();
    _manualHoldTimer = Timer(_manualHold, () {
      if (!mounted) return;
      _manualHoldActive = false;
      _centerActiveLine(animated: true);
    });
  }

  void _clearManualHold() {
    _manualHoldTimer?.cancel();
    _manualHoldActive = false;
  }

  void _centerActiveLine({required bool animated}) {
    if (!mounted || !_scrollController.hasClients) return;
    final active = widget.state.activeLyricIndex;
    if (active < 0 || widget.state.lyrics.isEmpty) return;

    final target = (active * _lineHeight) - ((_panelHeight - _lineHeight) / 2);
    final clamped = target.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    if ((clamped - _scrollController.offset).abs() < 0.5) return;

    _autoScrolling = true;
    if (animated) {
      _scrollController
          .animateTo(
        clamped,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() {
        _autoScrolling = false;
      });
    } else {
      _scrollController.jumpTo(clamped);
      _autoScrolling = false;
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification ||
        notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _handleManualScroll();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = widget.state.activeLyricIndex;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('同步歌词',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: '歌词提前',
                  onPressed: () => widget.controller.nudgeLyricOffset(-500),
                  icon: const Icon(Icons.remove),
                ),
                Text('${widget.state.lyricOffsetMs}ms'),
                IconButton(
                  tooltip: '歌词延后',
                  onPressed: () => widget.controller.nudgeLyricOffset(500),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.state.isLoadingLyrics)
              const SizedBox(
                height: 160,
                child: Center(child: Text('歌词加载中...')),
              )
            else if (widget.state.lyrics.isEmpty)
              const SizedBox(
                height: 160,
                child: Center(child: Text('未找到同步歌词')),
              )
            else
              SizedBox(
                height: _panelHeight,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: ListView.builder(
                    key: const ValueKey('lyrics-scroll-view'),
                    controller: _scrollController,
                    itemExtent: _lineHeight,
                    itemCount: widget.state.lyrics.length,
                    itemBuilder: (context, index) {
                      final line = widget.state.lyrics[index];
                      final isActive = index == active;
                      return AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: TextStyle(
                          color: isActive ? colors.tertiary : Colors.white54,
                          fontSize: isActive ? 18 : 14,
                          fontWeight:
                              isActive ? FontWeight.w800 : FontWeight.w400,
                        ),
                        child: Center(
                          child: Text(
                            line.text,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.state,
    required this.controller,
  });

  final EchoState state;
  final EchoController controller;

  @override
  Widget build(BuildContext context) {
    final durationMs =
        state.duration.inMilliseconds <= 0 ? 1 : state.duration.inMilliseconds;
    final positionMs =
        state.position.inMilliseconds.clamp(0, durationMs).toDouble();
    return Column(
      children: [
        Slider(
          value: positionMs,
          max: durationMs.toDouble(),
          onChanged: state.current == null
              ? null
              : (value) =>
                  controller.seek(Duration(milliseconds: value.round())),
        ),
        Row(
          children: [
            const Icon(Icons.repeat, size: 18, color: Colors.white60),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PlaybackMode>(
                  value: state.playbackMode,
                  isExpanded: true,
                  icon: const Icon(Icons.expand_more),
                  items: const [
                    DropdownMenuItem(
                      value: PlaybackMode.searchOrder,
                      child: Text('搜索列表顺序播放'),
                    ),
                    DropdownMenuItem(
                      value: PlaybackMode.searchShuffle,
                      child: Text('搜索列表随机播放'),
                    ),
                    DropdownMenuItem(
                      value: PlaybackMode.playlistOrder,
                      child: Text('当前歌单顺序播放'),
                    ),
                    DropdownMenuItem(
                      value: PlaybackMode.playlistShuffle,
                      child: Text('当前歌单随机播放'),
                    ),
                    DropdownMenuItem(
                      value: PlaybackMode.artistRadio,
                      child: Text('当前歌手随机播放'),
                    ),
                  ],
                  onChanged: state.current == null
                      ? null
                      : (mode) {
                          if (mode != null) {
                            controller.setPlaybackMode(mode);
                          }
                        },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(_formatDuration(state.position.inSeconds)),
            const Spacer(),
            IconButton(
              tooltip: '上一首',
              onPressed: null,
              icon: const Icon(Icons.skip_previous),
            ),
            FilledButton(
              onPressed: state.current == null || state.isResolving
                  ? null
                  : controller.togglePlay,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(16),
              ),
              child: state.isResolving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: '下一首',
              onPressed: state.current == null || state.isResolving
                  ? null
                  : controller.playNext,
              icon: const Icon(Icons.skip_next),
            ),
            const Spacer(),
            Text(_formatDuration(state.duration.inSeconds)),
          ],
        ),
      ],
    );
  }
}

class LibraryPane extends StatelessWidget {
  const LibraryPane({
    super.key,
    required this.state,
    required this.controller,
    this.compact = false,
  });

  final EchoState state;
  final EchoController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedCollectionView == CollectionView.discover
        ? CollectionView.playlists
        : state.selectedCollectionView;
    return Padding(
      padding:
          EdgeInsets.fromLTRB(compact ? 16 : 26, 20, compact ? 16 : 26, 12),
      child: DefaultTabController(
        key: ValueKey(selected),
        length: 3,
        initialIndex: switch (selected) {
          CollectionView.playlists => 0,
          CollectionView.history => 1,
          CollectionView.favorites => 2,
          CollectionView.discover => 0,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('曲库', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _createPlaylist(context, controller),
                  icon: const Icon(Icons.add),
                  label: const Text('新建歌单'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TabBar(
              onTap: (index) {
                controller.selectCollectionView(
                  [
                    CollectionView.playlists,
                    CollectionView.history,
                    CollectionView.favorites,
                  ][index],
                );
              },
              tabs: const [
                Tab(icon: Icon(Icons.queue_music), text: '我的歌单'),
                Tab(icon: Icon(Icons.history), text: '最近播放'),
                Tab(icon: Icon(Icons.favorite), text: '收藏'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                children: [
                  _PlaylistsView(state: state, controller: controller),
                  _TrackListView(
                    items: state.history,
                    emptyText: '还没有最近播放',
                    onPlay: controller.play,
                    trailingBuilder: (_, __) => const SizedBox.shrink(),
                    header: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: state.history.isEmpty
                            ? null
                            : controller.clearHistory,
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('清空'),
                      ),
                    ),
                  ),
                  _TrackListView(
                    items: state.favorites,
                    emptyText: '还没有收藏',
                    onPlay: controller.play,
                    trailingBuilder: (context, item) => IconButton(
                      tooltip: '取消收藏',
                      onPressed: () => controller.removeFromFavorites(item.id),
                      icon: const Icon(Icons.favorite),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistsView extends StatelessWidget {
  const _PlaylistsView({
    required this.state,
    required this.controller,
  });

  final EchoState state;
  final EchoController controller;

  @override
  Widget build(BuildContext context) {
    if (state.playlists.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _createPlaylist(context, controller),
          icon: const Icon(Icons.add),
          label: const Text('创建第一个歌单'),
        ),
      );
    }

    return ListView.separated(
      itemCount: state.playlists.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final playlist = state.playlists[index];
        return ExpansionTile(
          key: ValueKey('playlist-${playlist.id}'),
          leading: const Icon(Icons.queue_music),
          title: Text(playlist.name),
          subtitle: Text('${playlist.items.length} 首歌'),
          trailing: PopupMenuButton<String>(
            tooltip: '歌单操作',
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _renamePlaylist(context, controller, playlist);
                case 'delete':
                  controller.deletePlaylist(playlist.id);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
          children: [
            if (playlist.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('还没有歌曲'),
              )
            else
              ...playlist.items.map(
                (item) => ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(item.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    item.artist ?? item.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => controller.playFromPlaylist(playlist.id, item),
                  trailing: IconButton(
                    tooltip: '移出歌单',
                    onPressed: () =>
                        controller.removeFromPlaylist(playlist.id, item.id),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TrackListView extends StatelessWidget {
  const _TrackListView({
    required this.items,
    required this.emptyText,
    required this.onPlay,
    required this.trailingBuilder,
    this.header,
  });

  final List<SearchResult> items;
  final String emptyText;
  final ValueChanged<SearchResult> onPlay;
  final Widget Function(BuildContext, SearchResult) trailingBuilder;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Column(
        children: [
          if (header != null) header!,
          Expanded(child: Center(child: Text(emptyText))),
        ],
      );
    }

    return Column(
      children: [
        if (header != null) header!,
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  item.artist ?? item.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onPlay(item),
                trailing: trailingBuilder(context, item),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> _createPlaylist(
    BuildContext context, EchoController controller) async {
  final name = await _promptPlaylistName(context, title: '新建歌单');
  if (name == null) return;
  await controller.createPlaylist(name);
}

Future<void> _renamePlaylist(
  BuildContext context,
  EchoController controller,
  Playlist playlist,
) async {
  final name = await _promptPlaylistName(
    context,
    title: '重命名歌单',
    initialValue: playlist.name,
  );
  if (name == null) return;
  await controller.renamePlaylist(playlist.id, name);
}

Future<String?> _promptPlaylistName(
  BuildContext context, {
  required String title,
  String initialValue = '',
}) {
  final textController = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: textController,
        autofocus: true,
        decoration: const InputDecoration(labelText: '歌单名称'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          final value = textController.text.trim();
          if (value.isNotEmpty) Navigator.of(context).pop(value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final value = textController.text.trim();
            if (value.isNotEmpty) Navigator.of(context).pop(value);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  ).whenComplete(textController.dispose);
}

Future<void> _showAddToPlaylistSheet(
  BuildContext context,
  EchoController controller,
  List<Playlist> playlists,
  SearchResult item,
) {
  final rootContext = context;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('添加到歌单', style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('还没有歌单')),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(playlist.name),
                      subtitle: Text('${playlist.items.length} 首歌'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(controller.addToPlaylist(playlist.id, item));
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                final name = await _promptPlaylistName(
                  rootContext,
                  title: '新建歌单',
                  initialValue: '我的歌单',
                );
                if (name == null) return;
                final playlist = await controller.createPlaylist(name);
                await controller.addToPlaylist(playlist.id, item);
              },
              icon: const Icon(Icons.add),
              label: const Text('新建歌单并添加'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MiniTrack extends StatelessWidget {
  const _MiniTrack({
    required this.item,
    required this.onTap,
  });

  final SearchResult item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.music_note),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.artist ?? item.source,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
