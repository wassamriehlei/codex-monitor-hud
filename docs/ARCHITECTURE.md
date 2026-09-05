# Architecture

## 2.2 Windows process boundary

```text
Codex local files
       |
       v
CodexMonitorHud.Core (net10.0, platform-neutral)
       | parsing / discovery / incremental state / projections
       v
Windows WPF shell
compiled resident monitor
       |
       v
on-demand legacy Settings host (exact config/UI compatibility only)
```

The resident hot path is compiled C#. `CodexMonitorHud.Core` has no WPF, Windows Forms, registry, tray, or Win32 references. The Windows application is a separate `net10.0-windows` project. The full 2.1 Settings UI remains an on-demand compatibility adapter while the resident monitor and all live display surfaces use the compiled host. This split avoids making a risky settings rewrite a prerequisite for the performance migration and leaves an explicit `-Legacy` rollback.

## Scope

Codex Monitor HUD 3.4.0 is a local Windows projection over recent Codex Desktop, VS Code, and CLI session records. It combines the normal `CODEX_HOME` (`~/.codex` by default) with an optional isolated `~/.codex-deepseek` profile without reading either profile's provider configuration or authentication files. It does not maintain a historical database and does not modify Codex sessions.

```text
Codex local session JSONL + session_index.jsonl
                    |
                    v
        bounded discovery and incremental reader
                    |
                    v
             shared session-state table
          /          |          |          \
     summary       list      split      task registry
                                  \
                               quiet indicators
```

## Components

| Component | Responsibility |
| --- | --- |
| `src-dotnet/CodexMonitorHud.Core` | Platform-neutral configuration, bounded discovery, streaming JSONL parsing, identity, accounting, state transitions, pricing, and presentation rules. |
| `src-dotnet/CodexMonitorHud.App` | Compiled Windows lifecycle, WPF projections, tray, DPI/Win32 integration, bubbles, signals, and MCP notice inbox. |
| `tests-dotnet/CodexMonitorHud.Core.Tests` | Zero-dependency executable regression suite for neutral behavior. |
| `src/MonitorHud.Core.psm1` | Configuration normalization, bounded discovery, record parsing, accounting, themes, pricing, and pure helpers. |
| `src/CodexMonitorHUD.ps1` | On-demand exact-compatible Settings host and explicit legacy runtime rollback. |
| `src/HudWindow.xaml` | Main summary/list/quiet shell. |
| `src/TaskBubbleWindow.xaml` | Independent split-task surface. |
| `src/SettingsWindow.xaml` | Settings UI loaded only by the on-demand settings process. |
| `src/mcp-server.mjs` | Small local MCP control surface and bounded notice handoff. |

## Data flow

Discovery scans every enabled profile's Codex session date folders for files written inside the configured activity window, then applies one global 64-candidate cap. This prevents each added profile from multiplying the resident bound. Reopening an older conversation continues writing to its original date folder, so filtering only today's folder is incorrect. After discovery, ordinary watcher changes enqueue at most 256 affected paths. A full bounded scan occurs only for creation/deletion/rename, watcher overflow, startup, or the 30-second reconciliation boundary.

On discovery, the core reverse-reads 64 KiB chunks until it has the bounded 2,000-line tail instead of decoding the whole scan window. During monitoring, each state stores its file identity and byte offset and reads only appended data. The compiled reader rents a 64 KiB buffer; the monitor gives one session at most 256 KiB and all sessions together at most 4 MiB in one dispatcher pass. It carries only the incomplete record between reads and rejects a single pending record beyond 8 MiB. Unread session and official-title work remains in explicit backlogs for later responsive ticks. Records whose top-level type cannot affect identity, lifecycle, accounting, allowance, or model/workspace context are rejected before a full object graph is created.

Session identity, client surface, originator, and bounded model-provider label come from `session_meta`; user-facing conversation titles come from the matching profile's separate local `session_index.jsonl`. `codex_vscode` is classified as VS Code before the historical `source=vscode` Desktop fallback. Prompt, assistant, and tool-output text are not used for naming, source classification, or lifecycle inference. Internal/subagent source objects remain excluded. Model IDs are not allowlisted, so unknown future models keep all non-price monitoring behavior.

## State and projections

All surfaces read the same state objects. Split bubbles do not create new parsers. Visible membership is a projection over the discovered state table and applies internal-session, dismissal, active-window, terminal-retention, and departure rules.

