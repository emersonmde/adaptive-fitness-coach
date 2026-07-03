# Calorie Tracking — Product Spec (P4)

**Version 1.0** · Status: Approved for planning · Scope: iOS (phone-first; watch out of scope for v1)

Companion to `adaptive-fitness-coach-spec.md`. That PRD originally listed nutrition as a
non-goal ("calorie counting was already solved"); trying the existing apps proved it isn't,
which is what created this phase. This is a **new feature, not an extension of the workout
product** — it gets its own spec, its own non-negotiables, and must not dilute the watch-first
in-workout identity.

---

## 1. Summary

Dead-simple calorie logging built on what LLMs have actually solved: **text recognition and
fact-based retrieval** — not image-based guessing. Scan a receipt, barcode, or nutrition label;
the app identifies the seller and the items, then *looks up* each item's real calories from the
manufacturer's or restaurant's own published data. Photo-of-the-plate estimation exists only as
an explicit fallback ("I just made this thing, need to log it") and is always labeled as the
estimate it is.

The golden path is zero-conversation: **widget/icon → camera → snap → confirmation screen →
Save**, seconds end to end. Apple Health is the system of record — the app writes dietary
energy the way Health logs water intake, and keeps no private food database.

---

## 2. Problem & user

Same primary user as the main PRD: an adult building a fitness habit, losing weight, not a
quantified-self enthusiast. **Weight loss is driven by diet** — the main app governs the
training side; this closes the loop on intake.

**What existing calorie apps get wrong for this user:**
- Logging is the core interaction: search a crowd-sourced database of near-duplicate garbage
  entries, weigh ingredients, build recipes. The friction kills the habit in weeks.
- Their databases are unverified and stale; the number you log is confidently wrong.
- They are chat-free but shame-full: streaks, red days, over-budget warnings — the emotional
  failure mode that precedes the quiet uninstall.
- The new AI entrants lean on photo-of-plate estimation — the one modality that is
  *fundamentally* imprecise (portion information is not in the pixels) — and present the guess
  with false precision.

**Thesis:** most food a person on the go eats is **identifiable and looked-up-able** — it has a
receipt, a barcode, a label, a menu. Identification + retrieval is an LLM-solved problem.
Make that path effortless and verified; make estimation the honest fallback, not the product.

---

## 3. Non-negotiables

Distinct from the main PRD's N1–N7 (which continue to bind the workout product). Where they
overlap in spirit, these are the food-domain versions.

**C1 — Logging takes seconds, not questions.** The golden path is capture → confirm → save
with **zero required text input**. Clarifying questions are the exception, asked only when the
answer would *materially* change the number (see C4). If a flow can't hit roughly ten seconds
for a labeled/receipted item, it isn't done.

**C2 — Retrieval before estimation.** For anything identifiable (receipt, barcode, label,
recognizable branded/restaurant item), calories come from **retrieved facts** — the
manufacturer's or restaurant's own published nutrition data first, open databases (e.g. Open
Food Facts) as acceptable sources — never from a model's guess. Photo estimation is a fallback
mode only, and the UI never presents an estimate with the same confidence as a retrieved fact.

**C3 — Honest numbers, honest provenance.** Every logged entry knows where its number came
from: *verified* (seller's own data), *database* (open dataset), or *estimate* (model guess,
shown as a range, e.g. "550–750 kcal"). No false precision, ever — a fabricated-but-confident
number is the food-domain version of the main PRD's N6 and is the one unacceptable failure.

**C4 — Structured clarification, never chat.** When the model needs input (portion count,
confirm ingredients, "did you add dressing?"), it generates a **structured questionnaire
rendered as real native UI** — tappable options, sensible defaults, skippable — in the spirit
of Claude Code's option-picker, not a chat thread. The user answers by tapping, not typing.
No conversation-first UX anywhere in this feature.

**C5 — Apple Health is the system of record.** The app writes `dietaryEnergyConsumed` (and
macros where retrieved) to HealthKit, exactly as Health logs water. No private nutrition
store; deleting the app loses nothing. This *amends* the main PRD's N2 for the food domain:
the OS can observe a workout but cannot observe a meal, so here the app is the pen, and
Health remains the paper.

**C6 — No shame mechanics.** No streaks, no red days, no over-budget alarms. A missed day is
a missed day. **Consistency beats precision** for weight-loss adherence — a rough number
logged every day outperforms an exact number abandoned in week three; the design optimizes
for the logging habit surviving a bad weekend.

