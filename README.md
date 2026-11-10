# Decant

A lightweight, CrossOver-style launcher for running Windows games and apps on Apple Silicon Macs:
**Rosetta 2** (CPU) + **Wine** (Windows API) + a **DirectX → Metal** layer, managed as per-app "bottles".
**Decant.app** gives you a game library: open Steam, play Steam games, and add any Windows game or
installer you've downloaded. Apps that need Wine workarounds get them from **compatibility fix recipes**:
small data files, matched automatically when the app launches.

```
bin/decant              the CLI — all real logic lives here (bash 3.2, no deps)
fixes/                  per-app compatibility recipes (*.fix), e.g. steam.fix
integrations/           store plugins that list installed games (steam)
shim/                   source of decant-shim, the generic launch shim recipes use
share/                  prebuilt shims (decant-shim64.exe / decant-shim32.exe)
app/                    SwiftUI front end (calls the CLI, reads bottle.conf)
scripts/                build-wine.sh (build your own Wine; `decant setup --build-wine` runs it)
tests/                  run.sh (fast, fake Wine) and live.sh (real Wine)
docs/                   architecture, decision records, fix-writing guide
```

## Quick start

```bash
softwareupdate --install-rosetta --agree-to-license   # once
bin/decant setup --build-wine                          # Wine, DXMT, DXVK and the default bottle "games"
bin/decant install games steam                         # bottle "games", recipe "steam"
bin/decant run games Steam
```

`decant setup` is the recommended setup in one command ([ADR-0023](docs/adr/0023-recommended-setup-command.md)).
It installs only what's missing and never changes an existing bottle:
1. a prebuilt Wine Staging (~220 MB, Gcenx builds);
2. with `--build-wine`, CrossOver's open-source Wine 26.1.0 built locally (15-40 min, needs Xcode and
   Homebrew), which is what DXMT, D3DMetal and Decant's Wine patches need. Without it, games use DXVK;
3. the DXMT and DXVK graphics backends;
4. D3DMetal, only if you pass `--gptk <dir>` (see below);
5. a bottle named `games` with `BACKEND=auto`, Windows 10, msync and AVX on, set as the default bottle.

In the app, **Components → Set Up Recommended** does the same (without building Wine).

### D3DMetal (DirectX 12)
Apple's D3DMetal can't be redistributed. Download the Game Porting Toolkit from
developer.apple.com, mount the .dmg, then:

```bash
bin/decant backend install d3dmetal "/Volumes/Evaluation environment for Windows games 3.0"
bin/decant bottle set mygame METALFX=1    # optional; BACKEND=auto uses D3DMetal once imported
```
The GPTK download is a disk image that holds a second one ("Evaluation environment for Windows games
3.0.dmg"): mount that inner one. D3DMetal needs a CrossOver-based runtime (`yes` in `decant runtime list`).

## Which bottle should I use?

**One bottle for everything, set as the default.** With `BACKEND=auto` (the default) one CrossOver-based
runtime serves every API at once: D3DMetal (or DXMT without GPTK) for DirectX 10-12, Wine's wined3d
for DirectX 9 and older and OpenGL, and MoltenVK for Vulkan. It's decided at each launch from what's
installed, so there's nothing to set per game ([ADR-0019](docs/adr/0019-auto-backend-best-layer-per-api.md)). Make a second bottle
only for a game that needs different settings (another Wine version or graphics layer), or to try
something risky without touching your main one.

```bash
bin/decant bottle create games --default      # picks the best runtime + backend for you
bin/decant bottle default                     # which bottle is the default
```

On a Mac with the self-built CrossOver runtime that means DXMT + msync. With only the prebuilt runtime,
it means DXVK. In the app, the default bottle has a ★ and is where Add Game, Install Steam and new
installers go.

## Library

```bash
bin/decant library                            # every game in every bottle (Steam + your own)
bin/decant play steam steam:2784470           # launch a Steam game (via Steam)
bin/decant library add steam "My Game" ~/Downloads/MyGame/Game.exe
bin/decant play steam "manual:My Game"
bin/decant stop steam "manual:My Game"
```

In the app, **Library** shows the same list as a grid with Play/Stop. Use **Add Game…** for a downloaded
`.exe`: either the game itself, or an installer, after which it finds what was installed. **Open Steam**
(or **Install Steam**) is in the toolbar. Adding another store means adding an integration plugin
([docs/integrations.md](docs/integrations.md)).

> **Graphics:** the prebuilt Wine can't drive DXMT (its macOS driver has the symbols DXMT needs stripped),
> so bottles on it use **DXVK**. For DXMT (DirectX 10/11 → Metal directly, plus msync), build CrossOver's
> open-source Wine once. It takes about 10 minutes and needs no admin password:
> `scripts/build-wine.sh crossover 26.1.0`. New bottles then pick it automatically. `decant doctor` shows
> what each runtime supports. See [ADR-0011](docs/adr/0011-backend-by-runtime-capability.md) and
> [ADR-0012](docs/adr/0012-build-crossover-wine-with-prebuilt-x86-libs.md).

## "Access denied" or "needs administrator"?

Use **Run as Administrator**: the switch in **Add Game** (on by default for installers), the button in
bottle settings, or the library's right-click menu. From the command line:

```bash
bin/decant run --admin steam ~/Downloads/setup_mygame.exe
bin/decant repair steam            # fix read-only / wrongly-owned files in a bottle
```

This gives the installer Wine's **administrator token** (the same thing Windows' UAC prompt grants). It
also copies the installer into the bottle, away from macOS-protected folders and read-only disk images,
and clears read-only files. **Don't run Wine with `sudo`:** Wine has no permissions for root to
bypass, and root-owned files in a bottle *cause* "access denied" errors. If that has already happened,
**Repair Permissions** fixes it with one password prompt.
See [ADR-0013](docs/adr/0013-run-as-administrator-without-sudo.md).

