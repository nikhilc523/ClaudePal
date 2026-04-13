# ClaudePal - Execution Plan (v2)

## Architecture Shift Notice

This plan supersedes the original v1 plan as of April 11, 2026.

Key change: the Node.js bridge is replaced by a **native macOS menu bar app** that acts as the local authority. Cross-device sync uses **CloudKit** instead of LAN pairing. There is no Node.js, no npm, no Tailscale, no manual networking.

See `docs/architecture-decision.md` for the full rationale.

## 1. Product Vision

ClaudePal is a native Apple ecosystem companion for Claude Code that lets the user:

- receive real push notifications when Claude needs attention
- approve or deny permission requests from iPhone or Apple Watch
- respond to supported input requests without returning to the Mac
- monitor active Claude sessions, recent events, and task completion state

The product is a three-app suite under one Apple Developer account:

- **ClaudePal for Mac** — menu bar app, source of truth, hook receiver, approval authority
- **ClaudePal for iPhone** — approval UI, dashboard, notifications, Live Activity
- **ClaudePal for Apple Watch** — glanceable status, quick approve/deny

All three apps share a CloudKit container. The user installs them and iCloud handles the rest.

## 2. Product Scope

### V1 must ship

- macOS menu bar app with Claude Code hook integration
- one-click hook installation
- local SQLite persistence on Mac
- CloudKit sync for sessions, events, and pending approvals
- iPhone app with actionable notifications, approval detail, dashboard, history, settings
- Live Activity showing session state
- Apple Watch companion for glanceable state and approve/deny
- APNs for background notification delivery
- destructive approval gating with Face ID
- launch-on-login for the Mac app
- DMG distribution for macOS, App Store for iOS and watchOS

### V1.1 / post-launch

