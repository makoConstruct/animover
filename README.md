# Animove

[![pub.dev](https://img.shields.io/pub/v/animove.svg)](https://pub.dev/packages/animove) 

Animates changes in position, even those occurring at offset layout.

Simply place an `Animove` around the widgets that you want to have smooth movement, and place an `AnimoveFrame` around the page widget. (*It should be possible to run without an AnimoveFrame, but I haven't tested that yet, so you may encounter an easy to solve bug if you do. If you want to, please do try it and tell me how it works out!*)

Inspired by [animated_to](https://github.com/chooyan-eng/animated_to). We improve on AnimatedTo in many ways: Animove works in slivers. Animove doesn't have visual glitches when you move between different AnimoveFrames (AnimatedTo's analog to boundaries is called "AnimatedToBoundary"). And, for hit testing/clicking, we treat the Animove'd widget as if it's already at the target destination, while AnimatedTo takes pains to make the hit test position equal the current visual position as animated. AnimatedTo's way may feel correct, in a sense, but it's actually worse from a usability perspective: If a user wants to click something before its animation completes (which is rare), it's almost always easier for them if they can treat the widget as if it's standing still at the target location, because they likely already know where the target location is going to be.

As for disadvantages, I don't see any right now, I'm going to ask the author of AnimatedTo whether we're missing any major features, and I'll address them or mention their absense here.

We also provide `AnisizedContainer`, which animates resize in a way that harmonizes well with our other animated movements. Likewise, it does it by only running layout once, then depicting the change in layout over time in the container's background. So you may notice that the content of the AnisizedContainer reflows instantly, and this may or may not look glitchy. The solution (and this was always the only general solution to reflow animation) is to put the subwidgets in AnisizedContainers and Animoves as well.

The following is footage from Mako's Timer, which uses Animoves. This whole extra dynamic reflowing animation is implemented with ordinary Wrap containers, with Animoves and AnimoveFrames and AnisizedContainers in them. (*I don't know why it's a bit blurry, I think kdenlive might have done that*)

https://github.com/user-attachments/assets/0d1252a7-0537-4d31-8014-77fa37aaa9b7

### When Scrolling

Position changes due to scrolling are already smooth, so don't need to be animated, so, if you have a scrollview, you probably want to put an `AnimoveFrame` around the child so that Animove'd descendents of the scrollview don't lag behind when you scroll. If it's a sliver list, you need to use an `AnimoveSliverFrame` instead. (*though, strangely, some websites, even modern ones, seem to leave this scroll-lagging effect in intentionally, for stylistic reasons, I guess it conveys a subtle visual distinction between the animoved and non-animoved content*).

### roadmap/wishlist

- Handling resizing well. Which could be paraphrased as handling container alignment. If you have a right-aligned AnimoveFrame with a right aligned Animove child, and you downsize the AnimoveFrame, the child shouldn't move, as relative to the screen, or the frame above its frame, it hasn't moved. Currently, it will move, because relative to the left side of its nearest frame, it has moved, and the Animove doesn't know that it was right aligned or that the parent frame also moved to negate its movement. I think we can fix this? AnimoveFrame can, in theory, use its knowledge of its position relative to the parent AnimoveFrame to decide whether a resize should cause its items to animate or not, or, it should be able to adjust their start position.

    - (at this point, I believe it'll be a complete solution to layout animation)

