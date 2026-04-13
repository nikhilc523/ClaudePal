# ClaudePal Release Checklist

## Bridge Package

- `npm test`
- `npm pack --dry-run`
- `claudepal-bridge install`
- `claudepal-bridge status`
- `claudepal-bridge doctor`
- `claudepal-bridge uninstall`

## App Validation

- `swift test` in `ios/ClaudePalKit`
- Generate the Xcode project from `project.yml`
- Archive a release build for iPhone + Watch targets
- Verify privacy manifest is included in the app target

## Beta Readiness

- TestFlight QA checklist completed on two physical iPhones and one Apple Watch
- Onboarding guide reviewed against a fresh machine
- Troubleshooting guide updated with any new known issues

## Release Notes

- Summarize user-facing changes
- Record rollout date and build number
- Record rollback steps

## Rollback Steps

- Revert bridge npm package to previous published version
- Disable launchd auto-start on the bridge host if required
- Ship a follow-up TestFlight build if the issue is app-side only