## Is my setup stuck? Logs and diagnostics

```bash
bin/decant status steam               # working, waiting for you, or stopped (+ CPU and log freshness)
bin/decant logs steam --installer -f  # follow the installer's own log
bin/decant diagnostics steam          # zip of logs + settings + status on your Desktop, to attach anywhere
```

Inno Setup and MSI installers (GOG and most others) always write a detailed log; Decant adds the switch
automatically. In the app, the **Activity** panel (bottle settings, and the installer step of Add Game)
shows the same verdict live, with buttons to open the logs or export diagnostics. *Waiting for you*
usually means a dialog is open, possibly behind another window. See
[ADR-0014](docs/adr/0014-installer-logs-and-activity-status.md).

## Controllers

Xbox, PlayStation, Switch Pro and most other USB/Bluetooth pads work out of the box. Wine presents them
to games as Windows XInput/DirectInput controllers, through SDL2 (bundled in every runtime) or macOS's
HID layer. To check that one is detected:

```bash
bin/decant controllers games        # lists pads macOS sees, then opens Wine's Game Controllers panel
```

(app: bottle settings → **Game Controllers**). Pair Bluetooth pads in System Settings → Bluetooth first.
For Steam games, Steam Input can take over the controller. If a pad isn't seen in a Steam game, toggle
Steam Input in that game's Properties → Controller.

## Do I need to set up each game?

No. Settings live on the **bottle** (Wine version, graphics layer, performance switches), and every
game in that bottle gets them. 9 Kings needed nothing game-specific: the only fix was choosing a
graphics layer that works with the installed Wine, and Decant now does that automatically.

A **fix recipe** is only for the exception: an app that breaks under Wine in its own way (like Steam's
black windows). Recipes apply automatically, so you never configure them; they're written once and
shared, the same way CrossOver and Proton maintain per-game fixes. If a game doesn't start, the first
things to try are bottle-wide: the graphics layer, then the Wine version.

## Compatibility fixes

When an app needs a Wine workaround, it goes in a recipe, not in Decant's code. Decant applies every
recipe whose `MATCH` names the executable being launched:

```bash
bin/decant fix list                      # available recipes (built-in + yours)
bin/decant fix status steam              # which are on for a bottle
bin/decant fix disable steam steam       # turn one off (and undo its shims)
bin/decant fix check                     # lint recipes
```

Put your own recipes in `~/Library/Application Support/Decant/fixes/`. One with the same id as a
built-in recipe replaces it. The format, and a step-by-step method for diagnosing a broken app, are in
**[docs/fixes/README.md](docs/fixes/README.md)**. For a worked example, see [docs/fixes/steam.md](docs/fixes/steam.md).

## Performance knobs (per bottle: `decant bottle set <b> KEY=1`)

| Key | What it does |
|---|---|
| `BACKEND` | `auto` (default: best layer per API, see above) · `dxmt` (DX10/11, needs a DXMT-capable Wine) · `dxvk` (DX9-11, default on prebuilt Wine) · `d3dmetal` (DX12) · `wined3d` (fallback) |
| `MSYNC` | `WINEMSYNC=1`: Mach-semaphore sync. Big CPU win, but needs a CrossOver-patched Wine (`build-wine.sh crossover`); the stock Gcenx builds ignore it |
| `AVX` | `ROSETTA_ADVERTISE_AVX=1`: lets AVX2-requiring games start (macOS 15+) |
| `METALFX` | MetalFX upscaling: DXMT (spatial swapchain + NVAPI/DLSS path) and D3DMetal |
| `METAL_HUD` | `MTL_HUD_ENABLED=1`: FPS, frame time, GPU memory overlay |
| `RETINA` | native-resolution rendering (sharper, costs FPS) |
| `EXTRA_ENV` | any per-bottle env, e.g. `EXTRA_ENV="DXVK_HUD=fps WINEDEBUG=+loaddll"` |
| `FIXES_DISABLED` | space-separated recipe ids to skip in this bottle (`all` = none) |

The DXVK path also always sets the MoltenVK flags (`MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1`,
async queue submits, fast math), `DXVK_ASYNC=1`, and a per-bottle pipeline state cache.
DXMT bottles get a persistent per-bottle shader cache (`DXMT_SHADER_CACHE_PATH`).

## Documentation

| Doc | For |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the pieces fit: layers, on-disk layout, what `decant run` does |
| [docs/adr/](docs/adr/README.md) | Architecture Decision Records: why things are the way they are |
| [docs/fixes/README.md](docs/fixes/README.md) | Writing and debugging per-app fix recipes |
| [docs/integrations.md](docs/integrations.md) | Store-integration plugins (Steam, …) |
| [CHANGELOG.md](CHANGELOG.md) | What changed, per version |

## Limits
- Kernel-level anti-cheat (Vanguard, kernel-mode EAC/BattlEye) won't run.
- AVX-512 isn't available under Rosetta.
- Apple has said Rosetta will be cut back after macOS 27 to a subset kept for older games, so keep an eye on that.
- Wine is LGPL: if you ship a modified Wine, you must publish your changes.

## Licence
Decant is MIT-licensed ([LICENSE](LICENSE)). The Wine patches in `patches/` are LGPL-2.1-or-later, like
the Wine source they change ([patches/LICENSE](patches/LICENSE)). Decant isn't affiliated with Valve,
Apple, CodeWeavers or any game publisher. Use it to run software you're licensed to run.
