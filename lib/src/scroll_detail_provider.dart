/*
 * @Author: renzheng
 * @Date: 2023-11-13 19:27:34
 * @LastEditors: renzheng
 * @LastEditTime: 2023-11-15 14:24:53
 * @Description: 
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'scroll_notification_publisher.dart';

class ScrollDetailProvider extends StatefulWidget {
  const ScrollDetailProvider({
    Key? key,
    required this.child,
    this.lazy = false,
  }) : super(key: key);

  final Widget child;
  final bool lazy;

  @override
  _ScrollDetailProviderState createState() => _ScrollDetailProviderState();
}

class _ScrollDetailProviderState extends State<ScrollDetailProvider>
    with AutomaticKeepAliveClientMixin {
  bool initialed = false;
  StreamController<ScrollNotification> scrollNotificationController =
      StreamController<ScrollNotification>.broadcast();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ScrollNotificationPublisher(
      scrollNotificationController: scrollNotificationController,
      child: Builder(builder: (context) {
        if (!initialed) {
          postStartPosition(context);
          initialed = true;
        }
        return buildNotificationWidget(context, widget.child);
      }),
    );
  }

  Widget buildNotificationWidget(BuildContext context, Widget child) {
    if (widget.lazy) {
      return NotificationListener<ScrollEndNotification>(
        onNotification: (scrollNotification) {
          return postNotification(scrollNotification, context);
        },
        child: widget.child,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
        return postNotification(scrollNotification, context);
      },
      child: child,
    );
  }

  bool postNotification(ScrollNotification notification, BuildContext context) {
    scrollNotificationController.add(notification);
    return false;
  }

  // 首次展现需要单独发一个 Notification
  // pixels 为 0
  // 为了避免 listener 还没有监听上从而丢失第一次消息，延迟 500 ms
  void postStartPosition(BuildContext context) async {
    await Future.delayed(const Duration(microseconds: 500));
    final fakeScrollNotification = ScrollStartNotification(
      context: context,
      metrics: FixedScrollMetrics(
        minScrollExtent: 0.0,
        maxScrollExtent: 0.0,
        pixels: 0.0,
        viewportDimension: 0.0,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      ),
    );
    postNotification(fakeScrollNotification, context);
  }

  @override
  bool get wantKeepAlive => true;
}
