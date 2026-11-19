import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:country_flags/country_flags.dart';
import '../models/models.dart';

/// A widget that displays a single seat in the virtual study room.
/// 
/// Shows an identicon avatar, country flag badge, username, status message,
/// and current session duration.
class SeatWidget extends StatelessWidget {
  final Seat seat;
  final VoidCallback? onTap;
  final double size;
  final bool isCurrentUser;
  final DateTime Function() now;

  const SeatWidget({
    super.key,
    required this.seat,
    this.onTap,
    this.size = 80,
    this.isCurrentUser = false,
    this.now = DateTime.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final isDark = theme.brightness == Brightness.dark;
    
    // Define colors based on whether this is the current user
    final borderColor = isCurrentUser
        ? const Color(0xFFFFB300) // Gold/Amber for current user
        : seat.isOccupied 
            ? theme.colorScheme.primary // Navy accent for other users
            : (isDark ? Colors.grey.shade700 : Colors.grey.shade300);
    
    final shadowColor = isCurrentUser
        ? const Color(0xFFFFB300).withValues(alpha: 0.3)
        : theme.colorScheme.primary.withValues(alpha: 0.1);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: seat.isOccupied 
              ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
              : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: (seat.isOccupied || isCurrentUser) ? 2 : 1,
          ),
          boxShadow: seat.isOccupied
              ? [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: isCurrentUser ? 12 : 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: seat.isOccupied && seat.user != null
            ? _buildOccupiedSeat(theme)
            : _buildEmptySeat(theme),
      ),
    );
  }

  Widget _buildOccupiedSeat(ThemeData theme) {
    final user = seat.user!;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Avatar with country flag badge
        Flexible(
          flex: 3,
          child: _buildAvatarWithBadge(user, theme),
        ),
        const SizedBox(height: 4),
        // Username
        Flexible(
          child: Text(
            user.displayName,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Session duration
        Flexible(
          child: _DurationBadge(seat: seat, now: now),
        ),
      ],
    );
  }

  Widget _buildEmptySeat(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Empty seat icon
        Flexible(
          flex: 3,
          child: Container(
            width: size * 0.7,
            height: size * 0.7,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_seat_outlined,
              size: size * 0.4,
              color: theme.brightness == Brightness.dark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: Text(
            '#${seat.seatNumber}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade500,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarWithBadge(SeatUser user, ThemeData theme) {
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        children: [
          // Identicon avatar or Google Photo
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.brightness == Brightness.dark ? Colors.grey.shade700 : Colors.grey.shade200,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: user.photoUrl != null
                  ? Image.network(
                      user.photoUrl!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildJdenticon(user),
                    )
                  : _buildJdenticon(user),
            ),
          ),
          // Country flag badge (bottom-right)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: ClipOval(
                child: CountryFlag.fromCountryCode(
                  user.countryCode,
                  height: 24,
                  width: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJdenticon(SeatUser user) {
    return SvgPicture.string(
      Jdenticon.toSvg(user.iconSeed ?? user.userId, size: size.toInt()),
      width: size,
      height: size,
    );
  }
}

class _DurationBadge extends StatefulWidget {
  const _DurationBadge({required this.seat, required this.now});

  final Seat seat;
  final DateTime Function() now;

  @override
  State<_DurationBadge> createState() => _DurationBadgeState();
}

class _DurationBadgeState extends State<_DurationBadge> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(_DurationBadge oldWidget) {
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
    final delay = elapsed.inMinutes < 0 ? 1 - remainder : minute - remainder;
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
    final theme = Theme.of(context);
    final duration = widget.seat.elapsedAt(widget.now());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    String durationText;
    if (hours > 0) {
      durationText = '${hours}h${minutes}m';
    } else {
      durationText = '${minutes}m';
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          durationText,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
