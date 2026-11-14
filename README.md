# Guess a Sketch

A small macOS 27 SwiftUI prototype. Draw with a mouse or trackpad, undo a stroke, clear the canvas, or choose a new secret prompt. Press **Guess** to ask Apple's on-device model what the drawing depicts. The result includes a local match verdict and elapsed inference time (including session/request overhead, excluding bitmap rendering).

## Build and run

Requires Xcode 27 with the macOS 27 SDK and Swift 6.2 or newer. On-device inference also requires an Apple Intelligence-capable Mac, Apple Intelligence enabled, and the model downloaded.

```sh
zsh scripts/build-app.sh
open '.build/Guess a Sketch.app'
```

Open `Package.swift` in Xcode to develop. The build script keeps artifacts and module caches inside `.build`, makes a local app bundle, and ad-hoc signs it. It does not install, publish, or provision the app. SwiftPM's build-process sandbox is disabled for compatibility with an already restricted execution environment; this does not request broader filesystem permissions.

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security
```

## Data boundary and implementation

- `Drawing` stores normalized stroke points. AppKit draws these directly; the same renderer produces an opaque 600 × 600 bitmap. No window capture or screenshot API is used, so prompt labels and controls cannot enter the image.
- `SketchGuesser` accepts only a `CGImage`. Swap the implementation through `GameView(guesser:)` to test or replace inference.
- `AppleSketchGuesser` explicitly uses `SystemLanguageModel.default` with a fresh `LanguageModelSession` for every manual request, a fixed instruction, and `Attachment(image)`. There are no model tools, prompt candidates, previous guesses, network clients, cloud fallback, or drawing persistence.
- Matching runs afterward against the local prompt and a small alias list. It ignores case, punctuation and a leading article, but deliberately avoids substring matching. Semantically valid guesses outside those aliases can be marked incorrect.
- Drawing and round changes are disabled during inference. Editing the drawing invalidates its previous result. Unavailable Apple Intelligence and thrown model errors remain visible; availability can be refreshed without restarting.
- No automatic guesses, hints, Metal code or game engine.

## API verification

Verified against Xcode 27.0 (27A266a), macOS SDK 27.0, on macOS 27.0.1 (26A434). The installed `FoundationModels.swiftinterface` declares the macOS 27 `Attachment` initializer taking `CGImage`, `SystemLanguageModel.default.availability`, and `LanguageModelSession.respond` with a prompt builder. The adapter compiles directly against those declarations.

Apple's reference: [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting).

## Manual acceptance check

1. Drag and click on the canvas; verify continuous strokes and dots. Undo removes the latest stroke; Clear removes all.
2. Hide/reveal the prompt. New prompt changes the target and clears the drawing. Empty canvases cannot be submitted.
3. Draw the target and press Guess. Check the single guess, match verdict and latency. Edit the drawing and verify the old result disappears.
4. While guessing, ensure draw/undo/clear/new prompt/Guess are disabled.
5. With Apple Intelligence unavailable, drawing should still work, a reason should appear, and Retry availability should recheck readiness.

Automated tests cover matching, undo/clear, bitmap dimensions, background opacity and orientation. Recognition quality is model-dependent and is not asserted by unit tests.

## Verified prototype run

- `swift build` and the app packaging/ad-hoc signing script succeeded on the environment above.
- `swift test`: all 3 Swift Testing tests passed.
- Launched the packaged app and drew a triangular pizza slice with crust and dots using mouse input. Pressing Guess returned **Pizza slice**, **Match!**, **1.71 s** using the on-device adapter.
- Verified Undo invalidates the result, Hide changes the prompt to Hidden, and Clear/New prompt leave an empty canvas with Guess disabled and a different visible prompt.
- Unavailable-model and thrown-error branches compile but were not forced during this live run; Apple Intelligence was available. No system settings were changed.
