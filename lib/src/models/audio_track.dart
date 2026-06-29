/// The role an [AudioTrack] plays, mirroring the common set shared by the
/// HTML5 `AudioTrack.kind`, HLS `CHARACTERISTICS`, and ExoPlayer role flags.
///
/// Lets the player disambiguate tracks that share a language (e.g. a main mix
/// and a director's commentary) and build a sensible label when the host does
/// not supply one.
enum AudioTrackKind {
  /// The primary program audio.
  main,

  /// An alternate version of the main audio (e.g. a different mix).
  alternative,

  /// Commentary, e.g. a director's or cast track.
  commentary,

  /// Audio description for visually impaired viewers.
  description,

  /// A dubbed translation of the main audio.
  dub,
}

/// A selectable audio track surfaced in the player's options menu.
///
/// This is intentionally decoupled from any particular source (HLS, DASH,
/// embedded renditions...). The host supplies the tracks and reacts to the
/// user's selection through [ChewieController.onAudioTrackChanged]; switching
/// the playing rendition is left to the host, because the official
/// `video_player` plugin exposes no audio-track selection API. Unlike
/// subtitles, audio is never "off": one track is always active.
///
/// Only [id] and [label] are required. The remaining fields are optional hints
/// the player uses to disambiguate tracks and render richer labels — populate
/// whatever the source exposes (an HLS `EXT-X-MEDIA` tag, an ExoPlayer
/// `Format`, an mpv track) and leave the rest null.
class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.label,
    this.language,
    this.kind,
    this.channelCount,
    this.codec,
    this.isDefault = false,
  });

  /// Stable identifier the host uses to recognise the track on selection.
  ///
  /// A [String] keeps the API portable across backends whose native ids are
  /// integers (hls.js track index, ExoPlayer), strings (libmpv/media_kit), or
  /// language tags: the host stringifies whatever it has and parses it back in
  /// [ChewieController.onAudioTrackChanged].
  final String id;

  /// Human-readable name shown in the menu. When empty, the player falls back
  /// to [displayLabel], derived from [language], [kind], and [channelCount].
  final String label;

  /// Optional BCP-47 language tag (e.g. `en`, `fr-CA`), shown next to [label].
  final String? language;

  /// Optional role of this track, used to tell apart tracks that share a
  /// [language].
  final AudioTrackKind? kind;

  /// Optional channel count (2 → "Stereo", 6 → "5.1", 8 → "7.1").
  final int? channelCount;

  /// Optional codec string (e.g. `aac`, `eac3`), shown as a hint.
  final String? codec;

  /// Whether the source marks this as the default track. Purely informational:
  /// the host still decides the initially active track via
  /// [ChewieController.setAudioTracks].
  final bool isDefault;

  /// A friendly channel-layout name derived from [channelCount], or `null` when
  /// the channel count is unknown.
  String? get channelLayout {
    switch (channelCount) {
      case null:
        return null;
      case 1:
        return 'Mono';
      case 2:
        return 'Stereo';
      case 6:
        return '5.1';
      case 8:
        return '7.1';
      default:
        return '$channelCount ch';
    }
  }

  /// The text shown as the track's primary label. Uses [label] when the host
  /// provided one, otherwise builds a best-effort name from [language], [kind],
  /// and [channelLayout].
  String get displayLabel {
    if (label.isNotEmpty) return label;
    final parts = <String>[];
    final lang = language;
    if (lang != null && lang.isNotEmpty) parts.add(lang);
    final trackKind = kind;
    if (trackKind != null && trackKind != AudioTrackKind.main) {
      parts.add(_kindLabel(trackKind));
    }
    final layout = channelLayout;
    if (layout != null) parts.add(layout);
    return parts.isEmpty ? 'Audio' : parts.join(' · ');
  }

  static String _kindLabel(AudioTrackKind kind) {
    switch (kind) {
      case AudioTrackKind.main:
        return 'Main';
      case AudioTrackKind.alternative:
        return 'Alternative';
      case AudioTrackKind.commentary:
        return 'Commentary';
      case AudioTrackKind.description:
        return 'Audio description';
      case AudioTrackKind.dub:
        return 'Dub';
    }
  }

  /// Two tracks are equal when they share an [id]: the id is the stable key the
  /// host selects on, so a re-labelled track is still the same track.
  @override
  bool operator ==(Object other) => other is AudioTrack && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'AudioTrack(id: $id, label: $label, language: $language, kind: $kind, '
      'channelCount: $channelCount, codec: $codec, isDefault: $isDefault)';
}