Task numbering is in-memory and stable for the visible lifetime of a task. Released numbers enter a bounded cooldown queue before reuse.

The task registry is deliberately smaller than the UI state. Registry v2 stores only task number, workspace leaf, coarse status, update time, and bounded client/provider/profile labels so MCP controls can target the correct Desktop, VS Code, OpenAI CLI, or DeepSeek CLI task without exposing titles or transcript content.

## Rendering

Completed single clicks expand the ball immediately after mouse release. Both hosts track movement during `DragMove`, not just final displacement, so dragging out and back never becomes a click. Movement tracking is detached in `finally`, and rendering resumes only after the drag guard is cleared.

`surfaceMode` selects the normal window or a count-only floating ball independently from summary/list/split. `floatingBallSize` defaults to 60 DIP and is bounded to 32–120 DIP. Both hosts count only visible `active` and `listening` states and require a continuous 0.2-second hover before expansion. Press, leave, hide and mode changes cancel the timer; dragging suppresses expansion and requires fresh re-entry afterward. Collapse follows a 450 ms leave delay outside menus and drags. Placement computes the collapsed ball anchor first, picks left/right and up/down by screen midpoint, and locks that direction until collapse. Custom ball-mode coordinates persist the ball shell anchor, including when dragging the expanded window. A separate outer render transform provides 160 ms unfold/120 ms shrink and 100 ms show transitions without layout animation or interference with attention transforms; versioned completion guards prevent stale collapses after reversal, hide, drag or animation disable. Click-through disables effective ball mode. Dragging suspends polling/render/reposition work while retaining heartbeat updates; position persistence occurs only after actual movement.

Shared XAML resources give the ball finite number feedback and status-colored radial background motion. Only active/listening backgrounds loop, at 24 fps using opacity alone. Both hosts retain storyboard signatures to avoid refresh replay and remove clocks on expansion, hide, or `animateUpdates=false`; idle/paused backgrounds remain static. No native glass or animated blur is used.

The Settings host hides on close and stays cached for 10 minutes, then shuts down explicitly. Reopen requests reuse the window through a 100 ms signal timer and reload configuration only when hidden. A settings mutex avoids redundant launches from either host. The installer requests explicit settings-host exit before swapping files. System fonts are enumerated only when the font picker is opened; the frozen color-wheel bitmap remains lazy. XAML uses direct string parsing without an intermediate XML DOM. `scripts/test-settings-runtime.ps1` measures synthetic cold/warm visibility, HWND reuse, and graceful shutdown without reading user settings or sessions.

Independent bubbles use a uniform 420-DIP expanded content width and a root layout scale with automatic window sizing; Ctrl + wheel changes the per-session `BubbleScale` from 0.6 to 2.0, preserving it through collapse/merge/re-detach for the active session. Quiet indicators temporarily release the fixed content width so they still collapse to a dot. No corner resize handle or manual width/height is retained. `showProviderLabel` affects display labels and summary source grouping only, not identity metadata, source filtering, model display, or the privacy-safe registry.

The dispatcher uses an adaptive 250/800/1,500 ms cadence: bursts and parser backlog stay responsive, active/listening tasks retain the existing cadence, and idle state backs off. File-system changes for sessions, official titles, notices, and control signals coalesce into an immediate dispatcher wake, so the idle cadence does not add interaction latency. Directory discovery is separately bounded. A no-change tick advances lifecycle state without statting every session path, and a timer tick does not imply a full render.

The runtime caches:

- locale objects;
- appearance signatures;
- top-level metric control structure;
- task-list visible-content signatures;
- context and tray menu signatures;
- quiet-indicator projections.

Metric values update in place. List rows rebuild only when their structural projection changes; token, context, status, and notice text update retained controls. The header uses explicit grid columns so a fully populated metric row cannot overlap the right-side list toggle.

Attention is surface-local: summary mode affects the summary, list mode the matching row, and split mode the matching independent bubble. Context alerts animate only the context metric.

Each visible task has exactly one compact badge after its status dot, combining its source icon and stable number. The shared Lucide-derived visual language uses a monitor for Desktop, code brackets for VS Code, a terminal prompt for the normal OpenAI CLI, and horizontal waves for the isolated DeepSeek CLI profile. Closing a detached bubble changes only its projection ownership and merges it back into the main HUD; list-row dismissal is the separate operation that temporarily removes a task from the visible set.

