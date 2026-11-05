# LidTap

**Tap your MacBook lid.** LidTap turns the edges of your MacBook's display into buttons, with no extra
hardware. Tap a corner of the screen and it switches desktops, plays your music or hides everything
in a meeting.

It works by listening to the motion sensor inside your MacBook. A tap on the lid twists the laptop
slightly about its hinge; the sensor feels that twist about 800 times a second, and a small model
trained on *your* taps works out which part of the screen you tapped. Everything runs on your Mac:
no account, and your taps and settings never leave the machine. The only time LidTap goes online is to ask
GitHub whether a newer version is out (you can turn that off).

Made by [Yemcube (@yem.cube)](https://www.instagram.com/yem.cube).

- [What a tap can do](#what-a-tap-can-do)
- [Profiles: desk, lap, sofa](#profiles-desk-lap-sofa)
- [Install](#install)
- [Getting good taps](#getting-good-taps)
- [Which Macs work](#which-macs-work)
- [License](#license)
- [For developers](#for-developers)

## What a tap can do

LidTap splits the display into zones: 2×2 by default, or 2×3 and 3×3. Each zone does one thing, and
you choose which.

| Action | What it does |
|---|---|
| **Desktop Left / Right** | Switch to the previous or next desktop (Space) |
| **Play / Pause, Next, Previous** | Control whatever is playing: Music, Spotify, YouTube |
| **Volume Up / Down, Mute Sound** | Change the volume one step, or mute it, just like the volume keys |
| **New Note** | Open a fresh note in Notes |
| **Open App** | Launch an app, or bring it to the front if it's already open |
| **Run Shortcut** | Run any of your Shortcuts: turn on a Focus, start a timer, message someone, anything Shortcuts can do |
| **Privacy Guard** | Mid-meeting and someone walks in? One tap mutes every microphone, turns your meeting camera off (Zoom, Teams, Webex, Google Meet) and hides the screen. Tap again or click to come back, with your mic restored exactly as it was |

The default 2×2 layout: top-left **Desktop Left**, top-right **Desktop Right**, bottom-left
**Play / Pause**, bottom-right **Privacy Guard**.

LidTap ignores the bumps that aren't taps: typing, clicking, scrolling, moving the pointer, moving the
lid, and knocks on the desk.

## Profiles: desk, lap, sofa

A tap feels different on a desk, on your lap and on a sofa. Profiles let each place have its own
calibration, zone actions and sensitivity: say Desk switches desktops, and Sofa plays and pauses music.

LidTap starts with no profiles. To add one, open Settings → Profiles and click **Add Profile…**. Name it,
pick an icon, and either calibrate on the new surface (recommended, about two minutes) or start with a copy
of your current calibration. What you set up before is kept as **Default**, and you can rename it.

Once you have two or more, switch between them at the top of the LidTap menu, or press ⌘1 to ⌘9 while
the menu is open. Privacy Guard, feedback, sounds and update settings are shared by all profiles.

## Install

1. Download **LidTap-macOS.zip** from the [latest release](https://github.com/harsha20599/lidtap/releases/latest).
2. Unzip it, drag **LidTap.app** to Applications and open it. It's signed and notarized by Apple, so it
   opens like any other app.
3. A hand icon appears in the menu bar, and Settings opens.
4. Allow **Accessibility** when asked (System Settings → Privacy & Security → Accessibility). Desktop
   switching and music keys need it. **Input Monitoring** is optional: it lets LidTap tell typing from
   tapping more precisely.
5. Click **Calibrate**. Tap the dot in each highlighted zone a few times (about two minutes), then let it
   record 20 seconds of everyday bumps: typing, clicking, nudging the laptop. That's it.

**Updating:** from 1.0.2 on, LidTap updates itself. About once a day it checks GitHub for a new release and
asks before installing it; or click **Check Now** in Settings → General. It installs an update only if it's
signed by LidTap's developer, and keeps your calibration and settings. Turn off the daily check in Settings →
General. On 1.0.1 or earlier, download the new version once and replace the app in Applications. Coming from
1.0 or an unsigned build? Switch LidTap off and on again in the Accessibility list, once.

## Getting good taps

- **A quick, light flick** with a fingertip on the dot near each zone's corner. Never press hard: you
  don't need force, and pressing on a display can leave marks.
- **Wait for the screen to settle** between taps (about half a second).
- During calibration the meter says **Good tap**, **A little crisper** or **Gentler is fine**. Aim for green.
- Too many misreads? Settings → Training shows how reliable each zone is; **Calibrate Again** adds taps
  where they're needed.
- **Taps refused as "Too soft"?** A screen tap moves a larger, heavier MacBook less (a 16" MacBook Pro
  twists a half to a third as much as a 13" MacBook Air), so LidTap learns how hard taps land on *your* Mac
  from your calibration taps. To set the limit by hand, turn off **Learn tap strength from my taps** in
  Settings → Detection.

With crisp taps on a 2×2 grid, LidTap read 95% of taps correctly in our testing. Taps it isn't sure
about are ignored rather than guessed.

## Which Macs work

- An Apple Silicon MacBook **with the motion sensor**: MacBook Air or Pro with M2 or later, or the
  14"/16" MacBook Pro with M1 Pro or M1 Max.
- **Not** the M1 MacBook Air, the 13" M1 MacBook Pro, desktop Macs or Intel Macs: they have no motion sensor.
- macOS 14 Sonoma or later.

LidTap reads a sensor Apple doesn't document, so a future macOS update could change or break it.

## License

Free to use, change, tinker with and share under the [LidTap License](LICENSE): MIT, plus two rules.

1. **If you share anything built on LidTap publicly** (an app, a fork, a video or post showing your
   work), **credit "Based on LidTap by Yemcube"** with a link to Instagram
   [@yem.cube](https://www.instagram.com/yem.cube). Private use needs no credit.
2. **Commercial use needs approval first.** Selling it, putting it in a paid product or service, or
   using it in a company's products or advertising: message [@yem.cube](https://www.instagram.com/yem.cube)
   on Instagram.

LidTap is not affiliated with or endorsed by Apple.

---

# For developers

| Folder | What's in it |
|---|---|
| [`LidTapApp/`](LidTapApp) | The macOS menu bar app (Swift, SwiftUI) and its tests. Start with its [README](LidTapApp/README.md) |
| [`lidtap/`](lidtap), [`PROTOTYPE.md`](PROTOTYPE.md) | The original Python prototype: a browser GUI with live sensor traces, calibration and model comparison |
| [`LidTap.md`](LidTap.md) | How the detection and recognition work, end to end |
| [`reports/`](reports), [`research_notes/`](research_notes) | The research behind the approach: sensor access, prior art, signal processing and ML |
| [`tools/imu_probe.py`](tools/imu_probe.py) | A minimal probe that reads the motion and lid-angle sensors |

**Build the app** (needs the Xcode Command Line Tools):

```bash
LidTapApp/scripts/build.sh
```

It compiles with `swiftc`, assembles `LidTapApp/build/LidTap.app`, signs it ad hoc with the Hardened Runtime and
installs it to `~/Applications`. `--no-install` skips the install.

**Make a release** signed with a Developer ID and notarized by Apple (the setup steps are at the top of the script):

```bash
LidTapApp/scripts/release.sh
```

Bump `CFBundleShortVersionString` in `LidTapApp/Resources/Info.plist` first, then publish a GitHub release tagged
`v<version>` with `LidTap-macOS.zip` attached. Installed copies find it through GitHub's latest-release API
(drafts and pre-releases are ignored), show its notes, and install it only if it's newer and signed with the
same Developer ID (Team `23R7L2SQ34`).

**Run the tests:**

```bash
LidTapApp/scripts/test.sh
```

That runs the ML, detector, app-logic and UI suites with no side effects. The Python prototype has its own
hardware-free tests: `python -m unittest tests.test_prototype` from the repo root. `hardware`, `actions`,
`guard` and `e2e` suites drive the real system (switch Spaces, mute the mic, open apps), so run
them only when you aren't using the Mac.

**How it works, briefly:** the app reads the accelerometer and gyroscope through IOKit HID
(`AppleSPUHIDDevice`, ~800 Hz), high-pass filters the gyro, and triggers on an adaptive threshold.
Each tap becomes a 200 ms window and 70 features (shape, timing, axis ratios and a resampled template),
classified by a k-nearest-neighbours, logistic-regression or nearest-centroid model, whichever
cross-validates best on your own data. Taps far from anything it has learned, or below its confidence
floor, are rejected. Credit for the sensor work goes to [yamete](https://github.com/chipcolate/yamete),
[apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) and
[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor); see `reports/` for the full list.
