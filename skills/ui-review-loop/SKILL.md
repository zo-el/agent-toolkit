---
name: ui-review-loop
description: Screenshot-gallery review loop for UI work — specs declare visual beats, an env-gated snap() saves a numbered gallery of the real app, the agent self-reviews the shots, then the user reviews and requests changes. Use whenever building or changing UI the user will want to see (any framework with a driveable app + screenshot API).
---

# UI review loop (screenshot galleries)

The user reviews UI from **screenshots of the real app**, not from live runs or prose descriptions. The loop: build → drive the journey in a spec that declares its visual beats → generate the gallery → **self-review every shot** → hand the gallery over → apply feedback → regenerate. Repeat until a round comes back clean. One artifact serves three purposes: regression test, review material, living documentation of every UI state.

## The mechanism (~20 lines in any harness)

- A `snap(name)` helper in the e2e harness: with an env var set (e.g. `UI_TEST_SHOTS=<dir>`) it saves a **numbered** screenshot (`07-w9-fork.png`); unset → no-op, so CI pays nothing. (WebdriverIO: `browser.saveScreenshot`; Playwright: `page.screenshot`.)
- Specs call `snap("w2-intro")` at each **visual beat** — name shots as journey beats tied to the design's wireframe ids, so the gallery reads as the user journey.
- A `shotsEnabled()` guard lets a spec stretch *scripted mock timings* so transient states (spinners, substitutions, progress rows) hold still long enough to capture. That is the ONLY conditional allowed — never land demo pauses in specs (no test framework slow-mo knob makes them acceptable; screenshots replace watching).

## Self-review before handing over

View every shot yourself and critique it — the user's review time is spent on design decisions, not on bugs you could have caught. Specifically hunt:

- **Two shots that look identical** — a beat that stopped earning its place after a flow change; make each shot show its subject (e.g. open the menu that holds the disabled buttons).
- **Asserts that pass invisibly** — a `disabled` prop check on a control inside a closed menu proves nothing to a reviewer; the shot must SHOW the state.
- **Inherited styling across surface boundaries** — a modal over a dark surface inherits its light text onto a white card (washed-out headings); buttons styled for one background sitting on another.
- **Mock data that misrepresents state** — e.g. a security allowlist disabling a button only because the mock serves a non-allowlisted URL; mock the REAL happy-path data so shots show production appearance.
- **State-change side effects** — rotating/animating a container that used to be visually symmetric (a circle → rounded square turning into a diamond on rotate).

## Hard-won spec mechanics

- Assert **transient UI from component state**, not DOM text polls — fast flows outrun a 1s poll and the pane unmounts; read the element's state once the stable end-state renders.
- **Whitespace-normalize text matching** — prettier hard-wraps lit/JSX template sentences, putting newlines mid-phrase in `textContent`.
- A spec that sets **persistent state** (localStorage, opt-in mock persistence) cleans it **before AND after** (self-healing: a crashed run's leftovers must not poison the next; browser profiles outlive runs). If restore happens at module load, cleanup must reload the page.
- Failure outcomes the spec depends on must not hinge on real-network timing of unreachable hosts — assert the *observable state transition*, not an error message that may never render.

## With the user

- Present the gallery as a numbered table: shot → what they're reviewing. Map each change request to the shot it came from, and verify the fix by viewing the regenerated shot before reporting it done.
- Flag your own findings and judgment calls (with shot references) in the same round — but apply only what they asked; list the rest for their call.
