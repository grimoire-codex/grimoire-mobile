import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/reachability.dart';
import '../../core/settings.dart';
import 'contents_sheet.dart';
import 'page_images.dart';
import 'page_source.dart';
import 'progress.dart';
import 'reader_controller.dart';
import 'reader_page.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId, this.initialPage});

  final String bookId;
  final int? initialPage;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  PageController? _pages;
  int _page = 1;
  bool _chrome = true;
  bool _zoomed = false;
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _pages?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _setChrome(bool visible) {
    setState(() => _chrome = visible);
    SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  PageController _controllerFor(ReaderState state) {
    if (_pages != null) return _pages!;
    final saved = ref.read(progressProvider.notifier).pageFor(widget.bookId);
    _page = (widget.initialPage ?? saved ?? 1).clamp(1, state.source.pageCount);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch(state.source));
    return _pages = PageController(initialPage: _page - 1);
  }

  void _onPageChanged(ReaderState state, int index) {
    setState(() => _page = index + 1);
    _prefetch(state.source);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      ref.read(progressProvider.notifier).save(state.book, _page);
    });
  }

  /// Warms the pages either side, the way the web reader preloads, so a
  /// swipe lands on a page that is already rendered.
  void _prefetch(PageSource source) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final quality = ref.read(settingsProvider).quality.multiplier;
    for (final offset in const [1, 2, -1]) {
      final page = _page + offset;
      if (page < 1 || page > source.pageCount) continue;
      final aspect = source.aspectRatio(page);
      final shown = aspect == null
          ? size.width
          : (size.height * aspect).clamp(0, size.width).toDouble();
      final width = bucketWidth(shown * dpr * quality, max: source.maxWidth);
      precacheImage(source.image(page, width, urgent: false), context, onError: (_, _) {});
    }
  }

  void _goTo(int page) {
    final target = page.clamp(1, _pageCount);
    _pages?.jumpToPage(target - 1);
  }

  int get _pageCount => ref.read(readerProvider(widget.bookId)).value?.source.pageCount ?? 1;

  void _onTap(double fraction) {
    if (fraction < 0.25) {
      _pages?.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else if (fraction > 0.75) {
      _pages?.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _setChrome(!_chrome);
    }
  }

  Future<void> _askForPage() async {
    final controller = TextEditingController(text: '$_page');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(helperText: '1 – $_pageCount'),
          onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (page != null) _goTo(page);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(readerProvider(widget.bookId));
    ref.listen(readerProvider(widget.bookId), (previous, next) {
      final was = previous?.value?.source.kind;
      final now = next.value;
      if (was == ReadingSource.server && now != null && now.fellBack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server unreachable - reading your downloaded copy.')),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ReaderError(
          message: error is ReaderUnavailable ? '$error' : describeError(error),
          onRetry: () => ref.invalidate(readerProvider(widget.bookId)),
        ),
        data: _buildReader,
      ),
    );
  }

  Widget _buildReader(ReaderState state) {
    final settings = ref.watch(settingsProvider);
    final controller = _controllerFor(state);
    final source = state.source;
    final reachable = ref.watch(reachabilityProvider);

    return Stack(
      children: [
        PageView.builder(
          controller: controller,
          scrollDirection: settings.verticalPaging ? Axis.vertical : Axis.horizontal,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          itemCount: source.pageCount,
          onPageChanged: (i) => _onPageChanged(state, i),
          itemBuilder: (context, index) => ReaderPage(
            // A new source means new images; keep each page's zoom state
            // tied to its page, not its slot.
            key: ValueKey('${source.kind}-$index'),
            source: source,
            page: index + 1,
            qualityMultiplier: settings.quality.multiplier,
            onZoomChanged: (z) {
              if (z != _zoomed) setState(() => _zoomed = z);
            },
            onTap: _onTap,
            onError: ref.read(readerProvider(widget.bookId).notifier).serverPageFailed,
          ),
        ),
        _TopBar(
          visible: _chrome,
          state: state,
          canSwitch: state.downloaded && reachable,
          onContents: () => showContentsSheet(
            context,
            state: state,
            currentPage: _page,
            onSelect: _goTo,
            showBookmarks: reachable,
          ),
          onGoToPage: _askForPage,
          onToggleDirection: () =>
              ref.read(settingsProvider.notifier).setVerticalPaging(!settings.verticalPaging),
          verticalPaging: settings.verticalPaging,
          onSwitchSource: () => ref
              .read(readerProvider(widget.bookId).notifier)
              .useSource(
                source.kind == ReadingSource.server ? ReadingSource.device : ReadingSource.server,
              ),
        ),
        _BottomBar(
          visible: _chrome,
          page: _page,
          pageCount: source.pageCount,
          sourceKind: source.kind,
          onSeek: _goTo,
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.state,
    required this.canSwitch,
    required this.onContents,
    required this.onGoToPage,
    required this.onToggleDirection,
    required this.verticalPaging,
    required this.onSwitchSource,
  });

  final bool visible;
  final ReaderState state;
  final bool canSwitch;
  final VoidCallback onContents;
  final VoidCallback onGoToPage;
  final VoidCallback onToggleDirection;
  final bool verticalPaging;
  final VoidCallback onSwitchSource;

  @override
  Widget build(BuildContext context) {
    final onServer = state.source.kind == ReadingSource.server;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _Fade(
        visible: visible,
        offset: const Offset(0, -1),
        child: Material(
          color: Colors.black.withValues(alpha: 0.78),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const BackButton(color: Colors.white),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        if (state.book.systemName != null)
                          Text(
                            state.book.systemName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Contents',
                    color: Colors.white,
                    icon: const Icon(Icons.toc),
                    onPressed: onContents,
                  ),
                  PopupMenuButton<String>(
                    iconColor: Colors.white,
                    onSelected: (value) => switch (value) {
                      'page' => onGoToPage(),
                      'direction' => onToggleDirection(),
                      'source' => onSwitchSource(),
                      _ => null,
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'page', child: Text('Go to page…')),
                      PopupMenuItem(
                        value: 'direction',
                        child: Text(verticalPaging ? 'Swipe sideways' : 'Swipe up and down'),
                      ),
                      if (canSwitch)
                        PopupMenuItem(
                          value: 'source',
                          child: Text(onServer ? 'Render on this device' : 'Render on Grimoire'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.visible,
    required this.page,
    required this.pageCount,
    required this.sourceKind,
    required this.onSeek,
  });

  final bool visible;
  final int page;
  final int pageCount;
  final ReadingSource sourceKind;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    final onDevice = sourceKind == ReadingSource.device;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _Fade(
        visible: visible,
        offset: const Offset(0, 1),
        child: Material(
          color: Colors.black.withValues(alpha: 0.78),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pageCount > 1) _SeekSlider(page: page, pageCount: pageCount, onSeek: onSeek),
                  Row(
                    children: [
                      Icon(
                        onDevice ? Icons.offline_pin_outlined : Icons.cloud_outlined,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        onDevice ? 'On this device' : 'Grimoire',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        '$page / $pageCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scrubbing previews the page number and only jumps on release, so dragging
/// across a 400-page book doesn't render every page on the way.
class _SeekSlider extends StatefulWidget {
  const _SeekSlider({required this.page, required this.pageCount, required this.onSeek});

  final int page;
  final int pageCount;
  final ValueChanged<int> onSeek;

  @override
  State<_SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<_SeekSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.page.toDouble();
    return Slider(
      min: 1,
      max: widget.pageCount.toDouble(),
      value: value.clamp(1, widget.pageCount.toDouble()),
      label: '${value.round()}',
      divisions: widget.pageCount - 1,
      onChanged: (v) => setState(() => _dragging = v),
      onChangeEnd: (v) {
        setState(() => _dragging = null);
        widget.onSeek(v.round());
      },
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.offset, required this.child});

  final bool visible;
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : offset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: child,
        ),
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: BackButton(color: Colors.white),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.white70),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
