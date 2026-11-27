"""
Package a Nativ iOS build into an unsigned .ipa.

  python pack-ios.py <title> [--app-name Name] [--smoke]

Builds <out>/<Name>.app from a recompiled title and zips Payload/<Name>.app with the unix
permissions iOS expects (the executable 0755, everything else 0644). The bundle carries the
game data and the runtime's images; the iOS bootstrap in runtime/core/main.c turns them into
the command line and the fs/ layout.

  --smoke   no game data: the runtime alone, a ~40 MB ipa that boots and reports what it
            misses. The data of an installed Nativ build is reused from beside it.

Deflated: the bulk of a bundle is the game's own archive, which compresses ~1.3x.

Paths: <root> is this checkout (three levels up), <out> is $ATIV_IPA_OUT or <root>/dist.
"""
import json
import os
import shutil
import subprocess
import sys
import zipfile

TITLE = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else "PCSA00029"
SMOKE = "--smoke" in sys.argv          # no game data: the runtime alone, ~40 MB, for a cheap first boot
NAME = "NativUncharted" + ("-smoke" if SMOKE else "")
if "--app-name" in sys.argv:
    NAME = sys.argv[sys.argv.index("--app-name") + 1]

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
WORK = os.path.join(ROOT, "dump", "decrypted", TITLE)
OUT = os.path.join(WORK, "recomp")
DIST = os.environ.get("ATIV_IPA_OUT") or os.path.join(ROOT, "dist")
APP = os.path.join(DIST, NAME + ".app")
DATA = os.path.join(APP, "data")

BUNDLE_ID = "dev.nativ" + ("." + NAME.lower())
EXE = "game_host"

INFO_PLIST = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleDevelopmentRegion</key><string>en</string>
\t<key>CFBundleExecutable</key><string>{EXE}</string>
\t<key>CFBundleIdentifier</key><string>{BUNDLE_ID}</string>
\t<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
\t<key>CFBundleName</key><string>{NAME}</string>
\t<key>CFBundleDisplayName</key><string>{NAME}</string>
\t<key>CFBundlePackageType</key><string>APPL</string>
\t<key>CFBundleShortVersionString</key><string>0.1</string>
\t<key>CFBundleVersion</key><string>1</string>
\t<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
\t<key>LSRequiresIPhoneOS</key><true/>
\t<key>MinimumOSVersion</key><string>15.0</string>
\t<key>UIDeviceFamily</key><array><integer>1</integer></array>
\t<key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
\t<key>UILaunchScreen</key><dict/>
\t<key>UIStatusBarHidden</key><true/>
\t<key>UIViewControllerBasedStatusBarAppearance</key><false/>
\t<key>UISupportedInterfaceOrientations</key>
\t<array>
\t\t<string>UIInterfaceOrientationLandscapeLeft</string>
\t\t<string>UIInterfaceOrientationLandscapeRight</string>
\t</array>
\t<key>UIFileSharingEnabled</key><true/>
\t<key>CADisableMinimumFrameDurationOnPhone</key><true/>
\t<key>LSSupportsOpeningDocumentsInPlace</key><true/>
\t<key>UIRequiresFullScreen</key><true/>
</dict>
</plist>
"""


def run(*a):
    print("  ", " ".join(a))
    r = subprocess.run(a)
    # robocopy: 0-7 are success (1 = files copied), 8+ are failures
    if r.returncode and not (a[0].lower() == "robocopy" and r.returncode < 8):
        sys.exit(f"{a[0]} failed: {r.returncode}")


def main():
    if not os.path.isdir(OUT):
        sys.exit(f"no build at {OUT} (vitarecomp build {TITLE} first)")
    shutil.rmtree(APP, ignore_errors=True)
    os.makedirs(DATA)

    with open(os.path.join(WORK, "analysis", "eboot.data.json"), encoding="utf-8") as f:
        entry = "%x" % (json.load(f)["functions"]["module_start"] & ~1)

    # the runtime's images: the game's, and the firmware modules recompiled with it
    imgs = sorted(f for f in os.listdir(OUT) if f.endswith(".img"))
    mods = []
    for f in imgs:
        src = os.path.join(OUT, f)
        print(f"  {f} ({os.path.getsize(src) / 1e6:.1f} MB)")
        shutil.copy2(src, os.path.join(DATA, f))
        if f != "game.img":
            mods.append(f[:-4])

    with open(os.path.join(DATA, "entry.txt"), "w", newline="\n") as f:
        f.write(entry + "\n")
    with open(os.path.join(DATA, "modules.txt"), "w", newline="\n") as f:
        f.write(" ".join(mods) + "\n")

    shaders = os.path.join(ROOT, "packs", TITLE, "shaders.txt")
    if os.path.isfile(shaders):
        shutil.copy2(shaders, os.path.join(DATA, "shaders.txt"))

    # the pack's shipped save (savedata0: the bootstrap copies it into Documents on a fresh install)
    saved = os.path.join(ROOT, "packs", TITLE, "savedata")
    if os.path.isdir(saved):
        dst = os.path.join(DATA, "savedata0")
        os.makedirs(dst, exist_ok=True)
        shutil.copytree(saved, dst, dirs_exist_ok=True)
        print(f"  savedata -> data/savedata0 ({sum(os.path.getsize(os.path.join(a, f)) for a, _, fs2 in os.walk(saved) for f in fs2) / 1e3:.0f} KB)")

    with open(os.path.join(APP, "Info.plist"), "w", newline="\n", encoding="utf-8") as f:
        f.write(INFO_PLIST)

    shutil.copy2(os.path.join(OUT, EXE), os.path.join(APP, EXE))

    # the game's own copy (2.9 GB): robocopy, /MT for the many small files
    app0 = os.path.join(WORK, "app0")
    if SMOKE:
        os.makedirs(os.path.join(DATA, "app0"))
        print("  smoke: no game data, the runtime boots and logs what it misses")
    else:
        print(f"  app0 -> data/app0 ({sum(os.path.getsize(os.path.join(a, f)) for a, _, fs in os.walk(app0) for f in fs) / 1e9:.2f} GB)")
        run("robocopy", app0, os.path.join(DATA, "app0"), "/E", "/MT:16", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/R:1", "/W:1")

    ipa = os.path.join(DIST, NAME + "-unsigned.ipa")
    print(f"  zipping {ipa}")
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_STORED, allowZip64=True) as z:
        for dirpath, _, files in os.walk(APP):
            for fn in files:
                full = os.path.join(dirpath, fn)
                rel = os.path.join("Payload", NAME + ".app", os.path.relpath(full, APP)).replace(os.sep, "/")
                info = zipfile.ZipInfo.from_file(full, rel)
                mode = 0o100755 if fn == EXE else 0o100644
                info.external_attr = mode << 16
                info.compress_type = zipfile.ZIP_DEFLATED   # the game data is mostly uncompressed: ~1.3x back
                with open(full, "rb") as src, z.open(info, "w") as dst:
                    shutil.copyfileobj(src, dst, 1 << 20)

    print(f"OK {ipa}  {os.path.getsize(ipa) / 1e9:.2f} GB")


if __name__ == "__main__":
    main()
