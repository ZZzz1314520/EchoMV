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
        CollectionPane(
          title: '收藏',
          items: state.favorites,
          onPlay: controller.play,
          emptyText: '还没有收藏',
        ),
      ];
      return Scaffold(
        body: SafeArea(child: pages[_mobileIndex]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _mobileIndex,
          onDestinationSelected: (index) => setState(() => _mobileIndex = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.explore), label: '发现'),
            NavigationDestination(icon: Icon(Icons.graphic_eq), label: '播放'),
            NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
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
              child: SearchPane(state: state, controller: controller),
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
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
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
          const _NavItem(icon: Icons.explore, label: '发现', active: true),
          const _NavItem(icon: Icons.queue_music, label: '我的歌单'),
          const _NavItem(icon: Icons.history, label: '最近播放'),
          const _NavItem(icon: Icons.favorite, label: '收藏'),
          const Spacer(),
          Text('最近播放', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          ...state.history.take(4).map(
                (item) => _MiniTrack(item: item, onTap: () => controller.play(item)),
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
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? colors.primary.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: active ? colors.primary : Colors.white70),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: active ? colors.primary : Colors.white70)),
        ],
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
                onPressed: () => widget.controller.search(_searchController.text),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('搜索结果', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: 12),
              if (widget.state.query.isNotEmpty)
                Chip(label: Text(widget.state.query), visualDensity: VisualDensity.compact),
            ],
          ),
          if (widget.state.error != null) ...[
            const SizedBox(height: 10),
            Text(widget.state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: widget.state.results.isEmpty
                ? EmptySearch(onSearch: () => widget.controller.search(_searchController.text))
                : ListView.separated(
                    itemCount: widget.state.results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = widget.state.results[index];
                      return SearchResultCard(
                        item: item,
                        selected: widget.state.current?.id == item.id,
                        onPlay: () => widget.controller.play(item),
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
  });

  final SearchResult item;
  final bool selected;
  final VoidCallback onPlay;

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
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_video),
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
                        if (item.duration != null) _formatDuration(item.duration!),
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
      padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 20, compact ? 16 : 22, 12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: compact ? 0 : 0.44),
        border: compact ? null : Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('正在播放', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: '收藏',
                onPressed: state.current == null ? null : controller.toggleFavorite,
                icon: Icon(state.isCurrentFavorite ? Icons.favorite : Icons.favorite_border),
                color: state.isCurrentFavorite ? colors.secondary : Colors.white70,
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
                              peaks: state.media?.waveformPeaks,
                            ),
                            _CoverArt(item: state.current!),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        state.current!.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.item});

  final SearchResult item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 142,
        height: 142,
        color: const Color(0xFF252B30),
        child: item.thumbnailUrl == null
            ? const Icon(Icons.album, size: 56)
            : Image.network(
                item.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 56),
              ),
      ),
    );
  }
}

class LyricPanel extends StatelessWidget {
  const LyricPanel({
    super.key,
    required this.state,
    required this.controller,
  });

  final EchoState state;
  final EchoController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = state.activeLyricIndex;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('同步歌词', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: '歌词提前',
                  onPressed: () => controller.nudgeLyricOffset(-500),
                  icon: const Icon(Icons.remove),
                ),
                Text('${state.lyricOffsetMs}ms'),
                IconButton(
                  tooltip: '歌词延后',
                  onPressed: () => controller.nudgeLyricOffset(500),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.lyrics.isEmpty)
              const SizedBox(
                height: 160,
                child: Center(child: Text('未找到同步歌词')),
              )
            else
              SizedBox(
                height: 190,
                child: ListView.builder(
                  itemCount: state.lyrics.length,
                  itemBuilder: (context, index) {
                    final line = state.lyrics[index];
                    final isActive = index == active;
                    return AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style: TextStyle(
                        color: isActive ? colors.tertiary : Colors.white54,
                        fontSize: isActive ? 18 : 14,
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.w400,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(line.text, textAlign: TextAlign.center),
                      ),
                    );
                  },
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
    final durationMs = state.duration.inMilliseconds <= 0 ? 1 : state.duration.inMilliseconds;
    final positionMs = state.position.inMilliseconds.clamp(0, durationMs).toDouble();
    return Column(
      children: [
        Slider(
          value: positionMs,
          max: durationMs.toDouble(),
          onChanged: state.current == null
              ? null
              : (value) => controller.seek(Duration(milliseconds: value.round())),
        ),
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
              onPressed: state.current == null || state.isResolving ? null : controller.togglePlay,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(16),
              ),
              child: state.isResolving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: '下一首',
              onPressed: null,
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

class CollectionPane extends StatelessWidget {
  const CollectionPane({
    super.key,
    required this.title,
    required this.items,
    required this.onPlay,
    required this.emptyText,
  });

  final String title;
  final List<SearchResult> items;
  final ValueChanged<SearchResult> onPlay;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(emptyText))
                : ListView(
                    children: items
                        .map((item) => _MiniTrack(item: item, onTap: () => onPlay(item)))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
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
      subtitle: Text(item.artist ?? item.source, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
