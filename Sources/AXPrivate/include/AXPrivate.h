#ifndef ORDINO_AX_PRIVATE_H
#define ORDINO_AX_PRIVATE_H

#include <ApplicationServices/ApplicationServices.h>

/// Private HIServices function that maps an Accessibility window element to its
/// CoreGraphics window number. Not public API, but stable for over a decade and
/// used by Rectangle, Amethyst, AeroSpace and yabai. Declared in C (not via
/// @_silgen_name) so it gets the correct C calling convention.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier);

#endif
