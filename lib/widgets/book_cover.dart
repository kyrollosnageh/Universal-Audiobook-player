import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Reusable book cover art widget with caching, shimmer placeholder,
/// and error fallback.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageUrl != null
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              width: width,
              height: height,
              fit: fit,
              placeholder: (context, url) => _Placeholder(
                width: width,
                height: height,
                animate: !disableAnimations,
              ),
              errorWidget: (context, url, error) =>
                  _FallbackCover(width: width, height: height),
            )
          : _FallbackCover(width: width, height: height),
    );
  }
}

class _Placeholder extends StatefulWidget {
  const _Placeholder({this.width, this.height, this.animate = true});

  final double? width;
  final double? height;
  final bool animate;

  @override
  State<_Placeholder> createState() => _PlaceholderState();
}

class _PlaceholderState extends State<_Placeholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 0.6,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: LibrettoTheme.cardColor,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          color: LibrettoTheme.cardColor.withValues(alpha: _animation.value),
        );
      },
    );
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: LibrettoTheme.cardColor,
      child: const Center(
        child: Icon(
          Icons.headphones,
          size: 48,
          color: LibrettoTheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
