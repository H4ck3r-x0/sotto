<div align="center">

<img src="Sotto/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="120" alt="Sotto icon">

# Sotto

**Hold a key. Speak. Your words appear, anywhere.**

Push-to-talk dictation for macOS. Fully on-device.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![On-device](https://img.shields.io/badge/speech-100%25%20on--device-FF4D6E)
![License](https://img.shields.io/badge/license-MIT-8A8F98)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hud-dark.png">
  <img src="docs/assets/hud-light.png" width="720" alt="Sotto's frosted-glass HUD showing a live transcript">
</picture>

</div>

Hold the shortcut (default **Right ⌥**), speak, release. The transcript is cleaned up and typed into whatever app has focus.

- Transcription runs on Apple's on-device `SpeechAnalyzer`. No network code in the app.
- Pre-warmed pipeline: ~55 ms to start listening, ~20 MB of memory.
- Text is inserted by synthetic typing, so it works in web editors and terminals and never touches your clipboard.
- Record any shortcut in Settings: a modifier, an F-key, or a combo like ⌥Space.
- Removes filler words, fixes capitalization, and a personal dictionary keeps your jargon right.

## Building

```sh
brew install xcodegen
xcodegen
xcodebuild -project Sotto.xcodeproj -scheme Sotto -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/Sotto.app /Applications/
```

Requires macOS 26+ on Apple silicon. On first launch grant **Microphone** and **Accessibility**. Re-run `xcodegen` after adding or removing source files.

## Tips

- **Dictionary**: Settings → Dictation → Edit Dictionary…, one rule per line: `cloud code → Claude Code`.
- **Globe key switches language instead?** System Settings → Keyboard → "Press Globe key to: **Do Nothing**".
- **Debug log**: `defaults write app.sotto.Sotto debugLogging -bool YES`, then run the binary from a terminal.

Curious how it works? Read the [architecture notes](docs/ARCHITECTURE.md).

<div align="center">
<sub><a href="LICENSE">MIT License</a></sub>
</div>
