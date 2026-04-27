---
id: clock-advance-flow
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "PryClock.advance fires scheduled work without waiting real time."
tags: [smoke, clock]
animations: off
timeout: 10s
---

# Clock advance flow

Demonstrates Wave 1 / ADR-007: the host VM uses `PryClock.after(...)` to schedule
work that would normally take 5 seconds of wall time. The runner advances the
virtual clock and asserts the scheduled callback fired.

```pry
launch
wait_for: { role: Window, title_matches: "DemoApp" }

assert_state: { viewmodel: DocumentListVM, path: "scheduledFiredCount", equals: 0 }
click: { id: "schedule_button" }

# Wait for the button action to land on main actor and register the work.
wait_for:
  state: { viewmodel: DocumentListVM, path: "scheduleRequestedCount", equals: 1 }
  timeout: 2s

# Without virtual time we'd have to wait 5 seconds. Instead we fast-forward.
clock.advance: 6s

wait_for:
  state: { viewmodel: DocumentListVM, path: "scheduledFiredCount", equals: 1 }
  timeout: 1s

assert_state: { viewmodel: DocumentListVM, path: "debounceMessage", equals: "Scheduled work fired!" }
terminate
```
