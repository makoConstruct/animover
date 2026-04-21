# Animove

[![pub.dev](https://img.shields.io/pub/v/animove.svg)](https://pub.dev/packages/animove) 

Comprehensively animates all position/layout/sizing changes.

Simply place an `Animove` around the widgets that you need animated, and place an `AnimoveFrame` around the scaffold body. (*It should be possible to make things work without a root AnimoveFrame, by having Animoves with null frames insert themselves into the Scaffold's Overlay, but I'm not going to prioritize it.*). If you need to animate size changes, you'll want `AnisizedContainer`.

### Comparison to AnimatedTo

Animove is inspired by [animated_to](https://github.com/chooyan-eng/animated_to), but we improve on AnimatedTo in many ways:

- We allow transferring between different slivers/containers/frames (AnimatedTo has quite severe glitches when moving between different AnimatedToBoundaries) (the need to move between frames came up more than once in my timer app, I don't think it's rare).

- We work better across slivers. (though there remains at least one bug, it doesn't look like a tough one)

- For hit testing/clicking, we treat an Animove'd widget as if it's already at the target destination, while AnimatedTo takes pains to make the hit test position equal the current visual position as animated. AnimatedTo's way may feel correct, in a sense, but it's actually worse from a usability perspective: If a user wants to click something before its animation completes (which is rare), it's almost always easier for them if they can treat the widget as if it's standing still at the target location, because they likely already know the target location.

- AnimatedTo also written in a way that seems like Good Practice in some sense, but it seems unnecessary at this level of scale, and it makes things harder to read and edit.

As for disadvantages, I don't see any right now, I'm going to ask the author of AnimatedTo whether we're missing any major features, and I'll address them or mention their absense here.

### Footage

The following is footage from Mako's Timer, which uses Animoves. This dynamic reflowing animation is implemented entirely with ordinary Wrap containers, with Animoves and AnimoveFrames and AnisizedContainers in them. (*I don't know why it's a bit blurry, I think kdenlive might have done that*)

https://github.com/user-attachments/assets/0d1252a7-0537-4d31-8014-77fa37aaa9b7

### When Scrolling

Position changes due to scrolling are already smooth, so don't need to be animated, so, if you have a scrollview, you probably want to put an `AnimoveFrame` around the child so that Animove'd descendents of the scrollview don't lag behind when you scroll. If it's a sliver list, you need to use an `AnimoveSliverFrame` instead. (*though, strangely, some websites, even modern ones, seem to leave this scroll-lagging effect in intentionally, for stylistic reasons, I guess it conveys a subtle visual distinction between the animoved and non-animoved content*).

### Size animation

`AnisizedContainer` animates resize in a way that harmonizes well with our other animated movements. Likewise, it does it by only running layout once, then depicting the change in layout over time in the container's background. So you may notice that the content of the AnisizedContainer reflows instantly, and this may or may not look glitchy. The solution (and this was always the only general solution to reflow animation) is to put the subwidgets inside Animoves and AnisizedContainers as well.

### The Example

The app in `example/` is intended to make it easy to compare the subtleties of the behaviors of libraries that do the same thing as Animove. AnimatedTo is included. I also tried to include HeroAnimation, it just crashes right now, I'm guessing the problem's on their end but I haven't looked very closely at it.

### roadmap/wishlist

- Handling resizing well. Which could be paraphrased as handling container alignment. If you have a right-aligned AnimoveFrame with a right aligned Animove child, and you downsize the AnimoveFrame, the child shouldn't move, as relative to the screen, or the frame above its frame, it hasn't moved. Currently, it will move, because relative to the left side of its nearest frame, it has moved, and the Animove doesn't know that it was right aligned or that the parent frame also moved to negate its movement. I think we can fix this? AnimoveFrame can, in theory, use its knowledge of its position relative to the parent AnimoveFrame to decide whether a resize should cause its items to animate or not, or, it should be able to adjust their start position.

    - (at this point, I believe it'll be a complete solution to layout animation)

