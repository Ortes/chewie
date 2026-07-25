import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chewie/src/animated_play_pause.dart';
import 'package:chewie/src/center_play_button.dart';
import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/cupertino/cupertino_progress_bar.dart';
import 'package:chewie/src/cupertino/widgets/cupertino_options_dialog.dart';
import 'package:chewie/src/helpers/utils.dart';
import 'package:chewie/src/material/widgets/subtitle_track_dialog.dart'
    show SubtitleTrackChoice;
import 'package:chewie/src/models/audio_track.dart';
import 'package:chewie/src/models/option_item.dart';
import 'package:chewie/src/models/subtitle_model.dart';
import 'package:chewie/src/models/subtitle_track.dart';
import 'package:chewie/src/notifiers/index.dart';
import 'package:chewie/src/subtitle_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class CupertinoControls extends StatefulWidget {
  const CupertinoControls({
    required this.backgroundColor,
    required this.iconColor,
    this.showPlayButton = true,
    super.key,
  });

  final Color backgroundColor;
  final Color iconColor;
  final bool showPlayButton;

  @override
  State<StatefulWidget> createState() {
    return _CupertinoControlsState();
  }
}

class _CupertinoControlsState extends State<CupertinoControls>
    with SingleTickerProviderStateMixin {
  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  final marginSize = 5.0;
  Timer? _expandCollapseTimer;
  Timer? _initTimer;
  bool _dragging = false;
  Duration? _subtitlesPosition;
  // Only governs the static-subtitle path (no selectable tracks). For the
  // track path, visibility is derived from [activeSubtitleTrackId].
  bool _subtitleOn = false;
  // Last non-null track id, so toggling subtitles back on restores the user's
  // previous pick rather than jumping to the first track.
  String? _lastSubtitleId;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;
  double selectedSpeed = 1.0;
  late VideoPlayerController controller;

  // We know that _chewieController is set in didChangeDependencies
  ChewieController get chewieController => _chewieController!;
  ChewieController? _chewieController;

  // Hides the mouse cursor along with the controls while idle in fullscreen.
  MouseCursor get _idleCursor =>
      chewieController.hideCursorInFullScreen &&
          chewieController.isFullScreen &&
          notifier.hideStuff
      ? SystemMouseCursors.none
      : MouseCursor.defer;

  @override
  void initState() {
    super.initState();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return chewieController.errorBuilder != null
          ? chewieController.errorBuilder!(
              context,
              chewieController.videoPlayerController.value.errorDescription!,
            )
          : const Center(
              child: Icon(
                CupertinoIcons.exclamationmark_circle,
                color: Colors.white,
                size: 42,
              ),
            );
    }

    final backgroundColor = widget.backgroundColor;
    final iconColor = widget.iconColor;
    final orientation = MediaQuery.of(context).orientation;
    final barHeight = orientation == Orientation.portrait ? 30.0 : 47.0;
    final buttonPadding = orientation == Orientation.portrait ? 16.0 : 24.0;

    return MouseRegion(
      cursor: _idleCursor,
      onHover: (_) => _cancelAndRestartTimer(),
      child: GestureDetector(
        onTap: () => _cancelAndRestartTimer(),
        child: AbsorbPointer(
          absorbing: notifier.hideStuff,
          child: Stack(
            children: [
              if (_displayBufferingIndicator)
                _chewieController?.bufferingBuilder?.call(context) ??
                    const Center(child: CircularProgressIndicator())
              else
                _buildHitArea(),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _buildTopBar(
                    backgroundColor,
                    iconColor,
                    barHeight,
                    buttonPadding,
                  ),
                  const Spacer(),
                  if (_subtitlesVisible)
                    Transform.translate(
                      offset: Offset(
                        0.0,
                        notifier.hideStuff ? barHeight * 0.8 : 0.0,
                      ),
                      child: _buildSubtitleLayer(),
                    ),
                  _buildBottomBar(backgroundColor, iconColor, barHeight),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    controller.removeListener(_updateState);
    _hideTimer?.cancel();
    _expandCollapseTimer?.cancel();
    _initTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);
    controller = chewieController.videoPlayerController;

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  GestureDetector _buildOptionsButton(Color iconColor, double barHeight) {
    final options = <OptionItem>[];

    if (chewieController.additionalOptions != null &&
        chewieController.additionalOptions!(context).isNotEmpty) {
      options.addAll(chewieController.additionalOptions!(context));
    }

    if (chewieController.hasSubtitleTracks) {
      options.add(
        OptionItem(
          onTap: (_) async {
            Navigator.pop(context);
            await _onSubtitleTrackTap();
          },
          iconData: Icons.subtitles_outlined,
          title:
              chewieController.optionsTranslation?.subtitlesButtonText ??
              'Subtitles',
        ),
      );
    }

    if (chewieController.hasAudioTracks) {
      options.add(
        OptionItem(
          onTap: (_) async {
            Navigator.pop(context);
            await _onAudioTrackTap();
          },
          iconData: Icons.audiotrack_outlined,
          title:
              chewieController.optionsTranslation?.audioButtonText ?? 'Audio',
        ),
      );
    }

    return GestureDetector(
      onTap: () async {
        _hideTimer?.cancel();

        if (chewieController.optionsBuilder != null) {
          await chewieController.optionsBuilder!(context, options);
        } else {
          await showCupertinoModalPopup<OptionItem>(
            context: context,
            semanticsDismissible: true,
            useRootNavigator: chewieController.useRootNavigator,
            builder: (context) => CupertinoOptionsDialog(
              options: options,
              cancelButtonText:
                  chewieController.optionsTranslation?.cancelButtonText,
            ),
          );
          if (_latestValue.isPlaying) {
            _startHideTimer();
          }
        }
      },
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 4.0, right: 8.0),
        margin: const EdgeInsets.only(right: 6.0),
        child: Icon(Icons.more_vert, color: iconColor, size: 18),
      ),
    );
  }

  /// Whether subtitles are currently shown. For selectable tracks this is the
  /// single source of truth ([activeSubtitleTrackId] != null); for a static cue
  /// list it falls back to the local [_subtitleOn] toggle.
  bool get _subtitlesVisible => chewieController.hasSubtitleTracks
      ? chewieController.activeSubtitleTrackId != null
      : _subtitleOn;

  /// Renders streaming cues pushed via [ChewieController.setLiveSubtitle] when
  /// selectable tracks (or no static list) are in play, otherwise the static
  /// cue list.
  Widget _buildSubtitleLayer() {
    final usesLiveCues =
        chewieController.hasSubtitleTracks || chewieController.subtitle == null;
    if (usesLiveCues) {
      return ValueListenableBuilder<String?>(
        valueListenable: chewieController.liveSubtitle,
        builder: (context, text, _) {
          if (text == null || text.isEmpty) return const SizedBox();
          return _subtitleBox(text);
        },
      );
    }
    return _buildSubtitles(chewieController.subtitle!);
  }

  Widget _buildSubtitles(Subtitles subtitles) {
    if (_subtitlesPosition == null) {
      return const SizedBox();
    }
    final currentSubtitle = subtitles.getByPosition(_subtitlesPosition!);
    if (currentSubtitle.isEmpty) {
      return const SizedBox();
    }
    return _subtitleBox(currentSubtitle.first!.text);
  }

  Widget _subtitleBox(Object text) {
    return SubtitleOverlay(
      chewieController: chewieController,
      margin: EdgeInsets.only(left: marginSize, right: marginSize),
      text: text,
    );
  }

  Widget _buildBottomBar(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
  ) {
    return SafeArea(
      bottom: chewieController.isFullScreen,
      minimum: chewieController.controlsSafeAreaMinimum,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.bottomCenter,
          margin: EdgeInsets.all(marginSize),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.0),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: Container(
                height: barHeight,
                color: backgroundColor,
                child: chewieController.isLive
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          _buildPlayPause(controller, iconColor, barHeight),
                          _buildLive(iconColor),
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          _buildSkipBack(iconColor, barHeight),
                          _buildPlayPause(controller, iconColor, barHeight),
                          _buildSkipForward(iconColor, barHeight),
                          _buildPosition(iconColor),
                          _buildProgressBar(),
                          _buildRemaining(iconColor),
                          _buildSubtitleToggle(iconColor, barHeight),
                          if (chewieController.allowPlaybackSpeedChanging)
                            _buildSpeedButton(controller, iconColor, barHeight),
                          if (chewieController.additionalOptions != null &&
                              chewieController
                                  .additionalOptions!(context)
                                  .isNotEmpty)
                            _buildOptionsButton(iconColor, barHeight),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLive(Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Text('LIVE', style: TextStyle(color: iconColor, fontSize: 12.0)),
    );
  }

  GestureDetector _buildExpandButton(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    return GestureDetector(
      onTap: _onExpandCollapse,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0),
            child: Container(
              height: barHeight,
              padding: EdgeInsets.only(
                left: buttonPadding,
                right: buttonPadding,
              ),
              color: backgroundColor,
              child: Center(
                child: Icon(
                  chewieController.isFullScreen
                      ? CupertinoIcons.arrow_down_right_arrow_up_left
                      : CupertinoIcons.arrow_up_left_arrow_down_right,
                  color: iconColor,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHitArea() {
    final bool isFinished =
        (_latestValue.position >= _latestValue.duration) &&
        _latestValue.duration.inSeconds > 0;
    final bool showPlayButton =
        widget.showPlayButton && !_latestValue.isPlaying && !_dragging;

    return GestureDetector(
      onTap: _latestValue.isPlaying
          ? _chewieController?.pauseOnBackgroundTap ?? false
                ? () {
                    _playPause();

                    setState(() {
                      notifier.hideStuff = true;
                    });
                  }
                : _cancelAndRestartTimer
          : () {
              _hideTimer?.cancel();

              setState(() {
                notifier.hideStuff = false;
              });
            },
      child: CenterPlayButton(
        backgroundColor: widget.backgroundColor,
        iconColor: widget.iconColor,
        isFinished: isFinished,
        isPlaying: controller.value.isPlaying,
        show: showPlayButton,
        onPressed: _playPause,
      ),
    );
  }

  GestureDetector _buildMuteButton(
    VideoPlayerController controller,
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    return GestureDetector(
      onTap: () {
        _cancelAndRestartTimer();

        if (_latestValue.volume == 0) {
          controller.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = controller.value.volume;
          controller.setVolume(0.0);
        }
      },
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0),
            child: ColoredBox(
              color: backgroundColor,
              child: Container(
                height: barHeight,
                padding: EdgeInsets.only(
                  left: buttonPadding,
                  right: buttonPadding,
                ),
                child: Icon(
                  _latestValue.volume > 0 ? Icons.volume_up : Icons.volume_off,
                  color: iconColor,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  GestureDetector _buildPlayPause(
    VideoPlayerController controller,
    Color iconColor,
    double barHeight,
  ) {
    return GestureDetector(
      onTap: _playPause,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 6.0, right: 6.0),
        child: AnimatedPlayPause(
          color: widget.iconColor,
          playing: controller.value.isPlaying,
        ),
      ),
    );
  }

  Widget _buildPosition(Color iconColor) {
    final position = _latestValue.position;

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Text(
        formatDuration(position),
        style: TextStyle(color: iconColor, fontSize: 12.0),
      ),
    );
  }

  Widget _buildRemaining(Color iconColor) {
    final position = _latestValue.duration - _latestValue.position;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Text(
        '-${formatDuration(position)}',
        style: TextStyle(color: iconColor, fontSize: 12.0),
      ),
    );
  }

  Widget _buildSubtitleToggle(Color iconColor, double barHeight) {
    // Hide the button when there's nothing to toggle: neither a static cue list
    // nor selectable tracks.
    final hasStaticSubtitle = chewieController.subtitle?.isNotEmpty ?? false;
    if (!hasStaticSubtitle && !chewieController.hasSubtitleTracks) {
      return const SizedBox();
    }
    return GestureDetector(
      onTap: _subtitleToggle,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        margin: const EdgeInsets.only(right: 10.0),
        padding: const EdgeInsets.only(left: 6.0, right: 6.0),
        child: Icon(
          Icons.subtitles,
          color: _subtitlesVisible ? iconColor : Colors.grey[700],
          size: 16.0,
        ),
      ),
    );
  }

  void _subtitleToggle() {
    final controller = chewieController;
    // With selectable tracks, toggling drives the track selection so the host
    // can start/stop producing cues; visibility is derived from the active id.
    if (controller.hasSubtitleTracks) {
      if (controller.activeSubtitleTrackId != null) {
        controller.selectSubtitleTrack(null);
      } else {
        final track = _trackToRestore();
        _lastSubtitleId = track.id;
        controller.selectSubtitleTrack(track);
      }
      setState(() {});
      return;
    }
    setState(() {
      _subtitleOn = !_subtitleOn;
    });
  }

  /// The track to (re)activate when the toggle turns subtitles back on: the
  /// last one the user picked, else the source default, else the first.
  SubtitleTrack _trackToRestore() {
    final tracks = chewieController.subtitleTracks;
    return tracks.firstWhere(
      (t) => t.id == _lastSubtitleId,
      orElse: () =>
          tracks.firstWhere((t) => t.isDefault, orElse: () => tracks.first),
    );
  }

  Future<void> _onSubtitleTrackTap() async {
    _hideTimer?.cancel();

    final offLabel =
        chewieController.optionsTranslation?.subtitlesButtonText != null
        ? '${chewieController.optionsTranslation!.subtitlesButtonText} — off'
        : 'Off';
    final choice = await showCupertinoModalPopup<SubtitleTrackChoice>(
      context: context,
      semanticsDismissible: true,
      useRootNavigator: chewieController.useRootNavigator,
      builder: (context) => _SubtitleTrackDialog(
        tracks: chewieController.subtitleTracks,
        selectedId: chewieController.activeSubtitleTrackId,
        offLabel: offLabel,
      ),
    );

    if (choice != null) {
      if (choice.track != null) _lastSubtitleId = choice.track!.id;
      await chewieController.selectSubtitleTrack(choice.track);
      if (mounted) setState(() {});
    }

    if (_latestValue.isPlaying) {
      _startHideTimer();
    }
  }

  GestureDetector _buildSkipBack(Color iconColor, double barHeight) {
    return GestureDetector(
      onTap: _skipBack,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        margin: const EdgeInsets.only(left: 10.0),
        padding: const EdgeInsets.only(left: 6.0, right: 6.0),
        child: Icon(CupertinoIcons.gobackward_15, color: iconColor, size: 18.0),
      ),
    );
  }

  GestureDetector _buildSkipForward(Color iconColor, double barHeight) {
    return GestureDetector(
      onTap: _skipForward,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 6.0, right: 8.0),
        margin: const EdgeInsets.only(right: 8.0),
        child: Icon(CupertinoIcons.goforward_15, color: iconColor, size: 18.0),
      ),
    );
  }

  Future<void> _onAudioTrackTap() async {
    _hideTimer?.cancel();

    final track = await showCupertinoModalPopup<AudioTrack>(
      context: context,
      semanticsDismissible: true,
      useRootNavigator: chewieController.useRootNavigator,
      builder: (context) => _AudioTrackDialog(
        tracks: chewieController.audioTracks,
        selectedId: chewieController.activeAudioTrackId,
      ),
    );

    if (track != null) {
      await chewieController.selectAudioTrack(track);
    }

    if (_latestValue.isPlaying) {
      _startHideTimer();
    }
  }

  GestureDetector _buildSpeedButton(
    VideoPlayerController controller,
    Color iconColor,
    double barHeight,
  ) {
    return GestureDetector(
      onTap: () async {
        _hideTimer?.cancel();

        final chosenSpeed = await showCupertinoModalPopup<double>(
          context: context,
          semanticsDismissible: true,
          useRootNavigator: chewieController.useRootNavigator,
          builder: (context) => _PlaybackSpeedDialog(
            speeds: chewieController.playbackSpeeds,
            selected: _latestValue.playbackSpeed,
          ),
        );

        if (chosenSpeed != null) {
          controller.setPlaybackSpeed(chosenSpeed);

          selectedSpeed = chosenSpeed;
        }

        if (_latestValue.isPlaying) {
          _startHideTimer();
        }
      },
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 6.0, right: 8.0),
        margin: const EdgeInsets.only(right: 8.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewY(0.0)
            ..rotateX(math.pi)
            ..rotateZ(math.pi * 0.8),
          child: Icon(Icons.speed, color: iconColor, size: 18.0),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    return Container(
      height: barHeight,
      margin: EdgeInsets.only(
        top: marginSize,
        right: marginSize,
        left: marginSize,
      ),
      child: Row(
        children: <Widget>[
          if (chewieController.allowFullScreen)
            _buildExpandButton(
              backgroundColor,
              iconColor,
              barHeight,
              buttonPadding,
            ),
          const Spacer(),
          if (chewieController.allowMuting)
            _buildMuteButton(
              controller,
              backgroundColor,
              iconColor,
              barHeight,
              buttonPadding,
            ),
        ],
      ),
    );
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();

    setState(() {
      notifier.hideStuff = false;

      _startHideTimer();
    });
  }

  Future<void> _initialize() async {
    _subtitleOn =
        chewieController.showSubtitles &&
        (chewieController.subtitle?.isNotEmpty ?? false);
    // Seed the "restore on toggle" id with whatever starts active.
    _lastSubtitleId = chewieController.activeSubtitleTrackId;
    controller.addListener(_updateState);

    _updateState();

    if (controller.value.isPlaying || chewieController.autoPlay) {
      _startHideTimer();
    }

    if (chewieController.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        setState(() {
          notifier.hideStuff = false;
        });
      });
    }
  }

  void _onExpandCollapse() {
    setState(() {
      notifier.hideStuff = true;

      chewieController.toggleFullScreen();
      _expandCollapseTimer = Timer(const Duration(milliseconds: 300), () {
        setState(() {
          _cancelAndRestartTimer();
        });
      });
    });
  }

  Widget _buildProgressBar() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 12.0),
        child: CupertinoVideoProgressBar(
          controller,
          onDragStart: () {
            setState(() {
              _dragging = true;
            });

            _hideTimer?.cancel();
          },
          onDragUpdate: () {
            _hideTimer?.cancel();
          },
          onDragEnd: () {
            setState(() {
              _dragging = false;
            });

            _startHideTimer();
          },
          colors:
              chewieController.cupertinoProgressColors ??
              ChewieProgressColors(
                playedColor: const Color.fromARGB(120, 255, 255, 255),
                handleColor: const Color.fromARGB(255, 255, 255, 255),
                bufferedColor: const Color.fromARGB(60, 255, 255, 255),
                backgroundColor: const Color.fromARGB(20, 255, 255, 255),
              ),
          draggableProgressBar: chewieController.draggableProgressBar,
        ),
      ),
    );
  }

  void _playPause() {
    final isFinished =
        _latestValue.position >= _latestValue.duration &&
        _latestValue.duration.inSeconds > 0;

    setState(() {
      if (controller.value.isPlaying) {
        notifier.hideStuff = false;
        _hideTimer?.cancel();
        controller.pause();
      } else {
        _cancelAndRestartTimer();

        if (!controller.value.isInitialized) {
          controller.initialize().then((_) {
            controller.play();
          });
        } else {
          if (isFinished) {
            controller.seekTo(Duration.zero);
          }
          controller.play();
        }
      }
    });
  }

  Future<void> _skipBack() async {
    _cancelAndRestartTimer();
    final beginning = Duration.zero.inMilliseconds;
    final skip =
        (_latestValue.position - const Duration(seconds: 15)).inMilliseconds;
    await controller.seekTo(Duration(milliseconds: math.max(skip, beginning)));
    // Restoring the video speed to selected speed
    // A delay of 1 second is added to ensure a smooth transition of speed after reversing the video as reversing is an asynchronous function
    Future.delayed(const Duration(milliseconds: 1000), () {
      controller.setPlaybackSpeed(selectedSpeed);
    });
  }

  Future<void> _skipForward() async {
    _cancelAndRestartTimer();
    final end = _latestValue.duration.inMilliseconds;
    final skip =
        (_latestValue.position + const Duration(seconds: 15)).inMilliseconds;
    await controller.seekTo(Duration(milliseconds: math.min(skip, end)));
    // Restoring the video speed to selected speed
    // A delay of 1 second is added to ensure a smooth transition of speed after forwarding the video as forwaring is an asynchronous function
    Future.delayed(const Duration(milliseconds: 1000), () {
      controller.setPlaybackSpeed(selectedSpeed);
    });
  }

  void _startHideTimer() {
    final hideControlsTimer = chewieController.hideControlsTimer.isNegative
        ? ChewieController.defaultHideControlsTimer
        : chewieController.hideControlsTimer;
    _hideTimer = Timer(hideControlsTimer, () {
      setState(() {
        notifier.hideStuff = true;
      });
    });
  }

  void _bufferingTimerTimeout() {
    _displayBufferingIndicator = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _updateState() {
    if (!mounted) return;

    final bool buffering = getIsBuffering(controller);

    // display the progress bar indicator only after the buffering delay if it has been set
    if (chewieController.progressIndicatorDelay != null) {
      if (buffering) {
        _bufferingDisplayTimer ??= Timer(
          chewieController.progressIndicatorDelay!,
          _bufferingTimerTimeout,
        );
      } else {
        _bufferingDisplayTimer?.cancel();
        _bufferingDisplayTimer = null;
        _displayBufferingIndicator = false;
      }
    } else {
      _displayBufferingIndicator = buffering;
    }

    setState(() {
      _latestValue = controller.value;
      _subtitlesPosition = controller.value.position;
    });
  }
}

