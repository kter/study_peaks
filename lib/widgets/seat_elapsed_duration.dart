import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/seat.dart';

/// Rebuilds the displayed duration when the seat passes a minute boundary.
class SeatElapsedDuration extends StatefulWidget {
  const SeatElapsedDuration({
    super.key,
    required this.seat,
    required this.builder,
    this.now = DateTime.now,
  });

  final Seat seat;
  final DateTime Function() now;

  final Widget Function(BuildContext, Duration) builder;

  @override
  State<SeatElapsedDuration> createState() => _SeatElapsedDurationState();
}

class _SeatElapsedDurationState extends State<SeatElapsedDuration> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(SeatElapsedDuration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seat.sessionStartedAt != widget.seat.sessionStartedAt ||
        oldWidget.now != widget.now) {
      _refreshTimer?.cancel();
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    if (widget.seat.sessionStartedAt == null) return;

    final elapsed = widget.seat.elapsedAt(widget.now());
    const minute = Duration.millisecondsPerMinute;
    final remainder = elapsed.inMilliseconds.remainder(minute);
    // Negative elapsed minutes truncate toward zero just after the boundary.
    final delay = elapsed.isNegative ? 1 - remainder : minute - remainder;
    _refreshTimer = Timer(Duration(milliseconds: delay), () {
      setState(() {});
      _scheduleRefresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.seat.elapsedAt(widget.now());
    return widget.builder(
        context, elapsed.isNegative ? Duration.zero : elapsed);
  }
}
