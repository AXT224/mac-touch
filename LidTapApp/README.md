# LidTap for macOS

A menu bar app that turns gentle taps on your MacBook display into actions, using only the built-in
motion sensor. No touch hardware, camera or mirror.

## Build and install

```bash
scripts/build.sh
```

Compiles with `swiftc`, assembles `build/LidTap.app` with its icon, signs it ad hoc and installs it to
`~/Applications/LidTap.app`. `--no-install` skips the install. The script works around a broken
Command Line Tools 26.1 install (a stray `module.modulemap`) with a VFS overlay; it touches no system files.

## Zone actions

Desktop Left / Right · New Note · Play/Pause · Next / Previous Track · Volume Up / Down · Mute Sound ·
Open App (launch or bring to front) · Run Shortcut ·
Privacy Guard.

**Privacy Guard** blurs every screen instantly, mutes every microphone at the system level (restored
exactly afterwards), and if a camera is in use, turns it off in Zoom, Microsoft Teams, Webex or
Google Meet (Chrome, Edge, Brave, Safari), then checks it actually stopped. Tap the zone again or click
anywhere to undo it all, including turning the camera back on.

## Permissions

- **Accessibility**: required for desktop switching, media keys, New Note and meeting camera control.
- **Input Monitoring**: some Macs need it before the motion sensor streams.
- **Automation**: asked the first time Privacy Guard looks for a Google Meet tab.

The build is ad-hoc signed, so after each rebuild macOS may need Accessibility switched off and on again.

## Layout

| Path | Role |
|---|---|
| `Sources/LidTap/Core/IMUReader.swift` | IOKit access to the IMU (~800 Hz) and lid-angle sensor |
| `Sources/LidTap/Core/TapDetector.swift` | High-pass, adaptive gyro trigger, 200 ms tap windows, input/lid gates |
| `Sources/LidTap/Core/Features.swift` | 70 tap features, identical to the Python prototype |
| `Sources/LidTap/Core/Classifiers.swift`, `ZoneModel.swift` | Logistic regression, kNN, nearest centroid; cross-validation; open-set rejection |
| `Sources/LidTap/Core/Store.swift` | Config and dataset in `~/Library/Application Support/LidTap` |
| `Sources/LidTap/Actions/` | Zone actions, key/media events, Privacy Guard, meeting camera control |
| `Sources/LidTap/UI/` | Menu bar panel, Settings, full-screen calibration, on-screen tap feedback |
| `Sources/LidTap/App/` | App entry, central model |