class _PlaybackSpeedDialog extends StatelessWidget {
  const _PlaybackSpeedDialog({
    required List<double> speeds,
    required double selected,
  }) : _speeds = speeds,
       _selected = selected;

  final List<double> _speeds;
  final double _selected;

  @override
  Widget build(BuildContext context) {
    final selectedColor = CupertinoTheme.of(context).primaryColor;

    return CupertinoActionSheet(
      actions: _speeds
          .map(
            (e) => CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(context).pop(e);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (e == _selected)
                    Icon(Icons.check, size: 20.0, color: selectedColor),
                  Text(e.toString()),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _AudioTrackDialog extends StatelessWidget {
  const _AudioTrackDialog({
    required List<AudioTrack> tracks,
    required String? selectedId,
  }) : _tracks = tracks,
       _selectedId = selectedId;

  final List<AudioTrack> _tracks;
  final String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final selectedColor = CupertinoTheme.of(context).primaryColor;

    return CupertinoActionSheet(
      actions: _tracks
          .map(
            (track) => CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(track),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (track.id == _selectedId)
                    Icon(Icons.check, size: 20.0, color: selectedColor),
                  const SizedBox(width: 8.0),
                  Flexible(child: Text(track.displayLabel)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SubtitleTrackDialog extends StatelessWidget {
  const _SubtitleTrackDialog({
    required List<SubtitleTrack> tracks,
    required String? selectedId,
    this.offLabel = 'Off',
  }) : _tracks = tracks,
       _selectedId = selectedId;

  final List<SubtitleTrack> _tracks;
  final String? _selectedId;
  final String offLabel;

  @override
  Widget build(BuildContext context) {
    final selectedColor = CupertinoTheme.of(context).primaryColor;

    Widget action({
      required bool selected,
      required String label,
      required SubtitleTrack? track,
    }) {
      return CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(SubtitleTrackChoice(track)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) Icon(Icons.check, size: 20.0, color: selectedColor),
            const SizedBox(width: 8.0),
            Flexible(child: Text(label)),
          ],
        ),
      );
    }

    return CupertinoActionSheet(
      actions: [
        action(selected: _selectedId == null, label: offLabel, track: null),
        for (final track in _tracks)
          action(
            selected: track.id == _selectedId,
            label: track.displayLabel,
            track: track,
          ),
      ],
    );
  }
}
