import 'dart:async';

import 'package:flutter/material.dart';

// 共享滑动信息
class ScrollNotificationPublisher extends InheritedWidget {
  ScrollNotificationPublisher(
      {Key? key,
      required Widget child,
      required this.scrollNotificationController})
      : super(key: key, child: child);

  final StreamController<ScrollNotification> scrollNotificationController;

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return false;
  }

  static StreamController<ScrollNotification> of(BuildContext context) {
    return (context.dependOnInheritedWidgetOfExactType<
            ScrollNotificationPublisher>() as ScrollNotificationPublisher)
        .scrollNotificationController;
  }
}
