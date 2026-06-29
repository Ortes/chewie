import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/models/audio_track.dart';
import 'package:flutter/material.dart';

/// Shows the [AudioTrackDialog] for [controller] as a modal bottom sheet and
/// returns the track the user picked, or `null` when dismissed. Shared by the
/// Material touch and desktop controls so the presentation stays identical.
Future<AudioTrack?> showAudioTrackBottomSheet(
  BuildContext context,
  ChewieController controller,
) {
  return showModalBottomSheet<AudioTrack>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: controller.useRootNavigator,
    builder: (_) => AudioTrackDialog(
      tracks: controller.audioTracks,
      selectedId: controller.activeAudioTrackId,
    ),
  );
}

/// Lets the user pick one of the available [AudioTrack]s. Pops with the chosen
/// [AudioTrack], or `null` when dismissed. Unlike subtitles there is no "off"
/// option — one audio track is always active.
class AudioTrackDialog extends StatelessWidget {
  const AudioTrackDialog({
    super.key,
    required List<AudioTrack> tracks,
    required String? selectedId,
  })  : _tracks = tracks,
        _selectedId = selectedId;

  final List<AudioTrack> _tracks;
  final String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const ScrollPhysics(),
      children: [
        for (final track in _tracks) _buildTile(context, track),
      ],
    );
  }

  Widget _buildTile(BuildContext context, AudioTrack track) {
    final selected = track.id == _selectedId;
    final children = <Widget>[
      if (selected)
        Icon(Icons.check, size: 20.0, color: Theme.of(context).primaryColor)
      else
        const SizedBox(width: 20.0),
      const SizedBox(width: 16.0),
      Expanded(child: Text(track.displayLabel)),
    ];
    final hint = _buildHint(context, track);
    if (hint != null) children.add(hint);

    return ListTile(
      dense: true,
      selected: selected,
      onTap: () => Navigator.of(context).pop(track),
      title: Row(children: children),
    );
  }

  /// A small right-aligned hint with the track's language and, when known, its
  /// channel layout and codec — enough to tell apart tracks that share a label.
  Widget? _buildHint(BuildContext context, AudioTrack track) {
    final details = <String>[
      if (track.channelLayout != null) track.channelLayout!,
      if (track.codec != null && track.codec!.isNotEmpty)
        track.codec!.toUpperCase(),
    ].join(' · ');
    final lines = <String>[
      if (track.language != null && track.language!.isNotEmpty) track.language!,
      if (details.isNotEmpty) details,
    ];
    if (lines.isEmpty) return null;

    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [for (final line in lines) Text(line, style: style)],
    );
  }
}
