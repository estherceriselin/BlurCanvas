# Blur Canvas — Lightroom Classic Plugin

A Lightroom Classic export filter that centers your photo on a blurred-background canvas at any size you choose. Built for social-media exports where you want the full image visible inside a fixed aspect ratio (Instagram feed, Reels, etc.) without solid letterboxing. 

The blurred background is generated from the photo itself (or an external image), centered, and composited behind the original at the chosen canvas size.

---

## Download & Install

1. Go to the **[Releases page](../../releases)** and download the latest `BlurCanvas.zip`
2. Unzip it — you'll get a folder called `BlurCanvas.lrplugin`
3. Put that folder somewhere stable (e.g. `~/Pictures/` or `~/Documents/Lightroom Plugins/`)
4. In Lightroom Classic: **File → Plug-in Manager → Add**
5. Select the `BlurCanvas.lrplugin` folder and click **Add Plug-in**
6. Status should read **Installed and running**

---

## Requirements

- **Lightroom Classic** (SDK 6.0+)
- **ImageMagick 7** — the `magick` binary
  - If you have **LR Mogrify 2**, its bundled `magick` binary works perfectly
  - Otherwise install via Homebrew: `brew install imagemagick`

---

## First-time setup

1. Open the Export dialog (**File → Export** or **Shift+Cmd+E**)
2. In the left panel under **Export Filters**, find **Blur Canvas** and click **Insert**
3. In the Blur Canvas section that appears, set the **magick path**:
   - Click **Choose...** and navigate to your `magick` binary
   - LR Mogrify 2 users: it's inside `LRMogrify2.lrplugin/LRMogrify.extras/magick`
   - Homebrew users: run `which magick` in Terminal to find the path
4. Save an export preset (**Add** at the bottom of the left panel) so you don't have to repeat this

---

## Settings

| Setting | Description |
|---|---|
| **Enable Blur Canvas** | Toggle the effect on/off without removing the filter |
| **Background** | Blurred version of the photo (default) or an external image file |
| **Canvas** | Output dimensions in pixels |
| **Swap W/H for landscape** | Automatically flips canvas dimensions for landscape-oriented photos |
| **Blur radius** | How soft the background blur is — 30–60 recommended |
| **Darken BG** | Optionally darken the blurred background by a percentage |
| **magick path** | Path to the ImageMagick 7 `magick` binary |

---

## Common canvas sizes

| Format | Size |
|---|---|
| Instagram feed (4:5) | 2400 × 3000 |
| Instagram Reels (9:16) | 1080 × 1920 |
| Square | 1080 × 1080 |

---

## Notes

- Place Blur Canvas **after** LR Mogrify 2 in the filter chain if you use both — disable LR Mogrify's own Canvas step to avoid conflicts
- The effect processes the exported file; your original in Lightroom is untouched
- Settings are saved per export preset

---

## License

MIT — see [LICENSE](LICENSE)
