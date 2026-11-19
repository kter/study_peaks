import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/timer_provider.dart';
import 'dialogs/lock_task_dialog.dart';

/// Timer widget with circular progress and controls.
class TimerWidget extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback? onToggleCollapsed;

  const TimerWidget({
    super.key,
    this.isCollapsed = false,
    this.onToggleCollapsed,
  });

  @override
  State<TimerWidget> createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<TimerWidget> {
  @override
  Widget build(BuildContext context) {
    return Consumer<TimerProvider>(
      builder: (context, timer, child) {
        if (widget.isCollapsed) {
          return _buildCollapsedView(context, timer);
        }
        return _buildExpandedView(context, timer);
      },
    );
  }

  Widget _buildCollapsedView(BuildContext context, TimerProvider timer) {
    final isPomodoroBreak = timer.mode == TimerMode.pomodoro &&
        timer.pomodoroPhase == PomodoroPhase.shortBreak;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
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
                  : primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              timer.formattedTime,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isPomodoroBreak ? Colors.green.shade700 : primaryColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Compact mode toggle
          _buildCompactModeToggle(context, timer),
          const Spacer(),
          // Lock indicator (shown when screen is locked)
          if (timer.isScreenLocked)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.lock, size: 16, color: primaryColor),
            ),
          // Play/Pause button
          Container(
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () => _handlePlayPause(context, timer),
              icon: Icon(timer.isRunning ? Icons.pause : Icons.play_arrow),
              iconSize: 20,
              color: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
          ),
          const SizedBox(width: 8),
          // Expand button
          IconButton(
            onPressed: widget.onToggleCollapsed,
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

  /// Compact mode toggle for collapsed view
  Widget _buildCompactModeToggle(BuildContext context, TimerProvider timer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompactModeButton(
            context,
            timer,
            TimerMode.normal,
            Icons.timer_outlined,
            'Normal',
          ),
          _buildCompactModeButton(
            context,
            timer,
            TimerMode.pomodoro,
            Icons.hourglass_empty,
            'Pomodoro',
          ),
        ],
      ),
    );
  }

  Widget _buildCompactModeButton(
    BuildContext context,
    TimerProvider timer,
    TimerMode mode,
    IconData icon,
    String tooltip,
  ) {
    final isSelected = timer.mode == mode;
    final isPomodoroBreak = mode == TimerMode.pomodoro &&
        timer.mode == TimerMode.pomodoro &&
        timer.pomodoroPhase == PomodoroPhase.shortBreak;
    
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: timer.isRunning ? null : () => timer.setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (isPomodoroBreak ? Colors.green : primaryColor)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Theme.of(context).colorScheme.onPrimary : Colors.grey.shade500,
              ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                Text(
                  mode == TimerMode.pomodoro
                      ? (isPomodoroBreak ? 'Break' : 'Focus')
                      : 'Normal',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedView(BuildContext context, TimerProvider timer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
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
                onPressed: widget.onToggleCollapsed,
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
          const SizedBox(height: 8),
          // Screen lock switch
          _buildScreenLockSwitch(context, timer),
          const SizedBox(height: 16),
          // Timer display
          _buildTimerDisplay(context, timer),
          const SizedBox(height: 16),
          // Controls
          _buildControls(context, timer),
          // Pomodoro info
          if (timer.mode == TimerMode.pomodoro) ...[
            const SizedBox(height: 12),
            _buildPomodoroInfo(context, timer),
          ],
          // Unlock hint (shown briefly when screen is locked)
          if (timer.isScreenLocked) ...[
            const SizedBox(height: 8),
            _buildUnlockHint(context),
          ],
        ],
      ),
    );
  }

  Widget _buildScreenLockSwitch(BuildContext context, TimerProvider timer) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800.withValues(alpha: 0.5) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 16, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            l10n?.lockScreenDuringFocus ?? 'Lock screen during focus',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 32,
            child: Switch(
              value: timer.screenLockEnabled,
              onChanged: timer.isRunning ? null : (v) => timer.setScreenLockEnabled(v),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockHint(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.amber.shade900.withValues(alpha: 0.3)
              : Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.amber.shade700.withValues(alpha: 0.5)
                : Colors.amber.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 14, color: Colors.amber.shade700),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n?.lockTaskUnpinHint ?? 'Unpin: long-press Back + Recent',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle(BuildContext context, TimerProvider timer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isSelected = timer.mode == mode;
    return GestureDetector(
      onTap: timer.isRunning ? null : () => timer.setMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Theme.of(context).colorScheme.onPrimary : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.onPrimary : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerDisplay(BuildContext context, TimerProvider timer) {
    final isPomodoroBreak = timer.mode == TimerMode.pomodoro &&
        timer.pomodoroPhase == PomodoroPhase.shortBreak;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        if (timer.mode == TimerMode.pomodoro)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isPomodoroBreak
                  ? Colors.green.shade100
                  : primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isPomodoroBreak ? '☕ Break Time' : '🎯 Focus Time',
              style: TextStyle(
                color: isPomodoroBreak
                    ? Colors.green.shade700
                    : primaryColor,
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
                backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isPomodoroBreak ? Colors.green : primaryColor,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timer.formattedTime,
                  style: TextStyle(
                    fontSize: 32, // Reduced font size
                    fontWeight: FontWeight.w300,
                    color: primaryColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (timer.isScreenLocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(Icons.lock, size: 14, color: primaryColor.withValues(alpha: 0.6)),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  double _getPomodoroProgress(TimerProvider timer) {
    if (timer.pomodoroPhase == PomodoroPhase.focus) {
      return timer.pomodoroRemainingSeconds / timer.pomodoroFocusDuration;
    } else {
      return timer.pomodoroRemainingSeconds / timer.pomodoroBreakDuration;
    }
  }

  Widget _buildControls(BuildContext context, TimerProvider timer) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
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
          decoration: BoxDecoration(
            color: primaryColor,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: () => _handlePlayPause(context, timer),
            icon: Icon(timer.isRunning ? Icons.pause : Icons.play_arrow),
            iconSize: 36,
            color: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(width: 16),
        // Placeholder for symmetry
        const SizedBox(width: 44),
      ],
    );
  }

  /// Handle play/pause with optional lock task dialog.
  Future<void> _handlePlayPause(BuildContext context, TimerProvider timer) async {
    if (timer.isRunning) {
      timer.pause();
      return;
    }

    // Check if lock should be activated
    final shouldShowDialog = timer.screenLockEnabled &&
        !timer.isScreenLocked &&
        (timer.mode == TimerMode.normal ||
            (timer.mode == TimerMode.pomodoro &&
                timer.pomodoroPhase == PomodoroPhase.focus));

    if (shouldShowDialog) {
      final result = await showLockTaskDialog(context: context);
      if (!context.mounted) return;

      switch (result) {
        case LockTaskDialogResult.lockAndStart:
          await timer.startWithLock();
          break;
        case LockTaskDialogResult.startWithoutLock:
          timer.start();
          break;
        case LockTaskDialogResult.cancel:
        case null:
          // Do nothing
          break;
      }
    } else {
      timer.start();
    }
  }

  Widget _buildPomodoroInfo(BuildContext context, TimerProvider timer) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.emoji_events_outlined,
          size: 18,
          color: primaryColor,
        ),
        const SizedBox(width: 6),
        Text(
          '${timer.pomodoroCompletedCycles} cycles completed',
          style: TextStyle(
            color: primaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