**C7 — The workout product stays untouched.** Phone-only feature (main PRD's N4 is about the
workout; this feature has no watch requirement in v1). No dashboards creep into the watch; no
nutrition nagging in workout flows.

---

## 4. Core experience

1. **Capture.** From a Home-Screen widget / app icon / App Intent (ideally a Lock-Screen or
   Action-Button path), the camera opens immediately. The user snaps a receipt, barcode,
   nutrition label, or (fallback) the food itself. Multiple items per capture is normal
   (a grocery receipt is many items).
2. **Identify.** The app recognizes what it's looking at and who sold it: store / restaurant /
   manufacturer, then the individual items. This happens without the user waiting on a chat.
3. **Confirm.** A native confirmation screen lists the identified items with checkboxes —
   pre-checked for the obvious case, uncheck the pantry items you're not eating now, fix a
   misread inline. If something material is ambiguous, the structured questionnaire (C4)
   appears here — tap, don't type. One button: **Log**.
4. **Research.** Only after confirmation does the lookup fan out (C2): each item resolved
   against the seller's own nutrition data. Results land in the entry with provenance (C3).
   The user doesn't wait on this screen — logging is optimistic, the numbers finalize in the
   background behind an honest status (the main app's "Saving to Health… → Saved" pattern).
5. **Done.** Entries are in Apple Health. The app shows a quiet daily line, not a dashboard.

**The salad benchmark (binding):** buy a salad at a store → open camera from the widget →
snap the label/receipt → confirmation shows "Chicken Caesar Salad — [Store]" pre-checked →
tap Log → done. No typing, no questions, under ten seconds of user attention.

---

## 5. The LLM pipeline (binding on technical design)

Not one mega-prompt. A **staged pipeline**, each stage small, testable, and independently
swappable — the same discipline as the workout engine:

1. **Capture classification** — receipt vs barcode vs nutrition label vs plate photo.
   (Vision/FoundationModels system tools: OCR, barcode reading — prefer on-device system
   capabilities for this stage.)
2. **Source identification** — which store / restaurant / manufacturer. Receipts carry this in
   the header; barcodes resolve via GS1 prefix + product databases.
3. **Item extraction** — line items from the receipt / product from the barcode / dish from
   the label or photo. Output is a structured item list (the confirmation screen's model).
4. **Per-item lookup** — one tailored call per item, with web access: *"find the calories for
   ⟨item⟩ from ⟨seller⟩"* — deliberately not over-specified, so the model is free to use open
   databases, but instructed to **prefer the manufacturer's / restaurant's own site**. Returns
   the number, the source URL, and a provenance grade (C3).
5. **Fallback estimation** (plate photos only) — model estimates a range with stated
   assumptions; the questionnaire (C4) fires only for the assumptions that materially move
   the number (portion size, cooking fat, additions).

Stages 1–3 produce the confirmation screen; stage 4 runs *after* the user commits (don't
spend web lookups on items the user unchecks). The item list, not chat history, is the state
that flows between stages.

**Context discipline (binding — PCC is 32K total):** the model never sees raw HTML. Every
`fetch_page` result is reduced on-device before it enters context:
- **Search rung is already cheap**: Parallel Search MCP returns LLM-optimized excerpts, not
  pages — prefer answering from excerpts before fetching at all.
- **HTML → markdown-ish text** via **SwiftSoup** (single pure-Swift SPM package, no transitive
  deps) plus a small readability-style reducer of our own: strip script/style/nav/footer,
  pick the main content block, and — critically for nutrition pages — **serialize `<table>`
  elements as markdown tables** and lists as bullets (nutrition facts live in tables;
  a naive text dump destroys exactly the structure the model needs). Fallback with zero
  dependencies: `NSAttributedString(html:)` → plain text (built-in, but flattens tables and
  wants the main thread — acceptable only as the fallback).
- **PDFs** (chains love publishing nutrition PDFs): built-in **PDFKit** text extraction, no
  dependency at all.
- **Hard cap per fetch** (~a few K tokens after reduction) with head+matched-section
  selection — the tool can accept an optional `query` so the reducer keeps the sections
  mentioning the item, not the page's first N paragraphs. One page in context at a time;
  each new fetch replaces, never accumulates.
- Per-item lookups are **independent sessions** (fresh context each), not one long
  conversation — the item list is the state, so nothing needs to survive between items.

**Engine reuse:** this rides the existing `CoachEngine` seam (`AdaptiveCore/Coach/`) — the
multimodal extension point (`CoachMessage.Content.image`) was reserved for exactly this.
Expect a sibling protocol shape for the pipeline (stage in → structured result out) rather
than the conversational `CoachSession`; both live behind the same provider abstraction so
backends stay swappable (main PRD P3 decision).

---

## 6. Open questions

| # | Question | Resolution path |
|---|----------|-----------------|
| CQ1 | **Which backend performs the web lookup (stage 4)?** *Researched 2026-07-02 — options validated, choice pending the spike:* **(a) PCC + custom client-side tools.** FoundationModels custom `Tool`s are app-executed and round-trip mid-generation — the "model says fetch this, app fetches, model continues, may ask again" loop is the framework's native pattern, not a hack. Apple ships **no built-in web search/fetch tool** for its own models (system tools are OCR, barcode, Spotlight only), so the app supplies `fetch_page` / `search` tools. Free, no keys; the open question is loop quality (multi-hop retrieval on Apple's model) and where app-side *search* comes from. **(b) `ClaudeForFoundationModels`** (Anthropic's official Swift package, iOS 27, same `LanguageModelSession` API): **server-side `webSearch` / `webFetch` / `codeExecution` tools** with `domains: .allowing/.blocking` filters and `maxUses` caps — exactly the "find calories for ⟨item⟩ from ⟨seller⟩, prefer their site, fall back to open databases" agentic loop, in one round trip. Costs: API key in dev; production needs a backend proxy (App-Attest direct billing "coming soon"). **(c) No-LLM fast paths**: Open Food Facts' free REST API resolves most *barcodes* with no model call at all. **Data point:** the new Siri already answers "calories for a Wendy's salad" citing openhealth.org — the lookup task is demonstrably LLM-tractable, but Siri's web tooling is not exposed through the developer API; don't assume PCC inherits it. | Spike, in order: (c) barcode→OFF first (it may make stage 4 rare); then (a) on-device with a `fetch_page` tool against PCC; escalate per-item to (b) behind the provider seam when free paths fail — a cost-bounded quality ladder. |
| CQ1b | **Claude-tier billing** (if/when the ladder escalates): consumer OAuth (Pro/Max) is contractually restricted to Claude Code/claude.ai (Anthropic policy, Feb 2026) — a Max plan cannot back this app. "Sign in with Claude" (sanctioned third-party OAuth) bills the **signed-in user's own prepaid extra-usage pool** — the right per-user shape — but `ClaudeForFoundationModels` today supports only `.apiKey` / `.proxied` (App-Attest billing to the dev's workspace "coming soon"). | **Decided (2026-07-02): free-first is the architecture, not a compromise.** v1 ships on OFF + USDA FDC tools + dev-key web search + fetch-navigation over PCC, zero auth UX. The CQ1/CQ3 spike measures coverage on a real week of the user's meals (% resolved per rung, provenance grade). Claude enters only if that number disappoints — then via per-user Sign in with Claude once the package supports it (dev API key acceptable meanwhile as a spike instrument / personal-TestFlight stopgap, never to subsidize other users). The unresolvable tail (local restaurants with no published data) goes to the honest-estimate fallback (C3) on any backend. |
| CQ2 | Does iOS 27 Health expose a first-party quick-log surface for dietary energy (as it does for water), and can the app register as a data source for it? | API check during planning (nothing found in WWDC26 coverage — Health still has no food-entry UX, which strengthens the capture-flow-as-product case); determines how much "daily line" UI the app needs at all. |
| CQ3 | **Where does app-side *search* come from for the PCC path?** Fetch alone can't find the right page ("wendys.com — but which page?"). **Distribution constraint (binding): no secrets bundled in the app** — the app must be shippable to TestFlight testers / the App Store with zero keys inside; any credentialed tier is user-supplied at runtime (Keychain), never ours. Validated keyless ladder: (a) **domain-specific free indexes** — Open Food Facts (fully keyless REST; barcode + text search) as a `search_food_facts` tool; USDA FoodData Central label data where reachable keylessly (its API key is free but per-caller — treat as optional, not bundled); (b) **Parallel Search MCP** (`https://search.parallel.ai/mcp`) — **free web search with no key and no account**, LLM-optimized excerpts, built for agents; call it as a plain HTTP/MCP client wrapped in our `web_search` tool. Free tier is positioned for light use — per-meal lookups qualify; a Parallel key raises limits *if a user ever needs it*; (c) **DuckDuckGo HTML** — keyless fallback if Parallel changes terms (unofficial, parse-fragile — fallback only); (d) **fetch-only navigation** ("browser-use-lite": fetch wendys.com → follow the nutrition link) — multi-hop quality on Apple's model is what the CQ1 spike measures. | Spike alongside CQ1: (a)+(b) as tools on the PCC session, (c)/(d) as fallbacks. Claude escalation (CQ1b) only via **user-supplied auth** — Sign in with Claude when supported, or a user-entered key stored in Keychain — consistent with the no-bundled-secrets constraint. |
| CQ4 | Questionnaire rendering: native SwiftUI generated from a structured schema (preferred — matches C4 and the app's design language) vs embedded web form. | Design decision at planning; default native. |
| CQ5 | How does the daily view surface intake alongside HealthKit's workout burn without becoming a dashboard (C6/C7)? | Design exploration bounded by DESIGN-PRINCIPLES.md. |

---

## 7. Dependencies & platform constraints

- **HealthKit dietary types** — `dietaryEnergyConsumed` + macro quantities; write authorization is a new permission prompt.
- **Vision / FoundationModels system tools** — OCR and barcode reading on-device (WWDC26: `OCRTool`, `BarcodeReaderTool`).
- **FoundationModels / provider seam** — pipeline stages behind the existing engine abstraction; backend choice per CQ1 (custom client-side `Tool`s for PCC; `ClaudeForFoundationModels` server tools as the escalation tier).
- **Open Food Facts REST API** — free, keyless barcode→product resolution (the no-LLM fast path; CQ3).
- **Parallel Search MCP** (`search.parallel.ai/mcp`) — free, keyless web search for the PCC `web_search` tool (CQ3); DuckDuckGo HTML as the keyless fallback. **No secrets ship in the app** — any credentialed escalation (Claude SSO / user key) is user-supplied at runtime.
- **SwiftSoup** (SPM, pure Swift, no transitive deps) — HTML parsing for the on-device page reducer (§5 context discipline); **PDFKit** (built-in) for nutrition PDFs; `NSAttributedString(html:)` as the zero-dependency fallback.
- **App Intents (iOS 27)** — the capture entry point (widget / Lock Screen / Action Button / Siri), and **`LongRunningIntent`** for the post-confirm research step: it manages the background task and **automatically surfaces progress as a Live Activity** — the "numbers finalize in the background behind an honest status" requirement (§4.4) nearly for free, visible on the Dynamic Island, StandBy, the watch Smart Stack, and CarPlay.
- **WidgetKit** — quick-capture widget; iOS 27 widgets are customizable via App Intents.
- **Camera** — capture UX; new `NSCameraUsageDescription`.

---

## 8. Non-goals

- No meal planning, recipes, macro targets, or diet coaching (revisit only after capture is boring-good).
- No crowd-sourced food database of our own; no user-generated food entries shared anywhere.
- No watch surface in v1.
- No streaks/gamification (C6).
- No photo-first marketing: estimation is a fallback, not the pitch.
- No chat UI anywhere in the feature (C4).

---

## 9. Direction for the planning session (read before planning P4)

1. Read this spec, then `docs/PROJECT-STATUS.md` and the P3 section's architecture notes —
   the provider seam you'll extend is in `AdaptiveCore/Sources/AdaptiveCore/Coach/`
   (`CoachEngine.swift` — see `CoachMessage.Content.image`), with the FoundationModels adapter
   pattern in `Adaptive Fitness Coach/Services/Coach/`.
2. **Spike CQ1 first** — the web-lookup mechanism decides the architecture. Prototype stage 4
   as app-side fetch + LLM extraction before considering key-managed backends.
3. Keep the pipeline stages as **pure, testable functions with structured in/out** in
   AdaptiveCore where possible (prompt builders, item-list models, provenance types,
   confirmation-screen state), with a `ScriptedPipeline`-style fake mirroring
   `ScriptedCoachEngine` so the whole flow is sim-demoable (`-simulateMealScan` or similar)
   and XCUI-testable before any real model call exists — that ordering worked well for P3.
4. The confirmation screen and questionnaire are bound by `docs/DESIGN-PRINCIPLES.md`
   (reserved slots, one dominant element, honest labels); provenance grades (C3) need a
   visual language that is *quiet* — not a trust-score dashboard.
5. Milestone slicing suggestion: (a) barcode → lookup → Health write (smallest full loop),
   (b) receipt multi-item flow + confirmation screen, (c) label scan + questionnaire,
   (d) plate-photo fallback + widget/App Intent entry. Each slice ends with the salad
   benchmark timed.
