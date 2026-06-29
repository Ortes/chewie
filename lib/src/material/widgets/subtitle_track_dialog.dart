import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/models/subtitle_track.dart';
import 'package:flutter/material.dart';

/// The user's pick from a [SubtitleTrackDialog].
///
/// Wrapping the track lets callers tell "the user chose Off" ([track] is
/// `null`) apart from "the dialog was dismissed" (the dialog pops `null`).
class SubtitleTrackChoice {
  const SubtitleTrackChoice(this.track);

  /// The selected track, or `null` when the user picked "Off".
  final SubtitleTrack? track;
}

/// Shows the [SubtitleTrackDialog] for [controller] as a modal bottom sheet and
/// returns the user's choice (`SubtitleTrackChoice(null)` = Off), or `null`
/// when dismissed. Shared by the Material touch and desktop controls so the
/// presentation stays identical.
Future<SubtitleTrackChoice?> showSubtitleTrackBottomSheet(
  BuildContext context,
  ChewieController controller,
) {
  final offLabel = controller.optionsTranslation?.subtitlesButtonText != null
      ? '${controller.optionsTranslation!.subtitlesButtonText} — off'
      : 'Off';
  return showModalBottomSheet<SubtitleTrackChoice>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: controller.useRootNavigator,
    builder: (_) => SubtitleTrackDialog(
      tracks: controller.subtitleTracks,
      selectedId: controller.activeSubtitleTrackId,
      offLabel: offLabel,
    ),
  );
}

/// Lets the user pick one of the available [SubtitleTrack]s, or turn subtitles
/// off. Pops with a [SubtitleTrackChoice], or `null` when dismissed.
class SubtitleTrackDialog extends StatelessWidget {
  const SubtitleTrackDialog({
    super.key,
    required List<SubtitleTrack> tracks,
    required String? selectedId,
    this.offLabel = 'Off',
  })  : _tracks = tracks,
        _selectedId = selectedId;

  final List<SubtitleTrack> _tracks;
  final String? _selectedId;
  final String offLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const ScrollPhysics(),
      children: [
        _tile(
          context: context,
          selected: _selectedId == null,
          label: offLabel,
          onTap: () =>
              Navigator.of(context).pop(const SubtitleTrackChoice(null)),
        ),
        for (final track in _tracks)
          _tile(
            context: context,
            selected: track.id == _selectedId,
            label: track.displayLabel,
            hint: _hint(track),
            onTap: () => Navigator.of(context).pop(SubtitleTrackChoice(track)),
          ),
      ],
    );
  }

  Widget _tile({
    required BuildContext context,
    required bool selected,
    required String label,
    String? hint,
    required VoidCallback onTap,
  }) {
    final children = <Widget>[
      if (selected)
        Icon(Icons.check, size: 20.0, color: Theme.of(context).primaryColor)
      else
        const SizedBox(width: 20.0),
      const SizedBox(width: 16.0),
      Expanded(child: Text(label)),
    ];
    if (hint != null) {
      children.add(Text(hint, style: Theme.of(context).textTheme.bodySmall));
    }
    return ListTile(
      dense: true,
      selected: selected,
      onTap: onTap,
      title: Row(children: children),
    );
  }

  /// A small right-aligned hint: language plus a "CC"/"Description" tag and a
  /// "Forced" badge when applicable — enough to tell apart tracks sharing a
  /// label.
  String? _hint(SubtitleTrack track) {
    final parts = <String>[];
    final lang = track.language;
    if (lang != null && lang.isNotEmpty) parts.add(lang);
    final kindTag = switch (track.kind) {
      SubtitleTrackKind.captions => 'CC',
      SubtitleTrackKind.descriptions => 'Description',
      _ => null,
    };
    if (kindTag != null) parts.add(kindTag);
    if (track.isForced) parts.add('Forced');
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
