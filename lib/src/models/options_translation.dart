class OptionsTranslation {
  OptionsTranslation({
    this.playbackSpeedButtonText,
    this.subtitlesButtonText,
    this.audioButtonText,
    this.cancelButtonText,
  });

  String? playbackSpeedButtonText;
  String? subtitlesButtonText;
  String? audioButtonText;
  String? cancelButtonText;

  OptionsTranslation copyWith({
    String? playbackSpeedButtonText,
    String? subtitlesButtonText,
    String? audioButtonText,
    String? cancelButtonText,
  }) {
    return OptionsTranslation(
      playbackSpeedButtonText:
          playbackSpeedButtonText ?? this.playbackSpeedButtonText,
      subtitlesButtonText: subtitlesButtonText ?? this.subtitlesButtonText,
      audioButtonText: audioButtonText ?? this.audioButtonText,
      cancelButtonText: cancelButtonText ?? this.cancelButtonText,
    );
  }

  @override
  String toString() =>
      'OptionsTranslation(playbackSpeedButtonText: $playbackSpeedButtonText, subtitlesButtonText: $subtitlesButtonText, audioButtonText: $audioButtonText, cancelButtonText: $cancelButtonText)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is OptionsTranslation &&
        other.playbackSpeedButtonText == playbackSpeedButtonText &&
        other.subtitlesButtonText == subtitlesButtonText &&
        other.audioButtonText == audioButtonText &&
        other.cancelButtonText == cancelButtonText;
  }

  @override
  int get hashCode =>
      playbackSpeedButtonText.hashCode ^
      subtitlesButtonText.hashCode ^
      audioButtonText.hashCode ^
      cancelButtonText.hashCode;
}
