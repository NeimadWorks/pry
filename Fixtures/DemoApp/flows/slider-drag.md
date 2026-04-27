---
id: slider-drag-flow
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "Drag the intensity slider and verify the bound Double moves."
tags: [smoke, drag]
timeout: 15s
---

# Slider drag flow

Real CGEvent drag from one end of the slider to the other. Spec proves:

- `drag: { from, to }` resolves both endpoints and posts a real drag.
- The bound `@Published var intensity: Double` updates as the OS routes the
  drag through SwiftUI.

```pry
launch
wait_for: { role: Window, title_matches: "DemoApp" }
assert_state: { viewmodel: DocumentListVM, path: "intensity", equals: 0 }
drag: { from: { id: "intensity_slider" }, to: { id: "intensity_label" } }
wait_for: { state: { viewmodel: DocumentListVM, path: "intensity", any_of: [50, 60, 70, 80, 90, 100] } }
  timeout: 2s
terminate
```

Note: we drag from the slider's center to the label's frame at the right end —
SwiftUI doesn't expose the thumb as its own AX element, so we pivot from track
center to the right neighbor whose frame is reliably to the right.
