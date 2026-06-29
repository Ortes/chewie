/// The role a [SubtitleTrack] plays, mirroring the W3C `TextTrack.kind`
/// vocabulary (and video.js / Shaka). Lets the player hint captions vs plain
/// subtitles vs audio descriptions in the menu.
enum SubtitleTrackKind {
  /// Translation of dialogue for viewers who can hear the audio.
  subtitles,

  /// Transcription including sound effects, for deaf/hard-of-hearing viewers.
  captions,

  /// Textual description of the video, for blind/low-vision viewers.
  descriptions,
}

/// A selectable subtitle track surfaced in the player's options menu.
///
/// This is intentionally decoupled from any particular source (HLS, DASH,
/// embedded, sidecar files...). The host supplies the tracks and reacts to the
/// user's selection through [ChewieController.onSubtitleTrackChanged]; how cues
/// are produced and fed back (e.g. via [ChewieController.setLiveSubtitle] for a
/// streaming source, or via [ChewieController.setSubtitle] for a parsed cue
/// list) is left to the host. Unlike audio, subtitles can be turned off — a
/// `null` selection means "Off".
///
/// Only [id] and [label] are required. The remaining fields are optional hints
/// the player uses to disambiguate tracks and render richer labels — populate
/// whatever the source exposes (an HLS `EXT-X-MEDIA` tag, a Shaka text track)
/// and leave the rest null.
class SubtitleTrack {
  const SubtitleTrack({
    required this.id,
    required this.label,
    this.language,
    this.kind,
    this.isForced = false,
    this.isDefault = false,
  });

  /// Stable identifier the host uses to recognise the track on selection.
  ///
  /// A [String] keeps the API portable across backends whose native ids are
  /// integers (hls.js track index), strings (libmpv/media_kit), or language
  /// tags: the host stringifies whatever it has and parses it back in
  /// [ChewieController.onSubtitleTrackChanged].
  final String id;

  /// Human-readable name shown in the menu. When empty, the player falls back
  /// to [displayLabel], derived from [language] and [kind].
  final String label;

  /// Optional BCP-47 language tag (e.g. `en`, `fr-CA`), shown next to [label].
  final String? language;

  /// Optional role of this track (captions vs subtitles vs descriptions).
  final SubtitleTrackKind? kind;

  /// Whether the source marks this as a forced track (shown automatically for
  /// foreign-language passages even when subtitles are otherwise off).
  final bool isForced;

  /// Whether the source marks this as the default track. Purely informational:
  /// the host still decides the initially active track via
  /// [ChewieController.setSubtitleTracks].
  final bool isDefault;

  /// The text shown as the track's primary label. Uses [label] when the host
  /// provided one, otherwise builds a best-effort name from [language] and
  /// [kind].
  String get displayLabel {
    if (label.isNotEmpty) return label;
    final parts = <String>[];
    final lang = language;
    if (lang != null && lang.isNotEmpty) parts.add(lang);
    final trackKind = kind;
    if (trackKind != null && trackKind != SubtitleTrackKind.subtitles) {
      parts.add(_kindLabel(trackKind));
    }
    return parts.isEmpty ? 'Subtitles' : parts.join(' · ');
  }

  static String _kindLabel(SubtitleTrackKind kind) {
    switch (kind) {
      case SubtitleTrackKind.subtitles:
        return 'Subtitles';
      case SubtitleTrackKind.captions:
        return 'CC';
      case SubtitleTrackKind.descriptions:
        return 'Description';
    }
  }

  /// Two tracks are equal when they share an [id]: the id is the stable key the
  /// host selects on, so a re-labelled track is still the same track.
  @override
  bool operator ==(Object other) => other is SubtitleTrack && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SubtitleTrack(id: $id, label: $label, language: $language, kind: $kind, '
      'isForced: $isForced, isDefault: $isDefault)';
}
