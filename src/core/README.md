# Core and adapter boundary

The files in this directory are pure C++20. They do not include Foundation,
AppKit, ApplicationServices, or any other Objective-C++ API.

`DisplayGeometry::bounds` is expressed in one canonical physical coordinate
system. Its `x` and `y` values are allowed to be negative, so multi-display
layouts do not need a special case for displays placed left of or above the
primary display.

`DisplayState` converts between virtual canvas coordinates and that canonical
physical system. The platform adapter is responsible for converting native
screen coordinates into this system before constructing `DisplayGeometry`.

`WindowPool` remains the Objective-C++ adapter boundary. `ClientWindow` owns
one retained `AXUIElementRef`; its indexes only point to the owning
`shared_ptr` records and do not retain AX keys independently. The private
`_AXUIElementGetWindow` call is kept inside `WindowPool.mm`; a failed lookup
uses WID zero and the AX reference remains the fallback identity.
