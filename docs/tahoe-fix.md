# macOS Tahoe crash fix

Two independent crashes, both triggered on the first hotkey press. Neither existed on earlier macOS versions.

---

## Crash 1 — infinite recursion in `TopAnchoredPanel.setFrame`

**Symptom:** `EXC_BAD_ACCESS / SIGSEGV` — "Thread stack size exceeded due to excessive recursion" — 6585 frames deep, immediately on hotkey press. Widget never appeared.

**Root cause:**

`TopAnchoredPanel` overrides `setFrame(_:display:)` to pin the top edge and centre the panel horizontally, then calls `super.setFrame`. On macOS Tahoe, `NSHostingView.windowDidLayout()` now calls `updateAnimatedWindowSize(_:)` synchronously from within the layout pass that `super.setFrame` itself triggers. That calls `setFrame` again, which calls `super.setFrame`, which triggers layout, and so on.

Full cycle (collapsed):
```
hotkey press
→ state = .recording
→ FloatingPanelController.showPanel()
→ NSAnimationContext.runAnimationGroup { panel.animator().alphaValue = 1 }
  → NSHostingView.layout()
    → NSHostingView.updateAnimatedWindowSize(_:)
      → TopAnchoredPanel.setFrame  [call 1 — isSettingFrame = false → enters override]
        → super.setFrame
          → NSWindow._setFrameCommon → layout subtree
            → NSHostingView.windowDidLayout()
              → NSHostingView.updateAnimatedWindowSize(_:)
                → TopAnchoredPanel.setFrame  [call 2 — re-entrant]
                  → super.setFrame → layout → ... × 6585
```

This behaviour changed in Tahoe — earlier AppKit did not call `updateAnimatedWindowSize` from within a layout triggered by `setFrame`.

**Fix — `Sources/IntelliWhisper/UI/FloatingPanelController.swift`:**

Added `private var isSettingFrame = false` to `TopAnchoredPanel`. Split the single guard into two separate guards so that:
- Non-visible windows still pass through to `super.setFrame` unchanged.
- Re-entrant calls on visible windows **return immediately without calling `super`**. Calling `super` in the re-entrant case also triggers layout and continues the loop; a silent return is the only way to break the cycle.

```diff
+    private var isSettingFrame = false

     override func setFrame(_ frameRect: NSRect, display flag: Bool) {
+        // Non-visible windows: pass straight through, no position pinning needed.
         guard isVisible else {
             super.setFrame(frameRect, display: flag)
             return
         }
+        // Re-entrancy guard: on macOS Tahoe, NSHostingView.windowDidLayout() calls
+        // setFrame from within the layout pass triggered by our own super.setFrame call.
+        // Calling super again here would trigger another layout → infinite recursion.
+        // Drop the re-entrant call entirely; the frame from the first call is sufficient.
+        guard !isSettingFrame else { return }
+        isSettingFrame = true
+        defer { isSettingFrame = false }
         var rect = frameRect
```

---

## Crash 2 — `Bundle.module` fatalError + Downloads folder permission dialog

**Symptom:** After crash 1 was fixed, the widget appeared briefly then hit `EXC_BREAKPOINT / SIGTRAP` from `Swift.fatalError` inside the auto-generated `resource_bundle_accessor.swift`. macOS also showed a privacy dialog: _"IntelliWhisper Core möchte Zugriff auf Dateien in deinem Ordner „Downloads"."_

**Root cause:**

Swift Package Manager auto-generates `resource_bundle_accessor.swift` at build time. For this project it looks like:

```swift
extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL
            .appendingPathComponent("IntelliWhisper_IntelliWhisper.bundle").path
        let buildPath = "/Users/lenasara/Downloads/intelliwhisper/.build/…/IntelliWhisper_IntelliWhisper.bundle"

        guard let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath) else {
            Swift.fatalError("could not load resource bundle: …")
        }
        return bundle
    }()
}
```

Two problems:

1. **Wrong lookup path for installed app.** `Bundle.main.bundleURL` is the `.app` package root (`IntelliWhisper Core.app/`). The accessor looks for the bundle there, but the build script places it inside `Contents/Resources/`. So `mainPath` always misses.

