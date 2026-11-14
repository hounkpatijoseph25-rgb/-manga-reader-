import 'package:flutter/material.dart';

/// Page zoomable (pincer pour zoomer). Un appui simple :
/// - remet le zoom à zéro s'il est actif ;
/// - sinon transmet la position du doigt au lecteur (zones gauche / centre / droite).
class ZoomableView extends StatefulWidget {
  const ZoomableView({
    super.key,
    required this.child,
    required this.onTap,
    required this.onZoomChanged,
  });

  final Widget child;
  final ValueChanged<Offset> onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<ZoomableView> createState() => _ZoomableViewState();
}

class _ZoomableViewState extends State<ZoomableView> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  void _onTransform() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        if (_zoomed) {
          _controller.value = Matrix4.identity();
        } else {
          widget.onTap(details.globalPosition);
        }
      },
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 4,
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }
}
