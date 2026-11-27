"""
Package a Golden Abyss for iOS build into an unsigned .ipa.

  python pack-ios.py <title> [--app-name Name] [--smoke]

Builds <out>/GoldenAbyss.app from a recompiled title and zips Payload/GoldenAbyss.app with the unix permissions
iOS expects (the executable 0755, everything else 0644). The bundle carries the game data, the runtime's images
and the app icon: the game's own, sce_sys/icon0.png out of your copy, as pipeline/steam.py takes a game's art for a
Steam shortcut (--icon <png> takes another, and the drawn set in AppIcon/ is the fallback a smoke build uses).

  --smoke   no game data: the runtime alone, a ~40 MB ipa that boots and reports what it misses. The data of an
            installed Golden Abyss build is reused from beside it, and the bundle id gets a .smoke suffix so it
            installs beside the real one instead of replacing it.

Deflated: the bulk of a bundle is the game's own archive, which compresses ~1.3x.

Paths: <root> is this checkout (three levels up), <out> is $ATIV_IPA_OUT or <root>/dist.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icons   # (beside this script: the icon set, from the game's own art or the drawn fallback)

TITLE = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else "PCSA00029"
SMOKE = "--smoke" in sys.argv          # no game data: the runtime alone, ~40 MB, for a cheap first boot
NAME = "GoldenAbyss" + ("-smoke" if SMOKE else "")
if "--app-name" in sys.argv:
    NAME = sys.argv[sys.argv.index("--app-name") + 1]

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
WORK = os.path.join(ROOT, "dump", "decrypted", TITLE)
OUT = os.path.join(WORK, "recomp")
DIST = os.environ.get("ATIV_IPA_OUT") or os.path.join(ROOT, "dist")
APP = os.path.join(DIST, NAME + ".app")
DATA = os.path.join(APP, "data")
ICONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon")

BUNDLE_ID = "net.nikolan.goldenabyss" + (".smoke" if SMOKE else "")
if NAME != "GoldenAbyss" + ("-smoke" if SMOKE else ""):
    # a test build (--app-name) gets its own identifier, so it installs beside the real app instead of replacing it
    BUNDLE_ID += "." + re.sub(r"[^a-z0-9]+", "-", NAME.lower()).strip("-")
DISPLAY_NAME = "Golden Abyss"
EXE = "game_host"

# the names icons.py writes; iOS looks them up by point size and picks the file for the screen
ICON_FILES = ["Icon-20", "Icon-29", "Icon-40", "Icon-60"]
ICON_PLIST = "".join(f"\t\t<string>{n}</string>\n" for n in ICON_FILES)

INFO_PLIST = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleDevelopmentRegion</key><string>en</string>
\t<key>CFBundleExecutable</key><string>{EXE}</string>
\t<key>CFBundleIdentifier</key><string>{BUNDLE_ID}</string>
\t<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
\t<key>CFBundleName</key><string>{NAME}</string>
\t<key>CFBundleDisplayName</key><string>{DISPLAY_NAME}</string>
\t<key>CFBundlePackageType</key><string>APPL</string>
\t<key>CFBundleShortVersionString</key><string>0.1</string>
\t<key>CFBundleVersion</key><string>1</string>
\t<key>CFBundleIconFiles</key>
\t<array>
{ICON_PLIST}\t</array>
\t<key>CFBundleIcons</key>
\t<dict>
\t\t<key>CFBundlePrimaryIcon</key>
\t\t<dict>
\t\t\t<key>CFBundleIconFiles</key>
\t\t<array>
{ICON_PLIST}\t\t\t</array>
\t\t</dict>
\t</dict>
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

    with open(os.path.join(APP, "Info.plist"), "w", newline="\n", encoding="utf-8") as f:
        f.write(INFO_PLIST)

    # the icon: the game's own (sce_sys/icon0.png, out of the player's copy -- nothing of it is in this repository),
    # another with --icon, else the drawn set; every size, beside the executable where iOS reads them
    game_icon = os.path.join(WORK, "app0", "sce_sys", "icon0.png")
    icon_src = sys.argv[sys.argv.index("--icon") + 1] if "--icon" in sys.argv else (game_icon if os.path.isfile(game_icon) else "")
    if icon_src:
        print(f"  icon <- {icon_src}")
        icons.from_image(icon_src, APP)
    elif os.path.isdir(ICONS):
        for png in sorted(os.listdir(ICONS)):
            if png.endswith(".png"):
                shutil.copy2(os.path.join(ICONS, png), os.path.join(APP, png))
    else:
        sys.exit(f"no app icon: no {game_icon} in your copy, and no drawn set at {ICONS}")

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
