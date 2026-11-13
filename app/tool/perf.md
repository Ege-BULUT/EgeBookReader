# Performance limits

## A 10,000-book library

`test/perf_test.dart` builds 10,000 books (titles, authors, series, tags, lists, a highlight on every seventh book), writes them to disk with an empty file for each book, and times the library's own code. It fails above the limits at its top.

| step | what is timed | M1 Mac, ms | limit, ms |
|-|-|-|-|
| save | `Library.flush`: encode and write library.json (about 5 MB) | 85 | 1000 |
| load | `Library.load`: read, check 10,000 files, list books/ | 255 | 2500 |
| sort | `sortBooks`, all nine orders one after another (about 80 each) | 750 | 5000 |
| filter | state, two categories, a language, or favourite | 3 | 100 |
| search | fold every book's text once, then four searches | 85 | 1000 |
| sections | series sections plus the twelve category sections | 120 | 1500 |

Measured on 2026-11-13, `flutter test` (debug, JIT), best of three runs, other builds running at the same time. A release build runs this code about 2 to 4 times faster.

Fixed while measuring:

- Series sections were quadratic: 31 s for 10,000 books, now 12 ms.
- `sortKey` used `split('')` and `indexOf` for every letter. A table built once makes it 2.3 times faster, with the same keys.
- The first metadata pass called `changed()` for every book, so the shelf was sorted again after each one. It now shows the change every 25 books.

## Phone multiplier

As a rule of thumb, take the Mac numbers above as debug. A recent mid-range phone in release is about the same as these numbers. An old phone (4 Cortex-A53 cores, Android 8, 2 GB RAM) is 3 to 5 times slower than that, so a sort takes about 0.3 s there and a load about 1 s. The limits leave room for that. To measure the real multiplier, run the same test on the device: `tool/e2e.sh <device>` also runs `integration_test/perf_test.dart`, which prints `10,000 books, ms: {...}`. Divide by the Mac row.

## A big PDF, on the emulator

1. `python3 tool/big_pdf.py 2000 /tmp/big.pdf` makes a 2,000-page text PDF (12 MB).
2. `adb -s emulator-5554 push /tmp/big.pdf /sdcard/Download/`
3. In the app: Kitap ekle → Dosya seç → Download → big.pdf. It should be on the shelf with its cover within about 3 s.
4. Open it: the first page within 3 s. Drag the page bar to the end: page 2000 within 1 s. Turn 20 pages by tapping. Each one should curl smoothly.
5. Memory, before opening and after step 4: `adb shell dumpsys meminfo dev.egebulut.egebookreader | grep -E "TOTAL PSS|TOTAL:"`. It should stay under about 400 MB, and should not keep rising as pages are turned.
6. Jank: `adb logcat -d | grep -E "Skipped [0-9]+ frames"` should show nothing above about 30 frames.
7. Read aloud from page 1999 and stop. Close the book and reopen it: it opens at the same page.

## An old phone, on the emulator

1. Cold boot the AVD with less of everything, for example `emulator -avd unlucky_root -cores 2 -memory 2048 -no-snapshot-load`. Boot it normally again afterwards.
2. `tool/e2e.sh unlucky_root`: the suite must pass, and the printed perf numbers must stay under the limits.
3. Repeat the big-PDF steps above, and open a comic (CBZ) with 200 pages.
4. With a big library: run the perf test, then turn the screen and scroll the shelf quickly. Watch `adb logcat | grep -E "Skipped|lowmemorykiller|ANR"`.

Debug builds on an emulator are slower than a release build on a phone. Treat a pass there as a pass. A failure there needs a release build on a real old phone before it counts as a slowdown.
