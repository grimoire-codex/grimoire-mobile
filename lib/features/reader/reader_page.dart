import 'package:flutter/material.dart';

import 'page_images.dart';
import 'page_source.dart';

/// One zoomable page.
///
/// Renders at the screen's pixel width; once pinched past 1.25x it asks for
/// a sharper render at the zoomed width, keeping the current image on screen
/// until the sharper one arrives so zooming never flashes blank.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.source,
    required this.page,
    required this.qualityMultiplier,
    required this.onZoomChanged,
    required this.onTap,
    required this.onError,
  });

  final PageSource source;
  final int page;
  final double qualityMultiplier;
  final ValueChanged<bool> onZoomChanged;

  /// A single tap, with where it landed as a fraction of the page's width.
  final ValueChanged<double> onTap;
  final ValueChanged<Object> onError;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const _doubleTapScale = 2.5;

  final _transform = TransformationController();
  double _scale = 1;
  Offset _doubleTapAt = Offset.zero;
  int _retry = 0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _settle() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if ((scale - _scale).abs() > 0.05) setState(() => _scale = scale);
    widget.onZoomChanged(zoomed);
  }

  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1.01) {
      _transform.value = Matrix4.identity();
    } else {
      const s = _doubleTapScale;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-_doubleTapAt.dx * (s - 1), -_doubleTapAt.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _settle();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final aspect = widget.source.aspectRatio(widget.page);
        // When the page is height-bound (landscape page, tall phone) its shown
        // width is narrower than the screen.
        final shownWidth = aspect == null
            ? size.width
            : (size.height * aspect).clamp(0, size.width).toDouble();
        final zoom = _scale > 1.25 ? _scale : 1.0;
        final width = bucketWidth(
          shownWidth * dpr * widget.qualityMultiplier * zoom,
          max: widget.source.maxWidth,
        );
        final provider = widget.source.image(widget.page, width);

        return GestureDetector(
          onTapUp: (d) => widget.onTap(d.localPosition.dx / size.width),
          onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _transform,
            maxScale: 6,
            onInteractionEnd: (_) => _settle(),
            child: SizedBox.fromSize(
              size: size,
              child: Center(
                child: Image(
                  key: ValueKey(_retry),
                  image: provider,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  frameBuilder: (context, child, frame, wasSync) {
                    if (frame == null && !wasSync) {
                      return _Placeholder(page: widget.page, aspect: aspect ?? 0.72);
                    }
                    return child;
                  },
                  errorBuilder: (context, error, stack) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onError(error));
                    return _PageError(
                      page: widget.page,
                      onRetry: () {
                        provider.evict();
                        setState(() => _retry++);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.page, required this.aspect});

  final int page;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: aspect,
      child: ColoredBox(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 12),
              Text('$page', style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageError extends StatelessWidget {
  const _PageError({required this.page, required this.onRetry});

  final int page;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined, size: 40),
        const SizedBox(height: 8),
        Text('Page $page didn\'t load'),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
