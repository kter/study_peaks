import 'package:flutter/material.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:country_flags/country_flags.dart';
import '../models/seat.dart';

/// A widget that displays a single seat in the virtual study room.
/// 
/// Shows an identicon avatar, country flag badge, username, status message,
/// and current session duration.
class SeatWidget extends StatelessWidget {
  final Seat seat;
  final VoidCallback? onTap;
  final double size;

  const SeatWidget({
    super.key,
    required this.seat,
    this.onTap,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: seat.isOccupied 
              ? Colors.white 
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: seat.isOccupied 
                ? const Color(0xFF1A237E) // Navy accent
                : Colors.grey.shade300,
            width: seat.isOccupied ? 2 : 1,
          ),
          boxShadow: seat.isOccupied
              ? [
                  BoxShadow(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                    blurRadius: 8,
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
          child: _buildAvatarWithBadge(user),
        ),
        const SizedBox(height: 4),
        // Username
        Flexible(
          child: Text(
            user.displayName,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A237E),
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Session duration
        Flexible(
          child: _buildDurationBadge(),
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
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_seat_outlined,
              size: size * 0.4,
              color: Colors.grey.shade400,
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

  Widget _buildAvatarWithBadge(SeatUser user) {
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        children: [
          // Identicon avatar
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey.shade200,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: SvgPicture.string(
                Jdenticon.toSvg(user.userId, size: size.toInt()),
                width: size,
                height: size,
              ),
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

  Widget _buildDurationBadge() {
    final duration = Duration(seconds: seat.currentSessionDuration);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    String durationText;
    if (hours > 0) {
      durationText = '${hours}h ${minutes}m';
    } else {
      durationText = '${minutes}m';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 14,
            color: Color(0xFF1A237E),
          ),
          const SizedBox(width: 4),
          Text(
            durationText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A237E),
            ),
          ),
        ],
      ),
    );
  }
}
