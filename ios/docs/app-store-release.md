# ClaudePal App Store Metadata And Review Notes

## App Store Metadata Draft

- App Name: ClaudePal
- Subtitle: Claude approvals on iPhone and Apple Watch
- Promotional Text: Review Claude Code permissions, approvals, and session status from your wrist or your phone.
- Keywords: Claude, approvals, developer tools, watch, notifications, automation
- Support URL: `https://github.com/nikhilchowdary/ClaudePal`
- Marketing URL: `https://github.com/nikhilchowdary/ClaudePal`

## Screenshot Plan

- iPhone dashboard with active approval
- iPhone pairing flow with QR scan
- iPhone event detail showing destructive auth requirement
- Apple Watch approval screen
- Widget or complication showing active status

## Review Notes

- The app pairs with a local bridge process running on the user's own Mac.
- Remote notifications are used to deliver approval prompts from that bridge.
- Camera access is only used to scan a local pairing QR code.
- Local network access is only used to discover nearby bridge instances over Bonjour.
- The app does not provide a public cloud service or third-party account system.

## Privacy Disclosure Notes

- Data linked to the user: none
- Data used for tracking: none
- Diagnostics shared externally by default: none
- Device push tokens are sent only to the user's own bridge for APNs delivery

## Known Limitations

- The bridge host currently targets macOS for launch-on-login packaging.
- APNs push setup requires a paid Apple Developer team with push capability.
- Complex elicitation forms intentionally continue on iPhone instead of watch.
- Remote access is documented through Tailscale rather than a hosted bridge product.

