---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/expect-change.md
id: expect-change-flow
app: fr.neimad.pry.demoapp
status: failed
duration: 2.0s
steps_total: 5
steps_passed: 3
failed_at_step: 4
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T01:29:35Z
finished_at: 2026-04-27T01:29:37Z
---

# Verdict — expect-change-flow

**Status: FAILED at step 4**

## Step 4 — `expect_change click { id: "verbose_toggle" } → DocumentListVM.verbose = true`

**Expected:** predicate holds within 1.0s
**Observed:** got false; before action: false

### AX tree context at failure

```yaml
- AXApplication label="DemoApp"
  - AXWindow id="SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<DemoApp.ContentView, SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<DemoApp.DocumentListVM>>>, SwiftUI._FlexFrameLayout>, SwiftUI._TaskModifier2>-1-AppWindow-1" label="DemoApp" frame=(407,121,900,450) focused=true
    - AXGroup frame=(407,121,900,450)
      - AXStaticText value="DemoApp" frame=(800,169,113,31)
      - AXTextField id="doc_name_field" value="" frame=(439,212,711,24)
      - AXButton id="new_doc_button" label="New Document" frame=(1158,212,117,24)
      - AXCheckBox id="verbose_toggle" label="Verbose" value="0" frame=(822,248,71,16)
      - AXStaticText value="Intensity" frame=(653,276,52,16)
      - AXSlider id="intensity_slider" value="0" frame=(713,276,300,16)
        - AXValueIndicator value="0" frame=(713,276,20,16)
    - AXButton frame=(415,129,16,16)
    - AXButton frame=(461,129,16,16)
      - AXGroup frame=(462,130,14,14)
        - AXGroup frame=(462,130,14,14)
    - AXButton frame=(438,129,16,16)
    - AXStaticText value="DemoApp" frame=(489,129,68,16)
  - AXMenuBar frame=(0,0,1680,30)
    - AXMenuBarItem label="Apple" frame=(10,0,34,30)
      - AXMenu frame=(0,1050,0,0)
        - AXMenuItem id="_aboutThisMacRequested:" label="About This Mac" frame=(0,1050,0,0)
        - AXMenuItem id="_systemInformationRequested:" label="System Information" frame=(0,1050,0,0)
        - AXMenuItem label="" frame=(0,1050,0,0) enabled=false
        - AXMenuItem id="_systemSettingsRequested:" label="System Settings…, 1 update" frame=(0,1050,0,0)
        - AXMenuItem id="_appStoreRequested:" label="App Store" frame=(0,1050,0,0)
        - AXMenuItem label="" frame=(0,1050,0,0) enabled=false
    - AXMenuBarItem label="DemoApp" frame=(44,0,84,30)
      - AXMenu frame=(0,1050,0,0)
        - AXMenuItem id="orderFrontStandardAboutPanel:" label="About DemoApp" frame=(0,1050,0,0)
        - AXMenuItem label="" frame=(0,1050,0,0) enabled=false
        - AXMenuItem label="Services" frame=(0,1050,0,0)
        - AXMenuItem label="" frame=(0,1050,0,0) enabled=false
        - AXMenuItem id="hide:" label="Hide DemoApp" frame=(0,1050,0,0)
        - AXMenuItem id="hideOtherApplications:" label="Hide Others" frame=(0,1050,0,0)
    - AXMenuBarItem label="File" frame=(128,0,42,30)
      - AXMenu frame=(0,1050,0,0)
        - AXMenuItem id="menuAction:" label="New DemoApp Window" frame=(0,1050,0,0)
        - AXMenuItem label="" frame=(0,1050,0,0) enabled=false
        - AXMenuItem label="" frame=(0,1050,0,0) enabled=false
        - AXMenuItem id="performClose:" label="Close" frame=(0,1050,0,0)
        - AXMenuItem id="closeAll:" label="Close All" frame=(0,1050,0,0)
    - AXMenuBarItem label="Edit" frame=(170,0,44,30)
      - AXMenu frame=(0,1050,0,0)
        - AXMenuItem id="undo:" label="Undo" frame=(0,1050,0,0) enabled=false
        - AXMenuItem id="redo:" label="Redo" frame=(0,1050,0,0) enabled=false
        - AXMenuItem label="" frame=(0,1050,0,0) enabled=false
        - AXMenuItem id="cut:" label="Cut" frame=(0,1050,0,0) enabled=false
        - AXMenuItem id="copy:" label="Copy" frame=(0,1050,0,0) enabled=false
        - AXMenuItem id="paste:" label="Paste" frame=(0,1050,0,0) enabled=false
    - AXMenuBarItem label="View" frame=(214,0,50,30)
      - AXMenu frame=(0,1050,0,0)
        - AXMenuItem id="toggleTabBar:" label="Show Tab Bar" frame=(0,1050,0,0)
        - AXMenuItem id="toggleTabOverview:" label="Show All Tabs" frame=(0,1050,0,0)
        - AXMenuItem label="" frame=(0,1050,0,0) enabled=false
        - AXMenuItem id="toggleFullScreen:" label="Enter Full Screen" frame=(0,1050,0,0)
    - AXMenuBarItem label="Window" frame=(264,0,69,30)
      - AXMenu frame=(0,1050,0,0)
        - AXMenuItem id="performMiniaturize:" label="Minimize" frame=(0,1050,0,0)
        - AXMenuItem id="miniaturizeAll:" label="Minimize All" frame=(0,1050,0,0)
        - AXMenuItem id="performZoom:" label="Zoom" frame=(0,1050,0,0)
        - AXMenuItem id="zoomAll:" label="Zoom All" frame=(0,1050,0,0)
        - AXMenuItem id="_zoomFill:" label="Fill" frame=(0,1050,0,0)
        - AXMenuItem id="_zoomCenter:" label="Center" frame=(0,1050,0,0)

```

### Attachments

- `/Users/Dom/Projects/NeimadWorks/pry/Sources/PryRunner/pry-verdicts/expect-change-flow-20260427T012935Z/step-4-failure.png`


## Preceding steps

- ✅ Step 1 — `launch` (211ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (100ms)
- ✅ Step 3 — `expect_change click { id: "new_doc_button" } → DocumentListVM.documents.count = 1` (283ms)
- ❌ Step 4 — `expect_change click { id: "verbose_toggle" } → DocumentListVM.verbose = true` (1.2s) — expected predicate holds within 1.0s; observed got false; before action: false
- ⏭ Step 5 — `terminate` (0ms)