- managed APNs relay (removes need for user's own APNs key setup)
- Android client
- web dashboard
- multi-user support

## 3. Planning Assumptions

- one senior engineer building the first production-quality version
- target platforms: macOS 14+, iOS 17+, watchOS 10+
- all three apps built in Swift with SwiftUI
- Apple Developer account with CloudKit container, APNs key, and provisioning profiles
- physical iPhone and Apple Watch available for testing
- macOS app distributed as notarized DMG (not Mac App Store, to avoid sandbox)
- iOS and watchOS apps distributed through App Store / TestFlight

## 4. Key Technical Decisions

### 4.1 Claude Code integration

Use Claude Code HTTP hooks. The macOS app runs a localhost HTTP server to receive hook payloads directly from Claude Code.

Why HTTP hooks over shell scripts:

- native JSON payloads, no `curl` + `jq` wrappers
- same endpoint handles `PermissionRequest`, `Notification`, `Elicitation`, `TaskCompleted`, `Stop`
- no polling loop
- the macOS app controls the server lifecycle

### 4.2 System boundaries

- **macOS app** is the source of truth for hook resolution, sessions, events, and pending approvals
- **CloudKit** is the sync layer — a projection of Mac-side state, never the transaction authority
- **iPhone** is the primary user interface and approval command sender
- **Apple Watch** is a glance and quick-action surface, always relayed through iPhone
- **APNs** handles background wakeup only

Critical rule: **CloudKit must never finalize approval transactions.** The macOS app validates and resolves every approval locally before mirroring the result back to CloudKit.

### 4.3 macOS app architecture

- Swift + SwiftUI menu bar app (`MenuBarExtra`)
- Embedded localhost HTTP server (Swift NIO or Vapor)
- SQLite via GRDB for local persistence
- CloudKit framework for sync
- `SMAppService` for launch-on-login
- Direct file access to `~/.claude/` for hook config (no sandbox)
- Notarized DMG distribution with Sparkle for auto-updates

### 4.4 iPhone app architecture

- SwiftUI + Swift concurrency
- CloudKit subscriptions for real-time state updates
- `UserNotifications` with actionable categories
- `ActivityKit` + `WidgetKit` for Live Activities
- `WatchConnectivity` for watch sync
- `LocalAuthentication` for Face ID gated approvals
- Keychain for any auth tokens

### 4.5 Apple Watch architecture

- SwiftUI watch app
- State synced from iPhone via `WCSession`
- Approve/deny for safe actions
- Handoff to iPhone for destructive or complex actions
- WidgetKit complications

### 4.6 Distribution strategy

| Platform | Distribution | Why |
|---|---|---|
| macOS | Notarized DMG + Sparkle | Needs unsandboxed file access to `~/.claude/` and localhost server |
| iOS | App Store / TestFlight | Required |
| watchOS | App Store / TestFlight | Required |

CloudKit works with Developer ID-signed apps. No Mac App Store needed.

### 4.7 Remote access strategy

**There is no remote access configuration in V1.**

CloudKit is the transport. If the Mac and iPhone are signed into the same iCloud account, approvals work whether the devices are on the same network, different networks, or different continents.

This eliminates: Tailscale, LAN pairing, Bonjour discovery, manual URL entry, port forwarding.

## 5. Product Flows

### 5.1 Permission approval flow

1. Claude Code raises a `PermissionRequest` and posts the hook payload to localhost.
2. macOS app receives it, creates a pending approval in local SQLite, keeps the HTTP response open.
3. macOS app mirrors the pending approval to CloudKit.
4. CloudKit subscription triggers on iPhone. APNs delivers a background wakeup notification.
5. iPhone shows actionable notification with `Approve` and `Deny`.
6. User taps `Approve` (or opens the app and approves from detail view).
7. iPhone writes an approval command record to CloudKit.
8. macOS app receives the CloudKit subscription notification, reads the command.
9. macOS app validates the command, resolves the pending approval locally, writes the hook response back to Claude Code.
10. macOS app mirrors the resolved state back to CloudKit.
11. If no mobile decision arrives before hook timeout, Claude Code falls back to its local terminal UI.

Important: mobile approval accelerates the flow but never becomes the only path.

### 5.2 Input request flow (Elicitation)

Same transport as permission approval:

1. macOS app receives elicitation hook, mirrors to CloudKit.
2. iPhone shows form UI matching the elicitation schema.
3. User submits input.
4. iPhone writes input command to CloudKit.
5. macOS app reads it, validates, writes hook response.
6. Watch can handle simple text input via dictation; complex forms hand off to iPhone.

### 5.3 Task completion and notification flow

These are informational and must never block Claude Code:

1. macOS app receives `TaskCompleted`, `Stop`, or `Notification` hook.
2. Responds to Claude immediately (non-blocking).
3. Mirrors event to CloudKit.
4. iPhone and Watch show status update.

## 6. Event Model

### 6.1 Event types

- `permission_requested`
- `input_requested`
- `task_completed`
- `task_created`
- `session_started`
- `session_updated`
- `session_ended`
- `notification_received`
- `error_received`

### 6.2 Decision types

- `approve`
- `deny`
- `submit_input`
- `dismiss`
- `timeout`

### 6.3 Core records

#### Session

- `id`
- `cwd`
- `displayName`
- `status` (`active`, `waiting`, `idle`, `completed`, `failed`)
- `startedAt`
- `updatedAt`

#### Event

- `id`
- `sessionId`
- `type`
- `title`
- `message`
- `payload`
- `createdAt`

#### PendingDecision

- `id`
- `sessionId`
- `eventId`
- `decisionType`
- `status` (`pending`, `approved`, `denied`, `submitted`, `expired`)
- `expiresAt`
- `resolvedAt`

#### ApprovalCommand (CloudKit only)

- `id`
- `pendingDecisionId`
- `action` (`approve`, `deny`, `submit_input`)
- `inputPayload` (optional, for elicitation responses)
- `sourceDevice` (`iphone`, `watch`)
- `createdAt`

### 6.4 CloudKit record types

| Record Type | Synced By | Consumed By |
|---|---|---|
| `CPSession` | macOS | iPhone, Watch |
| `CPEvent` | macOS | iPhone, Watch |
| `CPPendingDecision` | macOS | iPhone, Watch |
| `CPApprovalCommand` | iPhone | macOS |
| `CPDeviceRegistration` | iPhone | macOS (for APNs targeting) |

Direction is intentional: macOS writes state records, iPhone writes command records. No conflicts.

## 7. Repository Layout

```text
ClaudePal/
├── plan.md
├── docs/
│   ├── architecture-decision.md
│   ├── cloudkit-schema.md
│   └── qa-checklists.md
├── contracts/
│   ├── events.schema.json
│   ├── decisions.schema.json
│   └── fixtures/
├── ClaudePalMac/
│   ├── ClaudePalMac.xcodeproj
│   ├── ClaudePalMac/
│   │   ├── App/
│   │   │   ├── ClaudePalMacApp.swift
│   │   │   └── MenuBarView.swift
│   │   ├── HookServer/
│   │   │   ├── HookServer.swift
│   │   │   └── HookRoutes.swift
│   │   ├── Storage/
│   │   │   ├── Database.swift
│   │   │   └── Models/
│   │   ├── CloudKit/
│   │   │   ├── CloudKitSync.swift
│   │   │   └── CloudKitSubscriptions.swift
│   │   ├── HookInstaller/
│   │   │   └── ClaudeHookConfig.swift
│   │   ├── Config/
│   │   └── Resources/
│   └── Tests/
├── ClaudePal/
│   ├── ClaudePal.xcodeproj (or workspace)
│   ├── ClaudePal/              (iPhone app)
│   ├── ClaudePalWatch/         (Watch app)
│   ├── ClaudePalWidgetExtension/
│   └── ClaudePalKit/           (shared Swift package)
└── scripts/
    ├── build-dmg.sh
    └── notarize.sh
```

## 8. Phase Plan

### Phase 1 — macOS Menu Bar App + Local Hook Loop

#### Goal

Prove that a native macOS app can receive Claude Code hooks, store events, and resolve approvals locally.

#### Deliverables

- macOS menu bar app shell with `MenuBarExtra`
- embedded localhost HTTP server
- hook endpoints for `PermissionRequest`, `Notification`, `Elicitation`, `TaskCompleted`, `Stop`
- SQLite persistence for sessions, events, and pending approvals
- one-click Claude hook installation (writes to `~/.claude/settings.json`)
- local approval resolution from the Mac menu bar UI (for testing)
- launch-on-login via `SMAppService`
- health indicator in menu bar (receiving hooks / idle / error)

#### Exit criteria

- Claude Code permission request arrives at the Mac app without manual config
- pending approval can be resolved from the Mac menu bar
- state survives app restart
- hook installation is a single button click

### Phase 1.5 — Notch Panel UI (Codync-Style Dynamic Island)

#### Goal

Replace or supplement the `MenuBarExtra` dropdown with a floating notch-anchored panel, similar to Codync's macOS Dynamic Island UI.

#### Deliverables

- Custom borderless `NSPanel` anchored to the top-center notch area
- Pill-shaped design with rounded corners, expand/collapse animation
- Compact state: small pill showing session status icon + pending count
- Expanded state: full approval detail with Approve/Deny buttons, session info, tool preview
- Smooth transitions between compact and expanded
- Click-outside-to-dismiss behavior
- Dark/light mode support
- Coexist with `MenuBarExtra` (menu bar icon still available as fallback)

#### Reference

- Codync macOS app: https://www.codync.dev/
- Implementation: custom `NSPanel` with `styleMask: [.borderless, .nonactivatingPanel]`, positioned at `NSScreen.main.frame` top center, CoreAnimation for pill shape and transitions

#### Exit criteria

- Pending approval appears as a pill near the notch
- Expanding shows full tool context and approve/deny
- Feels native and responsive, no flicker on expand/collapse

### Phase 2 — CloudKit Sync Layer

#### Goal

Mirror Mac-side state to CloudKit so iPhone can see it.

#### Deliverables

- CloudKit container configured with record types
- macOS app pushes sessions, events, and pending approvals to CloudKit
- macOS app subscribes to `CPApprovalCommand` records from iPhone
- approval command processing: read command → validate → resolve locally → mirror result
- conflict and deduplication handling
- CloudKit error recovery and retry

#### Exit criteria

- a pending approval created on Mac appears in CloudKit Dashboard within seconds
- an approval command written to CloudKit is picked up by the Mac app and resolves the hook
- CloudKit failures do not crash the Mac app or block Claude Code

### Phase 3 — iPhone App: Pairing-Free Setup + Approval UI

#### Goal

Ship an iPhone app that sees pending approvals and can resolve them, with zero manual pairing.

#### Deliverables

- iPhone app shell with onboarding
- CloudKit subscription for `CPPendingDecision` records
- approval detail screen with full tool context
- approve/deny action flow (writes `CPApprovalCommand` to CloudKit)
- APNs registration and device token upload to CloudKit
- actionable notification categories (`Approve`, `Deny`, `Open`)
- notification response handling (background approval write-back)
- destructive approval gating with Face ID

#### Exit criteria

- install Mac app, install iPhone app, same iCloud account — pending approvals appear on iPhone
- tapping `Approve` on a notification resolves the Claude Code hook on the Mac
- no QR codes, no IP addresses, no pairing codes
- destructive actions require Face ID

### Phase 4 — iPhone Product Surface

#### Goal

Make the iPhone app a complete daily-use companion, not just a notification endpoint.

#### Deliverables

- dashboard showing active sessions and pending approvals
- event history with filters
- session detail view
- settings screen (notification preferences, destructive action policy)
- Live Activity using `ActivityKit` for current session state
- in-app banners and haptics for real-time events
- connection/sync health indicator

#### Exit criteria

- user can browse history, inspect sessions, and approve from inside the app
- Live Activity updates when Claude transitions between active, waiting, and idle
- app is useful even without relying on notification taps

### Phase 5 — Apple Watch Companion

#### Goal

Deliver a reliable wrist-first glance and approval experience.

#### Deliverables

- watch app shell
- current status screen
- approve/deny UI for safe actions
- phone-watch sync via `WCSession`
- haptics for waiting, success, failure
- watch complication via WidgetKit
- dictation for simple elicitation input
- handoff to iPhone for complex/destructive actions

#### Exit criteria

- permission request can be approved from watch while iPhone is locked
- watch state stays in sync with current session status
- complication shows active/waiting/idle accurately

### Phase 6 — Security, Reliability, and Polish

#### Goal

Harden for real daily use.

#### Deliverables

- CloudKit subscription reliability audit
- pending decision reminder notifications before hook timeout
- deduplication for repeated notification bursts
- audit logging for approval decisions
- Sparkle auto-update integration for Mac app
- exportable diagnostic logs
- edge case handling: multiple Macs, stale CloudKit records, iCloud sign-out

#### Exit criteria

- reconnecting after Mac app restart does not lose pending state
- destructive approvals require Face ID on iPhone
- no duplicate or phantom approvals after network interruption

### Phase 7 — Packaging and Beta Release

#### Goal

Ship a testable beta.

#### Deliverables

- DMG builder and notarization script for Mac app
- TestFlight build for iPhone and Watch
- onboarding flow in Mac app (install hooks → verify → done)
- setup guide documentation
- App Store metadata and privacy disclosures
- release checklist

#### Exit criteria

- fresh user: download DMG, install, open Mac app, click "Install Hooks" — done on Mac side
- install iPhone app from TestFlight — pending approvals appear automatically
- no source edits, no terminal commands, no env vars
- beta test passes on physical iPhone + Apple Watch

## 9. Testing Strategy

### Unit tests

- hook payload parsing
- SQLite CRUD operations
- CloudKit record encoding/decoding
- approval command validation
- timeout logic

### Integration tests

- hook payload → Mac storage → CloudKit mirror → iPhone visibility
- iPhone approval command → CloudKit → Mac pickup → hook resolution
- watch approve → iPhone relay → CloudKit → Mac resolution

### Manual device test matrix

- Mac app foreground + background
- iPhone foreground, background, locked
- Apple Watch on wrist, phone nearby
- Mac app restart during pending decision
- iCloud sync delay simulation
- no-network scenarios

### Beta acceptance bar

- permission approval success rate is high enough for daily use
- no duplicate or orphaned pending decisions after restart
- approval round-trip under 5 seconds in normal conditions

## 10. Major Risks and Mitigations

### Risk: CloudKit subscription latency exceeds hook timeout

Mitigation: Claude Code hook timeouts for permission requests are typically minutes, not seconds. CloudKit subscriptions typically fire in under 2 seconds. There is ample margin. If CloudKit is severely delayed, the flow falls back to terminal approval.

### Risk: CloudKit outage blocks all approvals

Mitigation: the Mac app still has the full local approval UI in the menu bar. Mobile is a convenience layer, not the only path.

### Risk: App Store review concerns about remote control

Mitigation: the iPhone app is a companion to a self-hosted developer tool. Explicit user-initiated iCloud pairing (same account). Clear context before approvals. Destructive actions require Face ID.

### Risk: unsandboxed Mac app raises security concerns

Mitigation: notarization, Sparkle for updates, minimal file access (only `~/.claude/` and app data), open source if desired.

### Risk: watch experience unreliable if it owns too much logic

Mitigation: watch state is derived from iPhone via WCSession. Watch never talks to CloudKit or the Mac directly.

## 11. Definition of Done for V1

V1 is done when:

- macOS menu bar app receives Claude Code hooks without manual config
- iPhone receives push notifications for permission and completion events
- user can approve or deny from notification, app, or watch
- supported input requests can be answered from iPhone, simple ones from watch
- app shows current session state, pending approvals, and history
- Live Activity reflects active/waiting/idle
- Mac app restart does not lose pending state
- install flow requires zero terminal commands for the end user
- TestFlight beta is stable on physical devices

## 12. Build Order

1. macOS menu bar app + localhost hook server + SQLite
2. one-click hook installer
3. CloudKit container + record types + Mac sync
4. CloudKit approval command processing on Mac
5. iPhone app + CloudKit subscriptions + approval UI
6. APNs + actionable notifications
7. dashboard, history, Live Activity
8. Apple Watch companion
9. security hardening + reliability
10. DMG packaging + TestFlight + beta release

This sequence proves the hook loop locally first, then adds CloudKit, then builds the mobile surface on top of proven sync.
