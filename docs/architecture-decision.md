# ClaudePal Architecture Decision

Date: April 11, 2026

## Decision

The best long-term architecture for ClaudePal is a **hybrid architecture**:

- a **macOS companion app** is the source of truth and the only component allowed to write approval decisions back into Claude Code
- **CloudKit** is used as a cross-device sync layer for session state, history summaries, and watch/iPhone views
- a small **APNs relay service** is used only for background notifications, Live Activity refreshes, and wakeups when the iPhone is not foregrounded

This is better than:

- a **pure local bridge** for product usability and distribution
- a **pure CloudKit-first architecture** for approval accuracy, latency, and failure containment

## Executive Summary

If the goal is:

- fastest approval loop
- highest correctness for destructive approvals
- lowest chance of silent failure
- least painful consumer onboarding

then the answer is **not** “make the iPhone app smarter” and it is **not** “copy Codync exactly”.

The best answer is:

1. move the current bridge into a packaged macOS app
2. keep approval write-back local to that Mac app
3. mirror state to Apple devices through CloudKit
4. use a managed APNs relay only where iOS background delivery requires it

## What We Learned From Comparable Products

### Codync

Codync is useful because it proves that a companion developer app can feel close to zero-config if it uses Apple-native distribution and sync:

- macOS app installs Claude hook scripts
- session state syncs through CloudKit
- iPhone and watch apps are mostly display clients
- a Cloudflare Worker is used as an APNs relay for background updates

That is why Codync can claim:

- no LAN required
- zero config
- no login

But Codync is primarily a **monitoring product**. Monitoring tolerates eventual consistency much better than approval workflows do.

Sources:

- https://github.com/leepokai/Codync
- https://www.codync.dev/

### ntfy and the iOS constraint

The key technical constraint is not Claude Code. It is iOS background delivery.

The ntfy docs explicitly state that iOS instant notifications are not realistically possible without a central APNs-connected server. That matches what many self-hosted iOS products do in practice: they either rely on a managed upstream for push or they accept degraded background behavior.

Source:

- https://docs.ntfy.sh/config/

## What ClaudePal Needs That Codync Does Not

ClaudePal is not only a session monitor. It is meant to support:

- permission approvals
- destructive action gating
- elicitation response write-back
- reliable round-trip resolution before hook timeout

That changes the architecture choice.

For monitoring, stale data is annoying.

For approvals, stale data is dangerous.

That means the path that actually resolves a Claude hook must be:

- low latency
- deterministic
- directly attached to the machine running Claude Code
- resilient to temporary cloud and mobile failures

CloudKit alone is not the right system of record for that.

## Options Considered

### Option A: Pure Local Bridge

Current direction:

- local HTTP/WebSocket bridge on the Mac
- iPhone pairs directly to the bridge
- APNs is configured on the bridge host
- remote access uses Tailscale or another network overlay

#### Strengths

- fastest approval path
- direct control over hook round-trips
- minimal cloud dependency
- easiest to reason about for correctness

#### Weaknesses

- user setup is too technical
- Node/global npm is not consumer-friendly
- APNs key setup on the Mac is a major onboarding barrier
- remote access requires extra networking knowledge

#### Verdict

Strong runtime model, weak product model.

### Option B: CloudKit-First, Codync-Style

Architecture:

- macOS app captures hook events
- session state syncs through CloudKit
- iPhone and watch consume CloudKit state
- push comes from a cloud relay

#### Strengths

- excellent consumer onboarding
- no LAN pairing complexity
- Apple-native sync feels invisible
- easy App Store story

#### Weaknesses

- CloudKit is an eventually consistent sync layer, not an approval transaction bus
- approval write-back becomes harder to guarantee under latency, offline, or merge-delay conditions
- failure analysis is harder because there are more async boundaries
- destructive approval flows should not depend on a cloud-synced projection being current

#### Verdict

Excellent for monitoring and state viewing, not strong enough as the only approval backbone.

### Option C: Hybrid macOS Source Of Truth + CloudKit Mirror + APNs Relay

Architecture:

- macOS app owns hook ingestion, persistence, and approval resolution
- iPhone/watch read a mirrored session model from CloudKit
- phone approvals are sent to the macOS source of truth, not resolved inside CloudKit
- APNs relay wakes the phone and refreshes Live Activities when background execution is needed

#### Strengths

- keeps the fastest and safest approval path local
- gives users a nearly zero-config Apple ecosystem experience
- reduces LAN and manual pairing complexity
- supports watch/iPhone status everywhere through CloudKit
- avoids using CloudKit as a transaction coordinator

#### Weaknesses

- highest implementation complexity
- requires both Apple-native sync work and local bridge/macOS app work
- introduces a small managed service for APNs relay

#### Verdict

Best overall architecture for ClaudePal.

## Comparative Scoring

Scored from 1 to 5, where 5 is best.

| Criterion | Pure Local Bridge | CloudKit-First | Hybrid |
| --- | --- | --- | --- |
| Approval latency | 5 | 3 | 5 |
| Approval correctness | 5 | 3 | 5 |
| Destructive action safety | 5 | 3 | 5 |
| Consumer onboarding | 2 | 5 | 4 |
| Remote access UX | 2 | 5 | 4 |
| Failure isolation | 4 | 3 | 4 |
| Offline/LAN behavior | 5 | 3 | 5 |
| Implementation simplicity | 3 | 4 | 2 |
| Long-term product quality | 3 | 4 | 5 |

## Why The Hybrid Is Better

