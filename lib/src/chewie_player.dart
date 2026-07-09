import 'dart:async';

import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/models/audio_track.dart';
import 'web_fullscreen.dart';
import 'package:chewie/src/models/option_item.dart';
import 'package:chewie/src/models/options_translation.dart';
import 'package:chewie/src/models/subtitle_model.dart';
import 'package:chewie/src/models/subtitle_track.dart';
import 'package:chewie/src/notifiers/player_notifier.dart';
import 'package:chewie/src/player_with_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

typedef ChewieRoutePageBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      ChewieControllerProvider controllerProvider,
    );

/// A Video Player with Material and Cupertino skins.
///
/// `video_player` is pretty low level. Chewie wraps it in a friendly skin to
/// make it easy to use!
class Chewie extends StatefulWidget {
  const Chewie({super.key, required this.controller});

  /// The [ChewieController]
  final ChewieController controller;

  @override
  ChewieState createState() {
    return ChewieState();
  }
}

class ChewieState extends State<Chewie> {
  bool _isFullScreen = false;
  bool _wasPlayingBeforeFullScreen = false;
  bool _resumeAppliedInFullScreen = false;

  bool get isControllerFullScreen => widget.controller.isFullScreen;
  late PlayerNotifier notifier;
  late final void Function() _browserFsExitHandler;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(listener);
    notifier = PlayerNotifier.init();
    // When the user presses Escape, the browser exits its native fullscreen
    // without Chewie knowing. Detect this and collapse the fullscreen route.
    _browserFsExitHandler = () {
      if (!browserInFullscreen && _isFullScreen) {
        widget.controller.exitFullScreen();
      }
    };
    if (widget.controller.useNativeFullScreenOnWeb) {
      addBrowserFullscreenChangeListener(_browserFsExitHandler);
    }
  }

  @override
  void dispose() {
    if (widget.controller.useNativeFullScreenOnWeb) {
      removeBrowserFullscreenChangeListener(_browserFsExitHandler);
    }
    widget.controller.removeListener(listener);
    notifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(Chewie oldWidget) {
    if (oldWidget.controller != widget.controller) {
      widget.controller.addListener(listener);
    }
    super.didUpdateWidget(oldWidget);
    if (_isFullScreen != isControllerFullScreen) {
      widget.controller._isFullScreen = _isFullScreen;
    }
  }

  Future<void> listener() async {
    if (widget.controller.disableFullScreenRoute) {
      // The host app owns the fullscreen presentation; never push/pop a route
      // (which on web reparents the <video> element and forces an HLS reload on
      // exit). Just mirror the controller's flag so the control icon updates.
      _isFullScreen = isControllerFullScreen;
      return;
    }
    if (isControllerFullScreen && !_isFullScreen) {
      _wasPlayingBeforeFullScreen = widget.controller.videoPlayerController.value.isPlaying;
      _resumeAppliedInFullScreen = false;
      _isFullScreen = isControllerFullScreen;
      await _pushFullScreenWidget(context);
    } else if (_isFullScreen) {
      Navigator.of(context, rootNavigator: widget.controller.useRootNavigator).pop();
      _isFullScreen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChewieControllerProvider(
      controller: widget.controller,
      child: ChangeNotifierProvider<PlayerNotifier>.value(
        value: notifier,
        builder: (context, w) => const PlayerWithControls(),
      ),
    );
  }

  Widget _buildFullScreenVideo(
    BuildContext context,
    Animation<double> animation,
    ChewieControllerProvider controllerProvider,
  ) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: widget.controller.swipeToExitFullscreen
          ? GestureDetector(
              onVerticalDragEnd: (DragEndDetails details) {
                // A positive dy indicates a downward swipe. Use a threshold to avoid accidental triggers.
                final double dy = details.primaryVelocity ?? 0;
                if (dy > widget.controller.swipeThreshold) {
                  widget.controller.exitFullScreen();
                }
              },
              child: Container(alignment: Alignment.center, color: Colors.black, child: controllerProvider),
            )
          : Container(alignment: Alignment.center, color: Colors.black, child: controllerProvider),
    );
  }

  AnimatedWidget _defaultRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    ChewieControllerProvider controllerProvider,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return _buildFullScreenVideo(context, animation, controllerProvider);
      },
    );
  }

  Widget _fullScreenRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final controllerProvider = ChewieControllerProvider(
      controller: widget.controller,
      child: ChangeNotifierProvider<PlayerNotifier>.value(
        value: notifier,
        builder: (context, w) => const PlayerWithControls(),
      ),
    );

    if (kIsWeb && !_resumeAppliedInFullScreen) {
      _resumeAppliedInFullScreen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final vpc = widget.controller.videoPlayerController;
        await vpc.pause();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (_wasPlayingBeforeFullScreen) {
          await vpc.play();
        } else {
          await vpc.play();
          await vpc.pause();
        }
      });
    }

    if (widget.controller.routePageBuilder == null) {
      return _defaultRoutePageBuilder(context, animation, secondaryAnimation, controllerProvider);
    }
    return widget.controller.routePageBuilder!(context, animation, secondaryAnimation, controllerProvider);
  }

  Future<dynamic> _pushFullScreenWidget(BuildContext context) async {
    final TransitionRoute<void> route = PageRouteBuilder<void>(pageBuilder: _fullScreenRoutePageBuilder);

    onEnterFullScreen();

    if (!widget.controller.allowedScreenSleep) {
      WakelockPlus.enable();
    }

    // Ask the browser to enter its native fullscreen. Must be called before the
    // first await so we are still inside the user-gesture event handler.
    if (widget.controller.useNativeFullScreenOnWeb) {
      requestBrowserFullscreen();
    }

    await Navigator.of(context, rootNavigator: widget.controller.useRootNavigator).push(route);

    final wasPlaying = widget.controller.videoPlayerController.value.isPlaying;

    if (kIsWeb) {
      await _reInitializeControllers(wasPlaying);
      // Exit native browser fullscreen when the Chewie route pops (e.g. user
      // clicked the fullscreen button again). No-op if Escape was already used.
      if (widget.controller.useNativeFullScreenOnWeb) {
        exitBrowserFullscreen();
      }
    }

    _isFullScreen = false;
    widget.controller.exitFullScreen();

    if (!widget.controller.allowedScreenSleep) {
      WakelockPlus.disable();
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: widget.controller.systemOverlaysAfterFullScreen);
    SystemChrome.setPreferredOrientations(widget.controller.deviceOrientationsAfterFullScreen);
  }

  void onEnterFullScreen() {
    final videoWidth = widget.controller.videoPlayerController.value.size.width;
    final videoHeight = widget.controller.videoPlayerController.value.size.height;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

    // if (widget.controller.systemOverlaysOnEnterFullScreen != null) {
    //   /// Optional user preferred settings
    //   SystemChrome.setEnabledSystemUIMode(
    //     SystemUiMode.manual,
    //     overlays: widget.controller.systemOverlaysOnEnterFullScreen,
    //   );
    // } else {
    //   /// Default behavior
    //   SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    // }

    if (widget.controller.deviceOrientationsOnEnterFullScreen != null) {
      /// Optional user preferred settings
      SystemChrome.setPreferredOrientations(widget.controller.deviceOrientationsOnEnterFullScreen!);
    } else {
      final isLandscapeVideo = videoWidth > videoHeight;
      final isPortraitVideo = videoWidth < videoHeight;

      /// Default behavior
      /// Video w > h means we force landscape
      if (isLandscapeVideo) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      }
      /// Video h > w means we force portrait
      else if (isPortraitVideo) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      }
      /// Otherwise if h == w (square video)
      else {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    }
  }

  /// When viewing full screen on web, returning from full screen could cause
  /// the original video element to lose the picture. We re-initialize the
  /// controllers for web only when returning from full screen and preserve
  /// the previous play/pause state.
  Future<void> _reInitializeControllers(bool wasPlaying) async {
    final prevPosition = widget.controller.videoPlayerController.value.position;

    await widget.controller.videoPlayerController.initialize();
    widget.controller._initialize();
    await widget.controller.videoPlayerController.seekTo(prevPosition);

    if (wasPlaying) {
      await widget.controller.videoPlayerController.play();
    } else {
      await widget.controller.videoPlayerController.play();
      await widget.controller.videoPlayerController.pause();
    }
  }
}

