import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/study_bgm_controller.dart';

class StudyBgmButton extends StatelessWidget {
  const StudyBgmButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = context.select((StudyBgmController bgm) => bgm.enabled);
    return IconButton(
      tooltip: l10n.studyBgm,
      isSelected: enabled,
      selectedIcon: const Icon(Icons.music_note),
      icon: const Icon(Icons.music_off),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const _StudyBgmControls(),
      ),
    );
  }
}

class _StudyBgmControls extends StatelessWidget {
  const _StudyBgmControls();

  @override
  Widget build(BuildContext context) {
    final bgm = context.watch<StudyBgmController>();
    final l10n = AppLocalizations.of(context)!;
    final message = switch (bgm.message) {
      StudyBgmMessage.interrupted => l10n.studyBgmInterrupted,
      StudyBgmMessage.failed => l10n.studyBgmFailed,
      null => null,
    };

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.studyBgm, style: Theme.of(context).textTheme.titleLarge),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.studyBgmPlay),
              subtitle: bgm.timerAllowsPlayback
                  ? null
                  : Text(l10n.studyBgmDuringTimer),
              value: bgm.enabled,
              onChanged: bgm.ready ? bgm.setEnabled : null,
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.studyBgmTrack,
                border: const OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<StudyBgmTrack>(
                  isExpanded: true,
                  value: bgm.track,
                  isDense: true,
                  onChanged: bgm.ready
                      ? (track) {
                          if (track != null) bgm.selectTrack(track);
                        }
                      : null,
                  items: [
                    for (final track in StudyBgmTrack.values)
                      DropdownMenuItem(
                        value: track,
                        child: Text(
                          _trackName(track, l10n),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.studyBgmVolume),
            Slider(
              value: bgm.volume,
              divisions: 20,
              label: '${(bgm.volume * 100).round()}%',
              semanticFormatterCallback: (value) => '${(value * 100).round()}%',
              onChanged: bgm.ready ? bgm.setVolume : null,
              onChangeEnd: (_) => bgm.saveVolume(),
            ),
            if (message != null)
              Semantics(liveRegion: true, child: Text(message)),
          ],
        ),
      ),
    );
  }

  String _trackName(StudyBgmTrack track, AppLocalizations l10n) =>
      switch (track) {
        StudyBgmTrack.rain => l10n.studyBgmRain,
        StudyBgmTrack.waves => l10n.studyBgmWaves,
        StudyBgmTrack.musicBox => l10n.studyBgmMusicBox,
        StudyBgmTrack.dreamy => l10n.studyBgmDreamy,
        StudyBgmTrack.piano => l10n.studyBgmPiano,
        StudyBgmTrack.orchestra => l10n.studyBgmOrchestra,
        StudyBgmTrack.loFi => l10n.studyBgmLoFi,
        StudyBgmTrack.jazz => l10n.studyBgmJazz,
        StudyBgmTrack.brownNoise => l10n.studyBgmBrownNoise,
      };
}
