# Workspace transition plan

## Feasibility boundary

macOS does not expose a supported API for replacing, retiming, or skinning the native Mission Control four-finger Space animation. A normal application cannot turn that system animation off, receive its interactive progress, or substitute compositor frames. Ryft should not claim otherwise.

The supported product scope is a Ryft-owned transition for desktop switches initiated by Ryft: workspace buttons, global keybinds, and Control+number actions. Native trackpad switching will keep Apple's animation. An experimental private-API compositor hook is explicitly out of scope because it would be fragile across macOS releases and unsuitable for a dependable utility.

## Intended experience

- Workspace buttons react immediately on press.
- A prewarmed borderless overlay appears on every affected display.
- The outgoing desktop snapshot moves in the selected direction while the incoming desktop is revealed.
- The real Space switch happens behind the overlay.
- The overlay is removed as soon as the destination Space is confirmed.
- Default duration target: 180 to 220 ms.
- Reduce Motion replaces translation with a 100 ms crossfade or no transition.
- If capture permission, a destination frame, or timing confirmation is unavailable, Ryft falls back to the native switch without delaying input.

## Architecture

### 1. WorkspaceTransitionCoordinator

A single coordinator owns the transition state machine:

1. `idle`
2. `capturingOutgoing`
3. `switching`
4. `waitingForDestination`
5. `animating`
6. `cleanup`

It receives `switch(from:to:direction:)` from `WorkspaceService`, coalesces repeated input, and never blocks the main thread.

### 2. Capture

Use ScreenCaptureKit where available. Request Screen Recording permission explicitly and explain why. Cache one downscaled frame per display and avoid retaining historical desktop contents. Do not save captures to disk.

A no-capture mode can animate an opaque wallpaper-backed layer, but it must be labeled as a simplified transition rather than pretending to represent the outgoing desktop.

### 3. Overlay windows

Create one prewarmed, input-transparent `NSPanel` per display:

- borderless and fully opaque during animation
- `ignoresMouseEvents = true`
- joins all Spaces and supports fullscreen auxiliary presentation
- contains a layer-backed or Metal-rendered transition surface
- is removed immediately after destination confirmation

The desktop bar and notch mask remain outside the animated content unless the user enables an explicit “animate overlays” option.

### 4. Rendering

Start with Core Animation because a two-texture translation does not require Metal. Move to Metal only if profiling shows frame misses at native Retina resolution.

Supported modes for the first release:

- Horizontal slide
- Fast crossfade
- Hyprland-style slide with a small scale and opacity change
- Instant

No spring or bounce. Timing should use a fast ease-out curve and stay under 220 ms.

### 5. Synchronization

`WorkspaceService` already polls the current managed Space every 50 ms and receives `activeSpaceDidChangeNotification`. The coordinator will use both:

- optimistic UI selection at input time
- destination confirmation from managed-space metadata
- a 500 ms hard timeout
- immediate cleanup if the switch fails

Repeated next/previous commands update the queued destination rather than spawning overlapping animations.

## Settings

Add a **Workspace transitions** section under General:

- Enable Ryft transitions
- Style: Slide, Hyprland slide, Fade, Instant
- Duration: 100 to 350 ms
- Animate direction from workspace order
- Animate bar and side panels
- Permission status and a Screen Recording button
- A real preview using captured sample frames, not decorative placeholders

## Performance requirements

- Overlay windows prewarmed at launch.
- No synchronous capture or image decoding on the main thread.
- First visible response within one display frame after a Ryft workspace command.
- 60 fps minimum, 120 fps on ProMotion where the system allows it.
- Peak temporary capture memory bounded to two frames per active display.
- No retained screenshots after cleanup.

## Validation

Test:

- single and multiple displays
- displays with different scale factors and arrangements
- fullscreen applications
- rapid repeated workspace commands
- failed Control+number mappings
- Reduce Motion
- missing and revoked Screen Recording permission
- sleep/wake and display hot-plugging
- animation cancellation when Ryft quits or the feature is disabled

## Acceptance boundary

Ryft can make its own workspace commands look different and feel immediate. It cannot safely alter the actual Apple four-finger Mission Control animation. Any future exploration of that exact system gesture must be clearly marked experimental and cannot be the default product path.