## Settings process

The compiled resident HUD does not construct the full Settings or Color Picker visual trees. It launches the existing single on-demand Settings host with its own mutex. Closing the window saves configuration, writes a local reload signal, and exits. The compiled HUD reloads normalized configuration and invalidates only the affected render caches.

## Memory behavior

The resident parser, state table, and renderer now execute inside the compiled .NET process. Streaming buffers are pooled; changed paths and pending JSONL records are bounded; stable list structures retain controls instead of rebuilding them. The Settings process exits when closed, so its WPF tree and PowerShell heap are not resident.

Performance numbers remain machine- and fixture-specific. The migration is an architectural improvement, not a numeric memory promise; release evidence must include idle and burst measurements from the staged compiled runtime.

## Windows integration

- The Liquid visual layer uses WPF gradients and a non-hit-testable inner rim bound to the existing shell radius; it adds no native windows, shaders, assets, timers, or compositor changes. Both hosts share the XAML, while their dynamic list cards use the same foreground-luminance rule for light/dark inset surfaces.
- `ios26-liquid` is the new default and a declarative, importable theme. Saved settings still win during configuration merge, except that retired native-backdrop metadata always normalizes to `none`. Color-only legacy themes explicitly reset to solid surfaces so they never inherit the new pearl gradient. Native Blur/Acrylic, compositor interop, and native-region tracking have been removed; rounded WPF surfaces and ordinary transparency remain.
- Settings retain standard WPF control behavior behind custom templates, including named editing/slider/content parts, checked/disabled/focus states, and wrapping segmented headers. `scripts/test-liquid-design.ps1` loads actual templates, checks every tab at three window sizes, and verifies switches, sliders, scrolling, color-picker bounds, and radius bindings without reading user state.
- WPF provides transparent always-on-top windows.
- Per-Monitor V2 DPI awareness, layout rounding, and pixel snapping reduce mixed-DPI blur.
- Win32 extended styles implement optional click-through.
- Windows Forms provides the notification-area icon and recovery menu.
- Native window icons and a dedicated AppUserModelID prevent fallback to the PowerShell taskbar identity.

## Security and privacy boundaries

- no session-file writes;
- no telemetry or runtime network access;
- no prompt/response/tool-output parsing for identity or lifecycle;
- no model-authored XAML, script, shader, CSS, shell command, or network theme asset;
- bounded local notice messages and declarative animation recipes only;
- settings and user themes live outside the installed plugin directory.

The optional STDIO MCP server negotiates `2025-11-25` plus compatible older revisions and returns structured, schema-described tool results. It reads only HUD-local configuration, heartbeat, manual-exit state, and registry v2. Plugin installation is per `CODEX_HOME`; it never rewrites model/provider selections, and a new Codex task is required to discover a newly installed plugin. See `docs/MCP_INTEGRATION.md`.

## Testing strategy

`scripts/build-dotnet.ps1` builds the solution, runs the neutral Core suite, publishes the application, stages a private Windows Desktop runtime, and executes the staged health check. With `-RunRuntimeTests`, it also launches isolated compiled list and split WPF fixtures. Pure helpers and source contracts remain checked by `scripts/test.ps1`. `scripts/test-runtime-isolated.ps1` drives the same synthetic lifecycle and routing fixture against either `-HostMode legacy` or `-HostMode compiled`; `scripts/compare-runtime-performance.ps1` runs both hosts under the same list/split workload and records private bytes, working set, CPU, handles, and threads. Installation performs health, static, behavioral, and performance gates against a separate staged copy before switching directories; the prior installed version is retained under a versioned rollback path. Render-preview modes provide visual evidence for language, density, list style, transparency, and quiet layouts.

## Portability decision

A full rewrite into C# does not by itself create a macOS application: WPF, Windows Forms, notification-area behavior, click-through flags, registry integration, and AppUserModelID are Windows-only. The portable unit is the neutral Core plus file/config contracts. A macOS product should add a separate UI/system-integration project and reuse the Core rather than conditionally compiling Win32 calls throughout one application.

The preferred next shell is Avalonia if maximum C# reuse is more important than perfectly native macOS controls; SwiftUI is the alternative if native menu-bar/window behavior is more important than shared UI code. Either route still needs macOS-specific work for `.app` packaging, signing/notarization, menu-bar recovery, transparent-window hit testing, launch-at-login, deep links, and Apple-silicon arm64 validation.
