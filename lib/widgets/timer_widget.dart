import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/timer_provider.dart';

/// Timer widget with circular progress and controls.
class TimerWidget extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback? onToggleCollapsed;

  const TimerWidget({
    super.key,
    this.isCollapsed = false,
    this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<TimerProvider>(
      builder: (context, timer, child) {
        if (isCollapsed) {
          return _buildCollapsedView(timer);
        }
        return _buildExpandedView(context, timer);
      },
    );
  }

  Widget _buildCollapsedView(TimerProvider timer) {
    final isPomodoroBreak = timer.mode == TimerMode.pomodoro &&
        timer.pomodoroPhase == PomodoroPhase.shortBreak;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Timer display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isPomodoroBreak
                  ? Colors.green.shade100
                  : const Color(0xFF1A237E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              timer.formattedTime,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isPomodoroBreak ? Colors.green.shade700 : const Color(0xFF1A237E),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Mode indicator
          Icon(
            timer.mode == TimerMode.pomodoro ? Icons.hourglass_empty : Icons.timer_outlined,
            size: 18,
            color: const Color(0xFF1A237E),
          ),
          const SizedBox(width: 4),
          Text(
            timer.mode == TimerMode.pomodoro
                ? (isPomodoroBreak ? 'Break' : 'Focus')
                : 'Normal',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          // Play/Pause button
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A237E),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: timer.isRunning ? timer.pause : timer.start,
              icon: Icon(timer.isRunning ? Icons.pause : Icons.play_arrow),
              iconSize: 20,
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
          ),
          const SizedBox(width: 8),
          // Expand button
          IconButton(
            onPressed: onToggleCollapsed,
            icon: const Icon(Icons.expand_more),
            iconSize: 24,
            color: Colors.grey.shade600,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedView(BuildContext context, TimerProvider timer) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapse button row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: onToggleCollapsed,
                icon: const Icon(Icons.expand_less),
                iconSize: 24,
                color: Colors.grey.shade600,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Collapse timer',
              ),
            ],
          ),
          // Mode toggle
          _buildModeToggle(context, timer),
          const SizedBox(height: 16),
          // Timer display
          _buildTimerDisplay(timer),
          const SizedBox(height: 16),
          // Controls
          _buildControls(timer),
          // Pomodoro info
          if (timer.mode == TimerMode.pomodoro) ...[
            const SizedBox(height: 12),
            _buildPomodoroInfo(timer),
          ],
        ],
      ),
    );
  }

  Widget _buildModeToggle(BuildContext context, TimerProvider timer) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            context,
            timer,
            TimerMode.normal,
            'Normal',
            Icons.timer_outlined,
          ),
          const SizedBox(width: 8),
          _buildModeButton(
            context,
            timer,
            TimerMode.pomodoro,
            'Pomodoro',
            Icons.hourglass_empty,
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
    BuildContext context,
    TimerProvider timer,
    TimerMode mode,
    String label,
    IconData icon,
  ) {
    final isSelected = timer.mode == mode;
    return GestureDetector(
      onTap: timer.isRunning ? null : () => timer.setMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerDisplay(TimerProvider timer) {
    final isPomodoroBreak = timer.mode == TimerMode.pomodoro &&
        timer.pomodoroPhase == PomodoroPhase.shortBreak;

    return Column(
      children: [
        if (timer.mode == TimerMode.pomodoro)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isPomodoroBreak
                  ? Colors.green.shade100
                  : const Color(0xFF1A237E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isPomodoroBreak ? '☕ Break Time' : '🎯 Focus Time',
              style: TextStyle(
                color: isPomodoroBreak
                    ? Colors.green.shade700
                    : const Color(0xFF1A237E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Stack(
          alignment: Alignment.center,
          children: [
          SizedBox(
              width: 140, // Reduced size
              height: 140, // Reduced size
              child: CircularProgressIndicator(
                value: timer.mode == TimerMode.pomodoro
                    ? _getPomodoroProgress(timer)
                    : 1.0, // Fixed full circle for Normal mode instead of null (indeterminate/spinning)
                strokeWidth: 6, // Slightly thinner
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isPomodoroBreak ? Colors.green : const Color(0xFF1A237E),
                ),
              ),
            ),
            Text(
              timer.formattedTime,
              style: const TextStyle(
                fontSize: 32, // Reduced font size
                fontWeight: FontWeight.w300,
                color: Color(0xFF1A237E),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _getPomodoroProgress(TimerProvider timer) {
    if (timer.pomodoroPhase == PomodoroPhase.focus) {
      return timer.pomodoroRemainingSeconds / TimerProvider.pomodoroFocusDuration;
    } else {
      return timer.pomodoroRemainingSeconds / TimerProvider.pomodoroBreakDuration;
    }
  }

  Widget _buildControls(TimerProvider timer) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Reset button
        IconButton(
          onPressed: timer.reset,
          icon: const Icon(Icons.refresh),
          iconSize: 28,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 16),
        // Play/Pause button
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A237E),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: timer.isRunning ? timer.pause : timer.start,
            icon: Icon(timer.isRunning ? Icons.pause : Icons.play_arrow),
            iconSize: 36,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(width: 16),
        // Placeholder for symmetry
        const SizedBox(width: 44),
      ],
    );
  }

  Widget _buildPomodoroInfo(TimerProvider timer) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.emoji_events_outlined,
          size: 18,
          color: Color(0xFF1A237E),
        ),
        const SizedBox(width: 6),
        Text(
          '${timer.pomodoroCompletedCycles} cycles completed',
          style: const TextStyle(
            color: Color(0xFF1A237E),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
