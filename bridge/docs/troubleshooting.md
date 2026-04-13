# Troubleshooting

## `claudepal-bridge doctor` fails on hooks

Run:

```bash
claudepal-bridge install --scope local
```

Then confirm `.claude/settings.local.json` contains ClaudePal-managed hook groups.

## Bridge health check is unreachable

- Confirm the bridge process is running.
- Check `data/claudepal.log`.
- If you changed the port, rerun `status` and `doctor` with `--base-url http://127.0.0.1:<port>`.

## Push notifications are not arriving

- Verify APNs environment variables are present in the bridge environment.
- Confirm the iPhone granted notification permission.
- Re-pair if the device auth token was reset.
- Use `claudepal-bridge logs export` to capture `health.json`, event history, and bridge logs.

## Approval works on iPhone but not on Apple Watch

- Confirm the iPhone app is paired and recently synced.
- Open ClaudePal on iPhone once after bridge restart so the watch state refreshes.
- Complex elicitation forms intentionally fall back to iPhone.

## Remote access does not work off-LAN

- Prefer the Tailscale path described in [operations.md](./operations.md).
- Pair using the reachable Tailscale URL, not `127.0.0.1`.
- If you front the bridge with TLS, pair with the final `https://` URL so the app uses `wss://` for realtime updates.

