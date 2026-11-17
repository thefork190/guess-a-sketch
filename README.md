# Guess a Sketch

Prototype 2 is a small macOS 27 SwiftUI drawing game. Press **Start round** for 60 seconds of drawing with a mouse or trackpad. Apple’s on-device model guesses automatically about every four seconds when the nonempty canvas has changed. A match ends the round early; otherwise drawing stops at the deadline. The latest four guesses include inference latency. Undo, Clear, New round, and five ink swatches are available; black is the default.

Choose **Debug → No Timer (next round)** for unlimited drawing time. This option is off by default and applies only when starting a new round. The active round displays **No Timer** and still ends on a match.

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

- `Drawing` stores normalized stroke points and a color per stroke, including single-point marks. AppKit draws these directly; the same renderer produces an opaque 600 × 600 bitmap. No window capture or screenshot API is used, so prompt labels and controls cannot enter the image.
- `SketchGuesser` accepts only a `CGImage`. Swap the implementation through `DrawingRound(guesser:prompt:now:)` to test or replace inference.
- `AppleSketchGuesser` explicitly uses `SystemLanguageModel.default` with a fresh `LanguageModelSession` for every request, a fixed instruction, and `Attachment(image)`. There are no model tools, prompt candidates, previous guesses, network clients, cloud fallback, or drawing persistence.
- Matching runs afterward against the local prompt and a small alias list. It ignores case, punctuation and a leading article, but deliberately avoids substring matching. Semantically valid guesses outside those aliases can be marked incorrect.
- Drawing can continue during inference. The snapshot’s guess stays in history even if more ink has been added. Only one actual request is allowed in flight, including across resets: cancellation does not free the slot until the old call returns. A round generation token discards stale successes and errors.
- A monotonic deadline is checked both on timer ticks and on response arrival, so a late match cannot win after time expires. App suspension does not pause a timed round. Untimed rounds omit only this deadline.
- Requests have a minimum four-second start interval and require a nonempty drawing different from the last submitted snapshot. Failed requests require a canvas edit before retrying. Reset clears history and defaults ink to black; unavailable Apple Intelligence and model errors remain visible.
- No manual Guess button, hints, OCR, cloud inference, Metal code or game engine. The V1 model instruction and Swift matching/aliases are unchanged.

## API verification

Verified against Xcode 27.0 (27A266a), macOS SDK 27.0, on macOS 27.0.1 (26A434). The installed `FoundationModels.swiftinterface` declares the macOS 27 `Attachment` initializer taking `CGImage`, `SystemLanguageModel.default.availability`, and `LanguageModelSession.respond` with a prompt builder. The adapter compiles directly against those declarations.

Apple's reference: [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting).

## Verification and manual checks

Automated tests use an injected clock and guesser, including a service that ignores cancellation. They cover cadence, changed/nonempty canvas gating, bounded history, one request across resets, late results at the deadline, early matches, availability/errors, timed versus untimed rounds, matching, undo/clear, and pixel-level bitmap orientation and color checks.

For a live check, start a round, draw in several colors, and keep drawing while a guess is pending. Verify the clock, history, early match and timeout states. Reset during inference to check that the previous answer does not appear in the new round. Toggle Debug → No Timer (next round), start a new round, and verify the No Timer label and continued automatic guessing.

The V1 live inference smoke test returned “Pizza slice”, matched, in 1.71 seconds. That is historical V1 evidence, not a V2 live inference result. Recognition quality is model-dependent.