/// The ChewieController is used to configure and drive the Chewie Player
/// Widgets. It provides methods to control playback, such as [pause] and
/// [play], as well as methods that control the visual appearance of the player,
/// such as [enterFullScreen] or [exitFullScreen].
///
/// In addition, you can listen to the ChewieController for presentational
/// changes, such as entering and exiting full screen mode. To listen for
/// changes to the playback, such as a change to the seek position of the
/// player, please use the standard information provided by the
/// `VideoPlayerController`.
class ChewieController extends ChangeNotifier {
  ChewieController({
    required this.videoPlayerController,
    this.optionsTranslation,
    this.aspectRatio,
    this.autoInitialize = false,
    this.autoPlay = false,
    this.draggableProgressBar = true,
    this.startAt,
    this.looping = false,
    this.fullScreenByDefault = false,
    this.cupertinoProgressColors,
    this.materialProgressColors,
    this.materialSeekButtonFadeDuration = const Duration(milliseconds: 300),
    this.materialSeekButtonSize = 26,
    this.placeholder,
    this.overlay,
    this.showControlsOnInitialize = true,
    this.showOptions = true,
    this.optionsBuilder,
    this.additionalOptions,
    this.showControls = true,
    this.transformationController,
    this.zoomAndPan = false,
    this.maxScale = 2.5,
    this.subtitle,
    this.showSubtitles = false,
    this.subtitleBuilder,
    this.subtitleTracks = const <SubtitleTrack>[],
    String? activeSubtitleTrackId,
    this.onSubtitleTrackChanged,
    this.audioTracks = const <AudioTrack>[],
    String? activeAudioTrackId,
    this.onAudioTrackChanged,
    this.customControls,
    this.errorBuilder,
    this.bufferingBuilder,
    this.allowedScreenSleep = true,
    this.isLive = false,
    this.allowFullScreen = true,
    this.allowMuting = true,
    this.allowPlaybackSpeedChanging = true,
    this.useRootNavigator = true,
    this.disableFullScreenRoute = false,
    this.useNativeFullScreenOnWeb = true,
    this.playbackSpeeds = const [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
    this.systemOverlaysOnEnterFullScreen,
    this.deviceOrientationsOnEnterFullScreen,
    this.systemOverlaysAfterFullScreen = SystemUiOverlay.values,
    this.deviceOrientationsAfterFullScreen = DeviceOrientation.values,
    this.routePageBuilder,
    this.progressIndicatorDelay,
    this.hideControlsTimer = defaultHideControlsTimer,
    this.controlsSafeAreaMinimum = EdgeInsets.zero,
    this.pauseOnBackgroundTap = false,
    this.allowDoubleTapToggleFullScreen = true,
    this.swipeToExitFullscreen = true,
    this.swipeThreshold = 300,
    this.showSeekIndicator = true,
    this.keyboardSeekDuration = const Duration(seconds: 10),
    this.hideCursorInFullScreen = true,
  })  : _activeAudioTrackId = activeAudioTrackId,
        _activeSubtitleTrackId = activeSubtitleTrackId,
        assert(playbackSpeeds.every((speed) => speed > 0), 'The playbackSpeeds values must all be greater than 0') {
    _initialize();
  }

  ChewieController copyWith({
    VideoPlayerController? videoPlayerController,
    OptionsTranslation? optionsTranslation,
    double? aspectRatio,
    bool? autoInitialize,
    bool? autoPlay,
    bool? draggableProgressBar,
    Duration? startAt,
    bool? looping,
    bool? fullScreenByDefault,
    ChewieProgressColors? cupertinoProgressColors,
    ChewieProgressColors? materialProgressColors,
    Duration? materialSeekButtonFadeDuration,
    double? materialSeekButtonSize,
    Widget? placeholder,
    Widget? overlay,
    bool? showControlsOnInitialize,
    bool? showOptions,
    Future<void> Function(BuildContext, List<OptionItem>)? optionsBuilder,
    List<OptionItem> Function(BuildContext)? additionalOptions,
    bool? showControls,
    TransformationController? transformationController,
    bool? zoomAndPan,
    double? maxScale,
    Subtitles? subtitle,
    bool? showSubtitles,
    Widget Function(BuildContext, dynamic)? subtitleBuilder,
    List<SubtitleTrack>? subtitleTracks,
    String? activeSubtitleTrackId,
    FutureOr<void> Function(SubtitleTrack? track)? onSubtitleTrackChanged,
    List<AudioTrack>? audioTracks,
    String? activeAudioTrackId,
    FutureOr<void> Function(AudioTrack track)? onAudioTrackChanged,
    Widget? customControls,
    WidgetBuilder? bufferingBuilder,
    Widget Function(BuildContext, String)? errorBuilder,
    bool? allowedScreenSleep,
    bool? isLive,
    bool? allowFullScreen,
    bool? allowMuting,
    bool? allowPlaybackSpeedChanging,
    bool? useRootNavigator,
    bool? disableFullScreenRoute,
    bool? useNativeFullScreenOnWeb,
    Duration? hideControlsTimer,
    EdgeInsets? controlsSafeAreaMinimum,
    List<double>? playbackSpeeds,
    List<SystemUiOverlay>? systemOverlaysOnEnterFullScreen,
    List<DeviceOrientation>? deviceOrientationsOnEnterFullScreen,
    List<SystemUiOverlay>? systemOverlaysAfterFullScreen,
    List<DeviceOrientation>? deviceOrientationsAfterFullScreen,
    Duration? progressIndicatorDelay,
    Widget Function(BuildContext, Animation<double>, Animation<double>, ChewieControllerProvider)? routePageBuilder,
    bool? pauseOnBackgroundTap,
    bool? allowDoubleTapToggleFullScreen,
    bool? swipeToExitFullscreen,
    double? swipeThreshold,
    bool? showSeekIndicator,
    Duration? keyboardSeekDuration,
    bool? hideCursorInFullScreen,
  }) {
    return ChewieController(
      draggableProgressBar: draggableProgressBar ?? this.draggableProgressBar,
      videoPlayerController: videoPlayerController ?? this.videoPlayerController,
      optionsTranslation: optionsTranslation ?? this.optionsTranslation,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      autoInitialize: autoInitialize ?? this.autoInitialize,
      autoPlay: autoPlay ?? this.autoPlay,
      startAt: startAt ?? this.startAt,
      looping: looping ?? this.looping,
      fullScreenByDefault: fullScreenByDefault ?? this.fullScreenByDefault,
      cupertinoProgressColors: cupertinoProgressColors ?? this.cupertinoProgressColors,
      materialProgressColors: materialProgressColors ?? this.materialProgressColors,
      zoomAndPan: zoomAndPan ?? this.zoomAndPan,
      maxScale: maxScale ?? this.maxScale,
      controlsSafeAreaMinimum: controlsSafeAreaMinimum ?? this.controlsSafeAreaMinimum,
      transformationController: transformationController ?? this.transformationController,
      materialSeekButtonFadeDuration: materialSeekButtonFadeDuration ?? this.materialSeekButtonFadeDuration,
      materialSeekButtonSize: materialSeekButtonSize ?? this.materialSeekButtonSize,
      placeholder: placeholder ?? this.placeholder,
      overlay: overlay ?? this.overlay,
      showControlsOnInitialize: showControlsOnInitialize ?? this.showControlsOnInitialize,
      showOptions: showOptions ?? this.showOptions,
      optionsBuilder: optionsBuilder ?? this.optionsBuilder,
      additionalOptions: additionalOptions ?? this.additionalOptions,
      showControls: showControls ?? this.showControls,
      showSubtitles: showSubtitles ?? this.showSubtitles,
      subtitle: subtitle ?? this.subtitle,
      subtitleBuilder: subtitleBuilder ?? this.subtitleBuilder,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      activeSubtitleTrackId: activeSubtitleTrackId ?? this.activeSubtitleTrackId,
      onSubtitleTrackChanged:
          onSubtitleTrackChanged ?? this.onSubtitleTrackChanged,
      audioTracks: audioTracks ?? this.audioTracks,
      activeAudioTrackId: activeAudioTrackId ?? this.activeAudioTrackId,
      onAudioTrackChanged: onAudioTrackChanged ?? this.onAudioTrackChanged,
      customControls: customControls ?? this.customControls,
      errorBuilder: errorBuilder ?? this.errorBuilder,
      bufferingBuilder: bufferingBuilder ?? this.bufferingBuilder,
      allowedScreenSleep: allowedScreenSleep ?? this.allowedScreenSleep,
      isLive: isLive ?? this.isLive,
      allowFullScreen: allowFullScreen ?? this.allowFullScreen,
      allowMuting: allowMuting ?? this.allowMuting,
      allowPlaybackSpeedChanging: allowPlaybackSpeedChanging ?? this.allowPlaybackSpeedChanging,
      useRootNavigator: useRootNavigator ?? this.useRootNavigator,
      disableFullScreenRoute:
          disableFullScreenRoute ?? this.disableFullScreenRoute,
      useNativeFullScreenOnWeb:
          useNativeFullScreenOnWeb ?? this.useNativeFullScreenOnWeb,
      playbackSpeeds: playbackSpeeds ?? this.playbackSpeeds,
      systemOverlaysOnEnterFullScreen: systemOverlaysOnEnterFullScreen ?? this.systemOverlaysOnEnterFullScreen,
      deviceOrientationsOnEnterFullScreen:
          deviceOrientationsOnEnterFullScreen ?? this.deviceOrientationsOnEnterFullScreen,
      systemOverlaysAfterFullScreen: systemOverlaysAfterFullScreen ?? this.systemOverlaysAfterFullScreen,
      deviceOrientationsAfterFullScreen: deviceOrientationsAfterFullScreen ?? this.deviceOrientationsAfterFullScreen,
      routePageBuilder: routePageBuilder ?? this.routePageBuilder,
      hideControlsTimer: hideControlsTimer ?? this.hideControlsTimer,
      progressIndicatorDelay: progressIndicatorDelay ?? this.progressIndicatorDelay,
      pauseOnBackgroundTap: pauseOnBackgroundTap ?? this.pauseOnBackgroundTap,
      allowDoubleTapToggleFullScreen: allowDoubleTapToggleFullScreen ?? this.allowDoubleTapToggleFullScreen,
      swipeToExitFullscreen: swipeToExitFullscreen ?? this.swipeToExitFullscreen,
      swipeThreshold: swipeThreshold ?? this.swipeThreshold,
      showSeekIndicator: showSeekIndicator ?? this.showSeekIndicator,
      keyboardSeekDuration: keyboardSeekDuration ?? this.keyboardSeekDuration,
      hideCursorInFullScreen: hideCursorInFullScreen ?? this.hideCursorInFullScreen,
    );
  }

  static const defaultHideControlsTimer = Duration(seconds: 3);

  /// If false, the options button in MaterialUI and MaterialDesktopUI
  /// won't be shown.
  final bool showOptions;

  /// Pass your translations for the options like:
  /// - PlaybackSpeed
  /// - Subtitles
  /// - Cancel
  ///
  /// Buttons
  ///
  /// These are required for the default `OptionItem`'s
  final OptionsTranslation? optionsTranslation;

  /// Build your own options with default chewieOptions shiped through
  /// the builder method. Just add your own options to the Widget
  /// you'll build. If you want to hide the chewieOptions, just leave them
  /// out from your Widget.
  final Future<void> Function(BuildContext context, List<OptionItem> chewieOptions)? optionsBuilder;

  /// Add your own additional options on top of chewie options
  final List<OptionItem> Function(BuildContext context)? additionalOptions;

  /// Define here your own Widget on how your n'th subtitle will look like
  Widget Function(BuildContext context, dynamic subtitle)? subtitleBuilder;

  /// Add a List of Subtitles here in `Subtitles.subtitle`
  Subtitles? subtitle;

  /// Determines whether subtitles should be shown by default when the video starts.
  ///
  /// If set to `true`, subtitles will be displayed automatically when the video
  /// begins playing. If set to `false`, subtitles will be hidden by default.
  bool showSubtitles;

  /// Selectable subtitle tracks shown in the options menu.
  ///
  /// Source-agnostic: the host populates this (e.g. from an HLS manifest) and
  /// reacts to selection via [onSubtitleTrackChanged]. May change after the
  /// video loads — use [setSubtitleTracks] so the controls rebuild.
  List<SubtitleTrack> subtitleTracks;

  String? _activeSubtitleTrackId;

  /// Id of the currently selected track in [subtitleTracks], or `null` when
  /// subtitles are off.
  ///
  /// Read-only on purpose: the player owns this value so the CC toggle and the
  /// menu check mark stay in sync. Set the initial selection with
  /// [setSubtitleTracks] and change it through [selectSubtitleTrack]; both
  /// notify listeners.
  String? get activeSubtitleTrackId => _activeSubtitleTrackId;

  /// Performs the actual track switch when the user picks a track (or `null`
  /// for "Off").
  ///
  /// May return a [Future]; [selectSubtitleTrack] awaits it. If it throws, the
  /// selection is rolled back and the error is rethrown rather than silently
  /// swallowed.
  final FutureOr<void> Function(SubtitleTrack? track)? onSubtitleTrackChanged;

  /// The text of the cue currently on screen, for streaming sources that emit
  /// cues over time (e.g. HLS) rather than as a static [subtitle] list. Push
  /// updates with [setLiveSubtitle]; the controls render it when non-null.
  final ValueNotifier<String?> liveSubtitle = ValueNotifier<String?>(null);

  /// Whether any selectable subtitle tracks are available.
  bool get hasSubtitleTracks => subtitleTracks.isNotEmpty;

  /// Selectable audio tracks shown in the options menu.
  ///
  /// Source-agnostic: the host populates this (e.g. from an HLS manifest) and
  /// reacts to selection via [onAudioTrackChanged]. May change after the video
  /// loads — use [setAudioTracks] so the controls rebuild. Unlike subtitles,
  /// audio is never "off": one track is always active.
  List<AudioTrack> audioTracks;

  String? _activeAudioTrackId;

  /// Id of the currently selected track in [audioTracks], or `null` before one
  /// is chosen.
  ///
  /// Read-only on purpose: the player owns this value so the menu's check mark
  /// stays in sync. Set the initial selection with [setAudioTracks] and change
  /// it through [selectAudioTrack]; both notify listeners.
  String? get activeAudioTrackId => _activeAudioTrackId;

  /// Performs the actual rendition switch when the user picks a track.
  ///
  /// May return a [Future]; [selectAudioTrack] awaits it, so the host can keep
  /// it pending until the switch settles (sources typically rebuffer). If it
  /// throws, the selection is rolled back and the error is rethrown rather than
  /// silently swallowed.
  final FutureOr<void> Function(AudioTrack track)? onAudioTrackChanged;

  /// Whether more than one selectable audio track is available (a single track
  /// offers nothing to choose, so the menu entry stays hidden).
  bool get hasAudioTracks => audioTracks.length > 1;

  /// The controller for the video you want to play
  final VideoPlayerController videoPlayerController;

  /// Initialize the Video on Startup. This will prep the video for playback.
  final bool autoInitialize;

  /// Play the video as soon as it's displayed
  final bool autoPlay;

  /// Non-Draggable Progress Bar
  final bool draggableProgressBar;

  /// Start video at a certain position
  final Duration? startAt;

  /// Whether or not the video should loop
  final bool looping;

  /// Wether or not to show the controls when initializing the widget.
  final bool showControlsOnInitialize;

  /// Whether or not to show the controls at all
  final bool showControls;

  /// Controller to pass into the [InteractiveViewer] component.
  /// If it is required to control the transformation only via the controller,
  /// `zoomAndPan` should be set to false.
  final TransformationController? transformationController;

  /// Whether or not to allow zooming and panning.
  /// This can still be false, and the `transformationController` can be used to control the
  /// transformation.
  final bool zoomAndPan;

  /// Max scale when zooming
  final double maxScale;

  /// Defines customised controls. Check [MaterialControls] or
  /// [CupertinoControls] for reference.
  final Widget? customControls;

  /// When the video playback runs into an error, you can build a custom
  /// error message.
  final Widget Function(BuildContext context, String errorMessage)? errorBuilder;

  /// When the video is buffering, you can build a custom widget.
  final WidgetBuilder? bufferingBuilder;

  /// The Aspect Ratio of the Video. Important to get the correct size of the
  /// video!
  ///
  /// Will fallback to fitting within the space allowed.
  final double? aspectRatio;

  /// The colors to use for controls on iOS. By default, the iOS player uses
  /// colors sampled from the original iOS 11 designs.
  final ChewieProgressColors? cupertinoProgressColors;

  /// The colors to use for the Material Progress Bar. By default, the Material
  /// player uses the colors from your Theme.
  final ChewieProgressColors? materialProgressColors;

  // The duration of the fade animation for the seek button (Material Player only)
  final Duration materialSeekButtonFadeDuration;

  // The size of the seek button for the Material Player only
  final double materialSeekButtonSize;

  /// The placeholder is displayed underneath the Video before it is initialized
  /// or played.
  final Widget? placeholder;

  /// A widget which is placed between the video and the controls
  final Widget? overlay;

  /// Defines if the player will start in fullscreen when play is pressed
  final bool fullScreenByDefault;

  /// Defines if the player will sleep in fullscreen or not
  final bool allowedScreenSleep;

  /// Defines if the controls should be shown for live stream video
  final bool isLive;

  /// Defines if the fullscreen control should be shown
  final bool allowFullScreen;

  /// Defines if the mute control should be shown
  final bool allowMuting;

  /// Defines if the playback speed control should be shown
  final bool allowPlaybackSpeedChanging;

  /// Defines if push/pop navigations use the rootNavigator
  final bool useRootNavigator;

  /// When true, toggling fullscreen does NOT push/pop Chewie's own fullscreen
  /// route. The controller's [isFullScreen] still flips (so the control icon
  /// updates), but the player widget stays mounted in place and the host app is
  /// responsible for the fullscreen presentation (e.g. driving the browser
  /// Fullscreen API and expanding its own layout).
  ///
  /// On web, Chewie's route-based fullscreen reparents the platform-view
  /// `<video>` element; on exit the original view goes blank and the fork works
  /// around it by re-initializing the controller — which for an HLS source
  /// means a full manifest reload + rebuffer. Setting this avoids that entirely
  /// by never moving the element.
  final bool disableFullScreenRoute;

  /// On Flutter Web, also enter the browser's native fullscreen (via the
  /// Fullscreen API) when going fullscreen, instead of only expanding the
  /// Flutter view inside the browser window. Pressing Escape to leave the
  /// browser fullscreen also exits Chewie's fullscreen.
  ///
  /// Has no effect on non-web platforms.
  final bool useNativeFullScreenOnWeb;

  /// Defines the [Duration] before the video controls are hidden. By default, this is set to three seconds.
  final Duration hideControlsTimer;

  /// Defines the set of allowed playback speeds user can change
  final List<double> playbackSpeeds;

  /// Defines the system overlays visible on entering fullscreen
  final List<SystemUiOverlay>? systemOverlaysOnEnterFullScreen;

  /// Defines the set of allowed device orientations on entering fullscreen
  final List<DeviceOrientation>? deviceOrientationsOnEnterFullScreen;

  /// Defines the system overlays visible after exiting fullscreen
  final List<SystemUiOverlay> systemOverlaysAfterFullScreen;

  /// Defines the set of allowed device orientations after exiting fullscreen
  final List<DeviceOrientation> deviceOrientationsAfterFullScreen;

  /// Defines a custom RoutePageBuilder for the fullscreen
  final ChewieRoutePageBuilder? routePageBuilder;

  /// Defines a delay in milliseconds between entering buffering state and displaying the loading spinner. Set null (default) to disable it.
  final Duration? progressIndicatorDelay;

  /// Adds additional padding to the controls' [SafeArea] as desired.
  /// Defaults to [EdgeInsets.zero].
  final EdgeInsets controlsSafeAreaMinimum;

  /// Defines if the player should pause when the background is tapped
  final bool pauseOnBackgroundTap;

  /// Defines if double tap should toggle fullscreen mode
  final bool allowDoubleTapToggleFullScreen;

  /// Defines if the player allows swipe to exit fullscreen
  final bool swipeToExitFullscreen;

  /// Defines the minimum velocity threshold for swipe to exit fullscreen gesture
  /// The velocity is measured in pixels per second
  final double swipeThreshold;

  /// Whether to flash a YouTube-style indicator showing the seeked amount when
  /// seeking with the keyboard arrows on desktop. Repeated presses in the same
  /// direction accumulate (e.g. 10s → 20s → 30s). Defaults to `true`.
  final bool showSeekIndicator;

  /// How far each left/right arrow-key press seeks on the desktop controls.
  /// Also drives the amount shown by the seek indicator. Defaults to 10 seconds.
  final Duration keyboardSeekDuration;

  /// Whether the mouse cursor auto-hides together with the controls while in
  /// fullscreen (and reappears on mouse movement), like most video players.
  /// Has no effect outside fullscreen or on devices without a pointer.
  /// Defaults to `true`.
  final bool hideCursorInFullScreen;

  static ChewieController of(BuildContext context) {
    final chewieControllerProvider = context.dependOnInheritedWidgetOfExactType<ChewieControllerProvider>()!;

    return chewieControllerProvider.controller;
  }

  bool _isFullScreen = false;

  bool get isFullScreen => _isFullScreen;

  bool get isPlaying => videoPlayerController.value.isPlaying;

  Future<dynamic> _initialize() async {
    await videoPlayerController.setLooping(looping);

    if ((autoInitialize || autoPlay) && !videoPlayerController.value.isInitialized) {
      await videoPlayerController.initialize();
    }

    if (autoPlay) {
      if (fullScreenByDefault) {
        enterFullScreen();
      }

      await videoPlayerController.play();
    }

    if (startAt != null) {
      await videoPlayerController.seekTo(startAt!);
    }

    if (fullScreenByDefault) {
      videoPlayerController.addListener(_fullScreenListener);
    }
  }

  Future<void> _fullScreenListener() async {
    if (videoPlayerController.value.isPlaying && !_isFullScreen) {
      enterFullScreen();
      videoPlayerController.removeListener(_fullScreenListener);
    }
  }

  void enterFullScreen() {
    _isFullScreen = true;
    notifyListeners();
  }

  void exitFullScreen() {
    _isFullScreen = false;
    notifyListeners();
  }

  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    notifyListeners();
  }

