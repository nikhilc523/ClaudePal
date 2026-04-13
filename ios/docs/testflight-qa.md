# ClaudePal TestFlight QA Checklist

## Devices

- iPhone 1: iOS 17+
- iPhone 2: iOS 17+
- Apple Watch: watchOS 10+

## Pairing

- Fresh install launches to pairing flow.
- QR pairing succeeds against a local bridge.
- Notification permission request appears and registration completes.
- Bonjour discovery finds a LAN bridge when available.

## Approval Flow

- Permission request push arrives on the paired iPhone.
- Non-destructive approve succeeds from the iPhone app.
- Destructive approve requires device authentication.
- Deny succeeds from the notification action.
- Pending decision reminders arrive before timeout.

## Reliability

- Bridge restart does not lose unresolved decisions.
- Realtime updates reconnect after bridge restart.
- Offline decision queue flushes after the bridge becomes reachable again.
- Watch state refreshes after an iPhone reconnect.

## Watch

- Watch shows current pending approval.
- Simple text input elicitation can be submitted from watch dictation.
- Destructive approvals hand off to the iPhone.
- Widget/complication state matches active versus idle status closely enough to be useful.

## Release Blocking Issues

- APNs registration fails on supported signing setup.
- Approval response reaches the bridge but Claude hook response is not unblocked.
- Repeated pushes spam the same event after dedup window tuning.

