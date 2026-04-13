# ClaudePal Onboarding

This guide covers the first-time bridge setup for a fresh beta tester.

## Supported Environments

- macOS 14 or newer for the bridge host
- Node.js 22 or newer
- iPhone running iOS 17 or newer
- Apple Watch running watchOS 10 or newer for the watch companion
- Claude Code with project or user hook settings enabled

## 1. Install The Bridge

```bash
npm install -g claudepal-bridge
```

Start the local bridge:

```bash
claudepal-bridge
```

## 2. Install Claude Hooks

From the Claude project directory:

```bash
claudepal-bridge install --scope local
```

Validate the install:

```bash
claudepal-bridge status
claudepal-bridge doctor
```

## 3. Configure APNs

The bridge can start without APNs, but push approvals need it.

Required environment variables:

- `CLAUDEPAL_APNS_KEY_ID`
- `CLAUDEPAL_APNS_TEAM_ID`
- `CLAUDEPAL_APNS_BUNDLE_ID`
- `CLAUDEPAL_APNS_PRIVATE_KEY` or `CLAUDEPAL_APNS_PRIVATE_KEY_PATH`

Example:

```bash
export CLAUDEPAL_APNS_KEY_ID=KEY1234567
export CLAUDEPAL_APNS_TEAM_ID=TEAM123456
export CLAUDEPAL_APNS_BUNDLE_ID=com.nikhilchowdary.ClaudePal
export CLAUDEPAL_APNS_PRIVATE_KEY_PATH=$HOME/.config/claudepal/AuthKey_KEY1234567.p8
claudepal-bridge
```

## 4. Pair The iPhone

Create a pairing session:

```bash
claudepal-bridge pair
```

Scan the QR payload in the ClaudePal iPhone app, then enable notifications and approve the local network prompt if shown.

## 5. Optional Remote Access

Use the documented Tailscale flow in [operations.md](./operations.md) if the iPhone must reach the bridge away from the local machine.