  void togglePause() {
    isPlaying ? pause() : play();
  }

  Future<void> play() async {
    await videoPlayerController.play();
  }

  // ignore: avoid_positional_boolean_parameters
  Future<void> setLooping(bool looping) async {
    await videoPlayerController.setLooping(looping);
  }

  Future<void> pause() async {
    await videoPlayerController.pause();
  }

  Future<void> seekTo(Duration moment) async {
    await videoPlayerController.seekTo(moment);
  }

  Future<void> setVolume(double volume) async {
    await videoPlayerController.setVolume(volume);
  }

  void setSubtitle(List<Subtitle> newSubtitle) {
    subtitle = Subtitles(newSubtitle);
  }

  /// Replaces the selectable [subtitleTracks] and rebuilds the controls.
  ///
  /// Use when tracks become known only after the media loads (e.g. once an
  /// HLS manifest is parsed). Pass [activeId] to set the initially selected
  /// track without triggering [onSubtitleTrackChanged] (the host has already
  /// loaded it); leave it null to start with subtitles off.
  void setSubtitleTracks(List<SubtitleTrack> tracks, {String? activeId}) {
    subtitleTracks = tracks;
    if (activeId != null) _activeSubtitleTrackId = activeId;
    notifyListeners();
  }

  /// Selects [track] (or `null` to turn subtitles off).
  ///
  /// Updates [activeSubtitleTrackId] optimistically (so the menu's check mark
  /// and the CC toggle move immediately) and clears any on-screen
  /// [liveSubtitle] when turned off, then awaits [onSubtitleTrackChanged] to
  /// perform the actual switch. If that callback throws, the selection is
  /// rolled back to the previous track and the error is rethrown.
  Future<void> selectSubtitleTrack(SubtitleTrack? track) async {
    if (track?.id == _activeSubtitleTrackId) return;
    final previousId = _activeSubtitleTrackId;
    _activeSubtitleTrackId = track?.id;
    if (track == null) {
      liveSubtitle.value = null;
    }
    notifyListeners();

    final callback = onSubtitleTrackChanged;
    if (callback == null) return;
    try {
      await callback(track);
    } catch (_) {
      _activeSubtitleTrackId = previousId;
      notifyListeners();
      rethrow;
    }
  }

