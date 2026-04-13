# ClaudePal Phase 6 Operations

This bridge is still a local-first service, but phase 6 adds the minimum operational surface needed for daily use:

- paired-device auth tokens gate sensitive bridge reads and approvals
- notification delivery retries transient APNs failures, deduplicates bursty repeats, and schedules reminder pushes before a hook expires
- bridge state survives restarts because pending decisions live in SQLite and reminder timers are restored on boot
- bridge logs are written to a private file by default and can be exported as a debug bundle
- macOS launch-on-login is supported through a generated `launchd` agent

## Recommended Remote Access: Tailscale

Use Tailscale as the default remote path. It gives you encrypted device-to-device transport without exposing the bridge publicly.

1. Install Tailscale on the Mac that runs the bridge and on the iPhone.
2. Confirm both devices can reach each other on the same tailnet.
3. Start the bridge on the Mac with a host that Tailscale can reach, for example:

```bash
CLAUDEPAL_HOST=0.0.0.0 node --disable-warning=ExperimentalWarning src/index.js
```

4. Create a pairing session that advertises the Mac's Tailscale address instead of localhost:

```bash
node src/cli/bridge.js pair \
  --base-url http://127.0.0.1:19876 \
  --bridge-url http://100.x.y.z:19876
```

`--base-url` is where the pairing session is created. `--bridge-url` is what gets embedded into the QR payload and stored by the iPhone.

## TLS-Ready Configuration

The iPhone and watch clients already support `https://` bridge URLs and `wss://` live updates. If you later front the bridge with Caddy, nginx, or another TLS terminator, create pairing sessions with an `https://...` `--bridge-url` and keep the bridge itself bound locally.

## Launch On Login

Generate a launch agent plist:

```bash
node src/cli/bridge.js launchd print
```

Install it into `~/Library/LaunchAgents`:

```bash
node src/cli/bridge.js launchd install
```

For custom locations during testing:

```bash
node src/cli/bridge.js launchd install --plist-dir /tmp/claudepal-launchagents
```

The generated plist wires these environment variables by default:

- `CLAUDEPAL_HOST`
- `CLAUDEPAL_PORT`
- `CLAUDEPAL_DB_PATH`
- `CLAUDEPAL_LOG_PATH`

If you need APNs credentials in launchd, add them to the plist's `EnvironmentVariables` dictionary before loading it with `launchctl`.

## Log Export

Bridge logs default to `data/claudepal.log`.

Export a debug bundle:

```bash
node src/cli/bridge.js logs export --base-url http://127.0.0.1:19876
```

If you are exporting from a non-loopback bridge address, pass the paired device token:

```bash
node src/cli/bridge.js logs export \
  --base-url http://100.x.y.z:19876 \
  --auth-token <device-auth-token>
```

The export bundle includes:

- `bridge.log` when the local file exists
- `health.json`
- `sessions.json`
- `events.json`
- `pending-decisions.json`
- `manifest.json`

## Reliability Controls

Optional environment overrides:

- `CLAUDEPAL_PUSH_DEDUP_WINDOW_MS`
- `CLAUDEPAL_PUSH_REMINDER_LEAD_MS`
- `CLAUDEPAL_PUSH_RETRY_ATTEMPTS`
- `CLAUDEPAL_PUSH_RETRY_DELAY_MS`
- `CLAUDEPAL_LOG_PATH`

