# Animove

Make it so that when a widget's is moved from one part of the screen to another, the movement is animated appropriately. Simply place an `Animove` around the widgets that you need to move smoothly, and place an `AnimoveFrame` around the page widget.

Inspired by [animated_to](https://github.com/chooyan-eng/animated_to). Major differences:

- AnimatedTo doesn't work within slivers.

- It has visual glitches when you move between different frames (called "boundaries" there).

- For the purpose of hit testing/clicking, we treat the Animove'd widget as if it's already at the target destination, while AnimatedTo takes pains to make the hit test position equal the current visual position as animated. This may seem correct, in some way, but it's actually worse. If a user wants to click something before its animation completes (which is rare), it's almost always easier for them if they can treat the widget as if it's standing still at the target location, because they likely already know where the target location is going to be.

As for disadvantages, I don't see any right now, I'm going to ask the author of AnimatedTo whether we're missing any major features, and I'll address them or mention their absense here.

### When Scrolling

Position changes due to scrolling are already smooth, so don't need to be animated, so, if you have a scrollview, you probably want to put an `AnimoveFrame` around the child so that Animove'd descendents of the scrollview don't lag behind when you scroll. If it's a sliver list, you need to use an `AnimoveSliverFrame` instead. (*though, strangely, some websites, even modern ones, seem to leave this scroll-lagging effect in intentionally, for stylistic reasons, I guess it conveys a subtle visual distinction between the animoved and non-animoved content*).

### roadmap/wishlist

- Handling resizing well. There are two parts to this:

    - Handling alignment. If you have a right-aligned AnimoveFrame with a right aligned Animove child, and you downsize the AnimoveFrame, the child shouldn't move, as relative to the screen, or the frame above its frame, it hasn't moved. Currently, it will move, because relative to the left side of its nearest frame, it has moved, and the Animove doesn't know that it was right aligned or that the parent frame also moved to negate its movement. I think we can fix this? AnimoveFrame can, in theory, use its knowledge of its position relative to the parent AnimoveFrame to decide whether a resize should cause its items to animate or not, or, it should be able to adjust their start position.

    - Providing containers whose background size animates well ("AnisizedContainer"?) Currently you can get one from my previous (now deprecated) https://github.com/makoConstruct/animated_containers, it's called RanimatedContainer.
    
    - (at this point, I believe it'll be a complete solution to layout animation)

- Adapt the timely easing thing into a Simulation, and maybe make it the default sim.