### 1. The approval path stays local

When Claude emits a permission request, the fastest and most trustworthy component is the machine already running Claude Code. That machine should:

- receive the hook
- persist the pending approval
- enforce destructive approval policy
- accept the final decision
- write the result back to Claude immediately

That path should not depend on CloudKit propagation.

### 2. CloudKit is perfect as a read model

CloudKit is still a very good fit for:

- session list
- current status
- summaries
- event history
- watch widgets and Live Activities
- primary-session selection

Those are exactly the kinds of things where:

- Apple identity is already present
- sync should “just happen”
- eventual consistency is acceptable

### 3. iOS background behavior still needs help

If the iPhone app must alert the user while the app is backgrounded, APNs is still required. That means one of these must exist:

- a managed ClaudePal relay
- a user-run relay with APNs credentials

For a mainstream product, a managed relay is the right choice.

### 4. Packaging matters as much as protocol design

The biggest onboarding problem in the current ClaudePal design is not the protocol. It is packaging:

- install Node
- install npm package
- configure env vars
- run a local service manually
- install hooks manually
- reason about remote networking manually

A macOS app removes most of that friction even if the internal architecture remains local-first.

## Recommended Target Architecture

### Source of truth

Use a **macOS menu bar app** or lightweight background app as the authoritative runtime on the Mac.

It owns:

- Claude hook installation
- local event ingestion
- SQLite persistence
- approval write-back
- local diagnostics
- launch-on-login

### Local data plane

Keep a local storage and control plane on the Mac:

- SQLite for sessions, events, pending approvals, and audit trail
- local IPC or localhost HTTP only if needed by internal components
- no requirement for the iPhone to talk directly to a LAN bridge for normal operation

### Sync plane

Mirror state to **CloudKit**:

- active sessions
- recent event summaries
- pending approval metadata
- watch-facing state
- primary session and user presentation preferences

CloudKit records should be treated as a **projection**, not as the transaction authority.

### Approval command plane

Phone approval should work like this:

1. iPhone receives APNs wakeup or sees CloudKit state change
2. user approves or denies
3. command is sent to the macOS authority through a secure ClaudePal service path
4. macOS app resolves local pending approval and writes hook response back immediately
5. resolved state then mirrors back to CloudKit

Important rule:

- **CloudKit must not be the mechanism that finalizes approval transactions**

### APNs relay

Use a small managed ClaudePal relay for:

- APNs push notifications
- Live Activity background refresh triggers
- fallback wakeups when the phone is backgrounded

It should not need full session state. Ideally it only handles:

- device registration
- token routing
- wakeup/notification fanout

### iPhone and watch role

The iPhone app should be:

- primary user interface
- destructive approval authenticator
- decision entry point
- CloudKit consumer
- APNs receiver

The watch app should be:

- glance surface
- quick approve/deny surface for safe actions
- handoff surface for destructive or complex actions

## Security Model

### macOS authority

All sensitive writes should be authorized by the macOS authority. The phone is a trusted user device, but it should not become the authoritative state machine.

### Destructive approvals

Destructive approvals should require:

- local device authentication on iPhone
- explicit marking in the local pending approval record
- audit logging in the macOS store

### Cloud exposure

CloudKit should store only what is needed for cross-device UX, not raw transcripts or unnecessary command payloads unless they are explicitly required.

The APNs relay should avoid storing durable session content if possible.

## Failure Mode Analysis

### If CloudKit is delayed

Hybrid outcome:

- local approval still works on the Mac
- iPhone view may be momentarily stale
- state converges once CloudKit catches up

This is acceptable.

### If APNs is delayed

Hybrid outcome:

- approval does not silently corrupt state
- user may not get the wakeup immediately
- local pending approval still exists and can be resolved from the Mac

This is acceptable.

### If the phone is offline

Hybrid outcome:

- Mac still owns the pending approval
- the phone can act when it reconnects
- watch naturally degrades with phone connectivity

This is acceptable.

### If the Mac is offline

No architecture can resolve Claude hooks if the Mac running Claude Code is gone.

That means the system should optimize for:

- making the Mac-side authority robust
- making reconnection and resume reliable

not for pretending the Mac can disappear from the critical path.

## Practical Recommendation For ClaudePal

### Near-term

Keep the current bridge logic, but move it into a **macOS app shell**:

- package the bridge runtime inside the app
- add GUI onboarding
- add one-click hook install
- add launch-on-login
- show pairing, health, and logs in-app

This improves onboarding immediately without rewriting the core approval engine.

### Mid-term

Add **CloudKit sync** for mirrored state:

- session summaries
- pending approval summaries
- watch/iPhone dashboards
- Live Activity content

### Long-term

Add a **small ClaudePal-managed APNs relay** and move away from requiring end users to provision APNs credentials on their own Mac.

That is the step that turns the product from “developer setup” into “consumer install”.

## Final Recommendation

The better architecture is:

- **not** pure local bridge
- **not** pure CloudKit-first
- **yes** to a **hybrid architecture with macOS as the source of truth**

Short version:

- use **macOS local authority** for anything that affects Claude hook resolution
- use **CloudKit** for cross-device state sync and presentation
- use an **APNs relay** for background notifications and wakeups

That gives ClaudePal the best mix of:

- speed
- correctness
- safety
- resilience
- user-friendly setup

## References

- Codync GitHub: https://github.com/leepokai/Codync
- Codync website: https://www.codync.dev/
- ntfy iOS background notification notes: https://docs.ntfy.sh/config/