2. **Hardcoded build-machine path as fallback.** When `mainPath` fails the accessor tries `buildPath`, which is the absolute path to the build directory on the developer's machine — inside `~/Downloads/intelliwhisper/`. On any other machine (or after reinstall) that path does not exist. macOS Tahoe detects the attempt to access `~/Downloads` and shows a privacy prompt. Whether the user grants or denies, the bundle is not found and `fatalError` fires.

`FormattingIcon` was the only caller of `Bundle.module`, accessing it to load `ollama@2x.png`.

**Fix — `Sources/IntelliWhisper/UI/FloatingPanelView.swift`:**

Replaced the `Bundle.module` call in `FormattingIcon` with a direct lookup that works correctly for both installed app and development builds. `Bundle.module` is a `lazy static let` — it only runs when first accessed. Since `FormattingIcon` was the only caller, the generated accessor code now exists but is never invoked.

```diff
 private struct FormattingIcon: View {
+    private static let image: NSImage? = {
+        // Installed app: IntelliWhisper_IntelliWhisper.bundle is in Contents/Resources/
+        if let bundleURL = Bundle.main.url(forResource: "IntelliWhisper_IntelliWhisper", withExtension: "bundle"),
+           let rb = Bundle(url: bundleURL),
+           let url = rb.url(forResource: "ollama@2x", withExtension: "png") {
+            return NSImage(contentsOf: url)
+        }
+        // Development (swift build): bundle sits next to the binary
+        let devURL = Bundle.main.bundleURL
+            .appendingPathComponent("IntelliWhisper_IntelliWhisper.bundle")
+            .appendingPathComponent("ollama@2x.png")
+        return NSImage(contentsOf: devURL)
+    }()
+
     var body: some View {
-        if let url = Bundle.module.url(forResource: "ollama@2x", withExtension: "png"),
-           let nsImage = NSImage(contentsOf: url) {
+        if let nsImage = Self.image {
             Image(nsImage: nsImage)
```

---

---

## Crash 3 — same recursion, second hotkey press, guard placed too late

**Symptom:** After crash 1 and 2 were fixed, the app worked exactly once then crashed again with the same SIGSEGV stack-overflow on every subsequent hotkey press. Crash frame: `TopAnchoredPanel.setFrame(_:display:) [FloatingPanelController.swift:234]` — the `!isVisible` path.

**Root cause:**

The re-entrancy guard was placed *after* the `isVisible` check:

```swift
guard isVisible else {
    super.setFrame(frameRect, display: flag)  // ← loops here when panel being re-shown
    return
}
guard !isSettingFrame else { return }         // ← never reached when !isVisible
```

On the **first** hotkey press the panel is created fresh; SwiftUI has not rendered it yet so `updateAnimatedWindowSize` does not fire during `orderFrontRegardless()`. On **every subsequent** press the panel already exists (dismissed via `orderOut`), so `isVisible = false`. Calling `orderFrontRegardless()` triggers `_setUpFirstResponderBeforeBecomingVisible → layoutIfNeeded → windowDidLayout → updateAnimatedWindowSize → setFrame`. The `!isVisible` guard fires, calls `super.setFrame` without ever setting `isSettingFrame`, which triggers another layout → `setFrame` → `super.setFrame` → infinite loop.

**Fix — `Sources/IntelliWhisper/UI/FloatingPanelController.swift`:**

Move `guard !isSettingFrame` to the very top of the override so it protects both the visible and non-visible code paths:

```diff
     override func setFrame(_ frameRect: NSRect, display flag: Bool) {
-        // Non-visible windows: pass straight through, no position pinning needed.
-        guard isVisible else {
-            super.setFrame(frameRect, display: flag)
-            return
-        }
-        guard !isSettingFrame else { return }
-        isSettingFrame = true
-        defer { isSettingFrame = false }
-        var rect = frameRect
+        guard !isSettingFrame else { return }
+        isSettingFrame = true
+        defer { isSettingFrame = false }
+        guard isVisible else {
+            super.setFrame(frameRect, display: flag)
+            return
+        }
+        var rect = frameRect
```

---

## Files changed

| File | Change |
|------|--------|
| `Sources/IntelliWhisper/UI/FloatingPanelController.swift` | Re-entrancy guard at top of `TopAnchoredPanel.setFrame` (covers both visible and non-visible paths) |
| `Sources/IntelliWhisper/UI/FloatingPanelView.swift` | `FormattingIcon` loads image without `Bundle.module` |
