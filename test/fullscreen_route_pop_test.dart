import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

final Uri _src = Uri.parse(
  'https://assets.mixkit.co/videos/preview/mixkit-spinning-around-the-earth-29351-large.mp4',
);

void main() {
  testWidgets('a redundant exit request leaves the page behind the player', (
    WidgetTester tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final chewieController = ChewieController(
      videoPlayerController: VideoPlayerController.networkUrl(_src),
      autoPlay: false,
      looping: false,
    );
    addTearDown(chewieController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Column(
            children: [
              const Text('host page'),
              Expanded(child: Chewie(controller: chewieController)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('host page'), findsOneWidget);

    chewieController.enterFullScreen();
    await tester.pumpAndSettle();
    expect(chewieController.isFullScreen, isTrue);

    // The fullscreen route leaves on its own (system back button, or the web
    // re-initialization that runs after the route is already popped), and a
    // second exit source fires before Chewie has finished tearing down.
    navigatorKey.currentState!.pop();
    chewieController.exitFullScreen();
    await tester.pumpAndSettle();

    expect(find.text('host page'), findsOneWidget);
    expect(find.byType(Chewie), findsOneWidget);
  });
}
