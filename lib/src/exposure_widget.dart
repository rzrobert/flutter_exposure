import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'scroll_notification_publisher.dart';

enum ScrollState { visible, invisible }

typedef OnHide = Function(Duration duration);

// 控制曝光
class Exposure extends StatefulWidget {
  const Exposure({
    Key? key,
    required this.onExpose,
    required this.child,
    this.onHide,
    this.exposeFactor = 0.5,
    this.exposureController,
    this.exposureOnce = false,
  }) : super(key: key);

  /// onExpose will be called when widget is visible
  final VoidCallback onExpose;

  /// onHide will be called when widget is invisible
  final OnHide? onHide;

  /// widget need to be tracked
  final Widget child;

  /// exposeFactor is the factor of widget height or width
  /// depending on the direction of the scroll
  final double exposeFactor;

  /// to recheck if widget is visible
  final ExposureController? exposureController;

  /// if true, exposure will only call once
  final bool exposureOnce;

  @override
  State<Exposure> createState() => _ExposureState();
}

class _ExposureState extends State<Exposure> {
  bool show = false;
  ScrollState state = ScrollState.invisible;
  DateTime? _exposeDate;
  double _scrollOffset = 0.0;
  Axis direction = Axis.vertical;
  StreamSubscription? _scrollNotificationSubscription;
  bool _subscribed = false;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (mounted) {
        subscribeScrollNotification(context);
      }
    });
    widget.exposureController?._addState(this);
    super.initState();
  }

  @override
  void dispose() {
    widget.exposureController?._removeState(this);
    _scrollNotificationSubscription?.cancel();
    _scrollNotificationSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void subscribeScrollNotification(BuildContext context) {
    if (_subscribed) {
      return;
    }
    final StreamController<ScrollNotification>? publisher =
        ScrollNotificationPublisher.of(context);
    if (publisher == null) {
      throw FlutterError(
          'Exposure widget must be a descendant of ScrollNotificationPublisher');
    } else {
      _scrollNotificationSubscription =
          publisher.stream.listen((scrollNotification) {
        _scrollOffset = scrollNotification.metrics.pixels;
        direction = scrollNotification.metrics.axis;
        trackWidgetPosition();
      });
    }
  }

  void trackWidgetPosition() {
    if (!mounted) {
      return;
    }
    final exposureOffset = getExposureOffset(context);
    final exposurePitSize = (context.findRenderObject() as RenderBox).size;
    final viewPortSize = getViewPortSize(context) ?? const Size(1, 1);

    if (direction == Axis.vertical) {
      checkExposure(exposureOffset, _scrollOffset, exposurePitSize.height,
          viewPortSize.height);
    } else {
      checkExposure(exposureOffset, _scrollOffset, exposurePitSize.width,
          viewPortSize.width);
    }
  }

  Size? getViewPortSize(BuildContext context) {
    final RenderAbstractViewport? viewport = getViewPort(context);
    final Size? size = viewport?.paintBounds.size;
    return size;
  }

  RenderAbstractViewport? getViewPort(BuildContext context) {
    try {
      final RenderObject? box = context.findRenderObject();
      final RenderAbstractViewport viewport = RenderAbstractViewport.of(box);
      return viewport;
    } on Exception catch (error, stacktrace) {
      return null;
    }
  }

  double getExposureOffset(BuildContext context) {
    final RenderObject? box = context.findRenderObject();
    final RenderAbstractViewport? viewport = getViewPort(context);

    if (viewport == null || box == null || !box.attached) {
      return 0.0;
    }
    final RevealedOffset offsetRevealToTop =
        viewport.getOffsetToReveal(box, 0.0, rect: Rect.zero);
    return offsetRevealToTop.offset;
  }

  void checkExposure(double exposureOffset, double scrollOffset,
      double currentSize, double viewPortSize) {
    final exposeFactor = min(max(widget.exposeFactor, 0.1), 0.9);
    bool becomeVisible =
        (exposureOffset + currentSize * (1 - exposeFactor)) > scrollOffset &&
            (exposureOffset + currentSize * exposeFactor) <
                (scrollOffset + viewPortSize);

    bool becomeInvisible =
        (exposureOffset + currentSize * exposeFactor) < scrollOffset ||
            (exposureOffset + (currentSize * (exposeFactor))) >
                scrollOffset + viewPortSize;

    if (state == ScrollState.invisible) {
      if (becomeVisible) {
        state = ScrollState.visible;
        widget.onExpose.call();
        _recordExposeTime();
        if (widget.exposureOnce) {
          _scrollNotificationSubscription?.cancel();
          _scrollNotificationSubscription = null;
        }
        return;
      }
    } else {
      if (becomeInvisible) {
        state = ScrollState.invisible;
        _onHide();
        return;
      }
    }
  }

  _recordExposeTime() {
    _exposeDate = DateTime.now();
  }

  _onHide() {
    widget.onHide?.call(DateTime.now().difference(_exposeDate!));
  }

  void reCheckExposeState() {
    state = ScrollState.invisible;
    show = false;
    _scrollNotificationSubscription?.cancel();
    _scrollNotificationSubscription = null;
    subscribeScrollNotification(context);
    trackWidgetPosition();
  }

  RevealedOffset _getOffsetToReveal(
      RenderViewportBase viewport, RenderObject target, double alignment,
      {Rect? rect}) {
    // Steps to convert `rect` (from a RenderBox coordinate system) to its
    // scroll offset within this viewport (not in the exact order):
    //
    // 1. Pick the outermost RenderBox (between which, and the viewport, there
    // is nothing but RenderSlivers) as an intermediate reference frame
    // (the `pivot`), convert `rect` to that coordinate space.
    //
    // 2. Convert `rect` from the `pivot` coordinate space to its sliver
    // parent's sliver coordinate system (i.e., to a scroll offset), based on
    // the axis direction and growth direction of the parent.
    //
    // 3. Convert the scroll offset to its sliver parent's coordinate space
    // using `childScrollOffset`, until we reach the viewport.
    //
    // 4. Make the final conversion from the outmost sliver to the viewport
    // using `scrollOffsetOf`.

    double leadingScrollOffset = 0.0;
    // Starting at `target` and walking towards the root:
    //  - `child` will be the last object before we reach this viewport, and
    //  - `pivot` will be the last RenderBox before we reach this viewport.
    RenderObject child = target;
    RenderBox? pivot;
    bool onlySlivers = target
        is RenderSliver; // ... between viewport and `target` (`target` included).
    while (child.parent != viewport) {
      final RenderObject parent = child.parent!;
      if (child is RenderBox) {
        pivot = child;
      }
      if (parent is RenderSliver) {
        leadingScrollOffset += parent.childScrollOffset(child)!;
      } else {
        onlySlivers = false;
        leadingScrollOffset = 0.0;
      }
      child = parent;
    }

    // `rect` in the new intermediate coordinate system.
    final Rect rectLocal;
    // Our new reference frame render object's main axis extent.
    final double pivotExtent;
    final GrowthDirection growthDirection;

    // `leadingScrollOffset` is currently the scrollOffset of our new reference
    // frame (`pivot` or `target`), within `child`.
    if (pivot != null) {
      assert(pivot.parent != null);
      assert(pivot.parent != viewport);
      assert(pivot != viewport);
      assert(pivot.parent
          is RenderSliver); // TODO(abarth): Support other kinds of render objects besides slivers.
      final RenderSliver pivotParent = pivot.parent! as RenderSliver;
      growthDirection = pivotParent.constraints.growthDirection;
      switch (viewport.axis) {
        case Axis.horizontal:
          pivotExtent = pivot.size.width;
        case Axis.vertical:
          pivotExtent = pivot.size.height;
      }

      // pivotExtent = pivot.size.height;
      rect ??= target.paintBounds;
      rectLocal = MatrixUtils.transformRect(target.getTransformTo(pivot), rect);
    } else if (onlySlivers) {
      // `pivot` does not exist. We'll have to make up one from `target`, the
      // innermost sliver.
      final RenderSliver targetSliver = target as RenderSliver;
      growthDirection = targetSliver.constraints.growthDirection;
      // TODO(LongCatIsLooong): make sure this works if `targetSliver` is a
      // persistent header, when #56413 relands.
      pivotExtent = targetSliver.geometry!.scrollExtent;
      if (rect == null) {
        switch (viewport.axis) {
          case Axis.horizontal:
            rect = Rect.fromLTWH(
              0,
              0,
              targetSliver.geometry!.scrollExtent,
              targetSliver.constraints.crossAxisExtent,
            );
          case Axis.vertical:
            rect = Rect.fromLTWH(
              0,
              0,
              targetSliver.constraints.crossAxisExtent,
              targetSliver.geometry!.scrollExtent,
            );
        }
        // rect = Rect.fromLTWH(
        //   0,
        //   0,
        //   targetSliver.constraints.crossAxisExtent,
        //   targetSliver.geometry!.scrollExtent,
        // );
      }
      rectLocal = rect;
    } else {
      assert(rect != null);
      return RevealedOffset(offset: viewport.offset.pixels, rect: rect!);
    }

    assert(child.parent == viewport);
    assert(child is RenderSliver);
    final RenderSliver sliver = child as RenderSliver;

    final double targetMainAxisExtent;
    // The scroll offset of `rect` within `child`.
    switch (applyGrowthDirectionToAxisDirection(
        viewport.axisDirection, growthDirection)) {
      case AxisDirection.up:
        leadingScrollOffset += pivotExtent - rectLocal.bottom;
        targetMainAxisExtent = rectLocal.height;
      case AxisDirection.right:
        leadingScrollOffset += rectLocal.left;
        targetMainAxisExtent = rectLocal.width;
      case AxisDirection.down:
        leadingScrollOffset += rectLocal.top;
        targetMainAxisExtent = rectLocal.height;
      case AxisDirection.left:
        leadingScrollOffset += pivotExtent - rectLocal.right;
        targetMainAxisExtent = rectLocal.width;
    }

    // So far leadingScrollOffset is the scroll offset of `rect` in the `child`
    // sliver's sliver coordinate system. The sign of this value indicates
    // whether the `rect` protrudes the leading edge of the `child` sliver. When
    // this value is non-negative and `child`'s `maxScrollObstructionExtent` is
    // greater than 0, we assume `rect` can't be obstructed by the leading edge
    // of the viewport (i.e. its pinned to the leading edge).
    final bool isPinned = sliver.geometry!.maxScrollObstructionExtent > 0 &&
        leadingScrollOffset >= 0;

    // The scroll offset in the viewport to `rect`.
    leadingScrollOffset = viewport.scrollOffsetOf(sliver, leadingScrollOffset);

    // This step assumes the viewport's layout is up-to-date, i.e., if
    // offset.pixels is changed after the last performLayout, the new scroll
    // position will not be accounted for.
    final Matrix4 transform = target.getTransformTo(viewport);
    Rect targetRect = MatrixUtils.transformRect(transform, rect);
    final double extentOfPinnedSlivers =
        viewport.maxScrollObstructionExtentBefore(sliver);

    switch (sliver.constraints.growthDirection) {
      case GrowthDirection.forward:
        if (isPinned && alignment <= 0) {
          return RevealedOffset(offset: double.infinity, rect: targetRect);
        }
        leadingScrollOffset -= extentOfPinnedSlivers;
      case GrowthDirection.reverse:
        if (isPinned && alignment >= 1) {
          return RevealedOffset(
              offset: double.negativeInfinity, rect: targetRect);
        }
        // If child's growth direction is reverse, when viewport.offset is
        // `leadingScrollOffset`, it is positioned just outside of the leading
        // edge of the viewport.
        switch (viewport.axis) {
          case Axis.vertical:
            leadingScrollOffset -= targetRect.height;
          case Axis.horizontal:
            leadingScrollOffset -= targetRect.width;
        }

      // leadingScrollOffset -= targetRect.height;
    }

    final double mainAxisExtent;
    switch (viewport.axis) {
      case Axis.horizontal:
        mainAxisExtent = viewport.size.width - extentOfPinnedSlivers;
      case Axis.vertical:
        mainAxisExtent = viewport.size.height - extentOfPinnedSlivers;
    }

    // mainAxisExtent = viewport.size.height - extentOfPinnedSlivers;

    final double targetOffset = leadingScrollOffset -
        (mainAxisExtent - targetMainAxisExtent) * alignment;
    final double offsetDifference = viewport.offset.pixels - targetOffset;

    switch (viewport.axisDirection) {
      case AxisDirection.down:
        targetRect = targetRect.translate(0.0, offsetDifference);
      case AxisDirection.right:
        targetRect = targetRect.translate(offsetDifference, 0.0);
      case AxisDirection.up:
        targetRect = targetRect.translate(0.0, -offsetDifference);
      case AxisDirection.left:
        targetRect = targetRect.translate(-offsetDifference, 0.0);
    }

    return RevealedOffset(offset: targetOffset, rect: targetRect);
  }
}

class ExposureController {
  final List<_ExposureState> _states = [];

  void _addState(_ExposureState state) {
    _states.add(state);
  }

  void _removeState(_ExposureState state) {
    _states.remove(state);
  }

  void reCheckExposeState() {
    for (var _state in _states) {
      _state.reCheckExposeState();
    }
  }
}
