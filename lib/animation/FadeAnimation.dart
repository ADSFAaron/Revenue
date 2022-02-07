import 'package:flutter/material.dart';
import 'package:simple_animations/simple_animations.dart';

class FadeAnimation extends StatelessWidget {
  final int delay;
  final Widget child;

  FadeAnimation(this.delay, this.child);

  @override
  Widget build(BuildContext context) {
    final customTween = Tween<double>(begin: -50.0, end: 0.0);

    return PlayAnimation<double>(
      tween: customTween,
      duration: const Duration(milliseconds: 1000),
      delay: Duration(milliseconds: delay),
      curve: Curves.easeOut,
      builder: (context, child, value) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 500),
          opacity: (value + 50.0) / 50.0,
          child: Transform.translate(
            offset: Offset(0, value),
            child: child,
          ),
        );
      },
      child: child,
    );

    // final tween = MultiTrackTween([
    //   Track("opacity")
    //       .add(Duration(milliseconds: 500), Tween(begin: 0.0, end: 1.0)),
    //   Track("translateY").add(
    //       Duration(milliseconds: 500), Tween(begin: -30.0, end: 0.0),
    //       curve: Curves.easeOut)
    // ]);

    // return ControlledAnimation(
    //   delay: Duration(milliseconds: (500 * delay).round()),
    //   duration: tween.duration,
    //   tween: tween,
    //   child: child,
    //   builderWithChild: (context, child, animation) => Opacity(
    //     opacity: animation["opacity"],
    //     child: Transform.translate(
    //         offset: Offset(0, animation["translateY"]), child: child),
    //   ),
    // );
  }
}
