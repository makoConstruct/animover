# Animove

When a widget moves from one position to another, flutter offers no way to make that animate smoothly. We fix this. Simply place an `AnimoveFrame` around the whole app, and wrap any widget you expect to jump around in an `Animove`.

Inspired by [`animated_to`](https://github.com/chooyan-eng/animated_to). Animated_to had problems with scrolling containers. Our approach resolves those. It was apparent to us that animation needs to happen within a reference frame, to prevent animation from occuring in situations where it shouldn't, and also eventually to make sure that the draw order is right (but that's not in yet), so we introduced `AnimatedFrame`s, which encompass and separate the reference frames and cause scrolling to work properly.

### Whenever you're scrolling

- If your scrollview doesn't use slivers, put an `AnimoveFrame` around the child of the scrollview. This will prevent the contents from lagging behind when you scroll. You probably don't want them to do that, (*though, strangely, some sites, even modern ones, seem to have that effect intentionally for stylistic reasons*).

- If your scrollview uses slivers, put an `AnimoveSliverFrame` around the scrollview.

Scrollviews will work great given that.

### Zindex/clipping issues

The widget will have the zindex/clip bounds of its new position instantly, which will often look like a discontinuity or error in the animation. I think we can fix this by giving each `AnimoveFrame` an overlay and painting there instead of at the site, but I'm not sure we can defer/project paint like that, iirc flutter forbids painting out of layout order. If so, we have a major problem here, but I should probably complain to the project and maybe they'll just remove that assert. But also, AnimatedTo and Hero does it somehow, we can probably imitate that.

### If you want to animate size changes

Size changes have to be handled differently, by you. Flutter's default AnimatedSize seems pretty useless, as I don't think it passes constraints from the surrounding through the size animator to the child, that seems kinda impossible and the docs' example seems to conspicuously avoid revealing what would happen in such a situation. But it might be possible to make such a widget, where it runs layout on the child once with the outside given constraints, uses that to target then animation, then lays the child out for real with the animated size change.

But the *right* way to animate size layout changes is with an instant layout change and a gradual paint change, which we started working on with a `RanimatedContainer` in a previous project, and we might complete that and move it over here soon.

Once you are structuring your containers like RanimatedContainers, and putting everything in Animoves, that will be a complete solution to animating layout changes.