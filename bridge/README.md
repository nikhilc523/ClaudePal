# ClaudePal Bridge

`claudepal-bridge` is the local companion service for the ClaudePal iPhone and Apple Watch apps. It receives Claude hook events, persists bridge state, pushes approval notifications, and accepts decisions back from the phone or watch.

## Install

```bash
npm install -g claudepal-bridge
```

Run the bridge:

```bash
claudepal-bridge
```

Install Claude hook settings into the current project:

```bash
claudepal-bridge install --scope local
```

Create a pairing QR payload:

```bash
claudepal-bridge pair
```

Inspect the current installation:

```bash
claudepal-bridge status
claudepal-bridge doctor
```

Remove managed Claude hook settings:

```bash
claudepal-bridge uninstall --scope local
```

## Commands

- `claudepal-bridge install`
- `claudepal-bridge uninstall`
- `claudepal-bridge pair`
- `claudepal-bridge status`
- `claudepal-bridge doctor`
- `claudepal-bridge mock:event`
- `claudepal-bridge launchd print|install|uninstall`
- `claudepal-bridge logs export`

## Docs

- [Onboarding](./docs/onboarding.md)
- [Operations](./docs/operations.md)
- [Troubleshooting](./docs/troubleshooting.md)