  /// Pushes the current cue text for streaming subtitle sources. Pass `null`
  /// when no cue is showing.
  void setLiveSubtitle(String? text) {
    liveSubtitle.value = text;
  }

  /// Replaces the selectable [audioTracks] and rebuilds the controls.
  ///
  /// Use when tracks become known only after the media loads (e.g. once an
  /// HLS manifest is parsed). Pass [activeId] to set the initially selected
  /// track without triggering [onAudioTrackChanged] (the host has already
  /// loaded that rendition).
  void setAudioTracks(List<AudioTrack> tracks, {String? activeId}) {
    audioTracks = tracks;
    if (activeId != null) _activeAudioTrackId = activeId;
    notifyListeners();
  }

  /// Selects [track] as the active audio rendition.
  ///
  /// Updates [activeAudioTrackId] optimistically (so the menu's check mark
  /// moves immediately), then awaits [onAudioTrackChanged] to perform the
  /// actual switch. If that callback throws, the selection is rolled back to
  /// the previous track and the error is rethrown.
  Future<void> selectAudioTrack(AudioTrack track) async {
    if (track.id == _activeAudioTrackId) return;
    final previousId = _activeAudioTrackId;
    _activeAudioTrackId = track.id;
    notifyListeners();

    final callback = onAudioTrackChanged;
    if (callback == null) return;
    try {
      await callback(track);
    } catch (_) {
      _activeAudioTrackId = previousId;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    liveSubtitle.dispose();
    super.dispose();
  }
}

class ChewieControllerProvider extends InheritedWidget {
  const ChewieControllerProvider({super.key, required this.controller, required super.child});

  final ChewieController controller;

  @override
  bool updateShouldNotify(ChewieControllerProvider oldWidget) => controller != oldWidget.controller;
}
