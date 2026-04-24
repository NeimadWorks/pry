---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/new-document.md
id: new-document-flow
app: fr.neimad.pry.demoapp
status: failed
duration: 0.9s
steps_total: 11
steps_passed: 7
failed_at_step: 8
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-24T18:00:24Z
finished_at: 2026-04-24T18:00:25Z
---

# Verdict — new-document-flow

**Status: FAILED at step 8**

## Step 8 — `wait_for (timeout 2.0s): DocumentListVM.documents.count equals 3`

**Expected:** DocumentListVM.documents.count equals 3
**Observed:** got 2

### AX tree context at failure

```yaml
- AXApplication label="DemoApp"
  - AXWindow id="SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<DemoApp.ContentView, SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<DemoApp.DocumentListVM>>>, SwiftUI._FlexFrameLayout>, SwiftUI._TaskModifier2>-1-AppWindow-1" label="DemoApp" frame=(390,315,900,450) focused=true
    - AXGroup frame=(390,315,900,450)
      - AXStaticText value="DemoApp" frame=(784,363,113,31)
      - AXTextField id="doc_name_field" value="" frame=(422,406,711,24)
      - AXButton id="new_doc_button" label="New Document" frame=(1141,406,117,24)
      - AXCheckBox id="verbose_toggle" label="Verbose" value="0" frame=(804,442,71,16)
      - AXButton id="tap_zone" label="Tap zone (0)" frame=(422,470,836,32)
      - AXScrollArea frame=(406,514,868,210)
        - AXOutline id="doc_list" frame=(406,514,868,210)
    - AXButton frame=(398,323,16,16)
    - AXButton frame=(444,323,16,16)
      - AXGroup frame=(445,324,14,14)
        - AXGroup frame=(445,324,14,14)
    - AXButton frame=(421,323,16,16)
    - AXStaticText value="DemoApp" frame=(472,323,68,16)
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

### Registered state at failure

```yaml
DocumentListVM:
  clickCount: 3
  documents.count: 3
  draftName: ""
  verbose: false
  zoneTapCount: 0

```

### Attachments

- `/Users/Dom/Projects/NeimadWorks/pry/pry-verdicts/new-document-flow-20260424T180024Z/step-8-failure.png`


## Preceding steps

- ✅ Step 1 — `launch` (274ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (116ms)
- ✅ Step 3 — `assert_state DocumentListVM.documents.count equals 0` (0ms)
- ✅ Step 4 — `assert_state DocumentListVM.clickCount equals 0` (0ms)
- ✅ Step 5 — `click { id: "new_doc_button" }` (206ms)
- ✅ Step 6 — `click { id: "new_doc_button" }` (76ms)
- ✅ Step 7 — `click { id: "new_doc_button" }` (59ms)
- ❌ Step 8 — `wait_for (timeout 2.0s): DocumentListVM.documents.count equals 3` (0ms) — expected DocumentListVM.documents.count equals 3; observed got 2
- ⏭ Step 9 — `assert_state DocumentListVM.clickCount equals 3` (0ms)
- ⏭ Step 10 — `assert_tree: contains { role: AXButton, label: "New Document" }` (0ms)
- ⏭ Step 11 — `terminate` (0ms)
