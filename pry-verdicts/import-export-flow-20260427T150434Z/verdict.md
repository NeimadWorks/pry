---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/import-export.md
id: import-export-flow
app: fr.neimad.pry.demoapp
status: failed
duration: 11.0s
steps_total: 10
steps_passed: 6
failed_at_step: 6
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T15:04:34Z
finished_at: 2026-04-27T15:04:45Z
---

# Verdict — import-export-flow

**Status: FAILED at step 6**

## Step 6 — `wait_for (timeout 3.0s): DocumentListVM.lastImportedURL equals "/etc/hosts"`

**Expected:** predicate holds within 3.0s
**Observed:** got "/private/etc/hosts"

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
  - AXFunctionRowTopLevelElement frame=(0,0,1004,30)

```

### Attachments

- `/Users/Dom/Projects/NeimadWorks/pry/pry-verdicts/import-export-flow-20260427T150434Z/step-6-failure.png`


## Preceding steps

- ✅ Step 1 — `[setup] launch` (697ms)
- ✅ Step 2 — `[setup] wait_for (timeout 5.0s): window title_matches="DemoApp"` (66ms)
- ✅ Step 3 — `write_pasteboard "ignored"` (0ms)
- ✅ Step 4 — `click { id: "import_button" }` (211ms)
- ✅ Step 5 — `open_file "/etc/hosts"` (6.7s)
- ❌ Step 6 — `wait_for (timeout 3.0s): DocumentListVM.lastImportedURL equals "/etc/hosts"` (3.0s) — expected predicate holds within 3.0s; observed got "/private/etc/hosts"
- ⏭ Step 7 — `click { id: "export_button" }` (0ms)
- ⏭ Step 8 — `save_file "/tmp/pry-export-demo.txt"` (0ms)
- ⏭ Step 9 — `wait_for (timeout 3.0s): DocumentListVM.lastExportedURL equals "/tmp/pry-export-demo.txt"` (0ms)
- ✅ Step 10 — `[teardown] terminate` (53ms)
