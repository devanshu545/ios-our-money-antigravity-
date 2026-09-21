# App Icon

Run `python3 OurMoney_iOS/tools/generate_icon.py` (or the plain-python equivalent) to render
`AppIcon1024.png` — the wallet logo in the OurMoney teal-on-dark-graphite brand — directly into
`OurMoney/Resources/Assets.xcassets/AppIcon.appiconset/`.

The script uses only the Python standard library and writes a valid PNG (no Pillow required).
The GitHub Actions workflow regenerates the icon automatically at build time, so the produced
IPA always contains a real 1024×1024 icon.
