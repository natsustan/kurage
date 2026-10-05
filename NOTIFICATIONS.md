# iOS notifications

Kurage implements ordinary push notifications with a separate OneSignal iOS app and OneSignal iOS SDK 5.5.1, pinned in `project.yml` and `Package.resolved`. Official Lody machines submit notification events to Lody Cloud; delivery from that Cloud to Kurage has not been confirmed. Live Activities are not implemented.

The notification feature is currently hidden pending confirmation of official hosted Cloud support. `OneSignalNotificationService.isCloudDeliveryEnabled` is `false`, so normal launches do not initialize the SDK or resume registration from a saved preference. Settings shows the Notifications entry only when the injected service is configured. The implementation, signing configuration and stored preference remain available for a later rollout; `--fixture --fixture-notifications` still exercises the isolated notification flows. After the operator confirms a supported sending configuration, enable the flag, rebuild, and verify real device delivery before restoring availability to users.

## Client configuration

1. Create a OneSignal app for the Kurage bundle ID, `com.spike.kurage`, and configure its Apple iOS platform with an APNs authentication key. Register the notification extension bundle ID, `com.spike.kurage.notification-service`, and enable the `group.com.spike.kurage.onesignal` App Group for both targets. Enable Push Notifications for the main app's signing configuration.
2. The public `KURAGE_ONESIGNAL_APP_ID` build setting defaults to Kurage's OneSignal app UUID, `199f71a9-c5a2-42c9-ac88-4b8b7593b06f`. Its Apple iOS platform is configured with an APNs authentication key for `com.spike.kurage`. To use another OneSignal app, override this setting in the build configuration. Builds without a valid ID do not initialize the SDK and hide the notification entry.
3. Regenerate the project with `xcodegen generate` after editing `project.yml`. The main app and extension use the same version and App Group; Debug uses the development APNs environment and Release uses production.

The client never needs a OneSignal REST API key or an APNs private key. Do not put either in this repository or the app bundle. See [OneSignal's iOS setup guide](https://documentation.onesignal.com/docs/en/ios-sdk-setup) for Apple and OneSignal configuration.

## Official Lody notification path

Official Lody main `e73d3109` was inspected on 2026-10-04. Its [shared OneSignal client](https://github.com/LodyAI/Lody/blob/e73d3109b26412186d67571992a3ba1363433645/packages/components/src/lib/onesignal.ts) initializes the Web SDK or native Cordova plugin with `VITE_ONESIGNAL_APP_ID`. The [authenticated route](https://github.com/LodyAI/Lody/blob/e73d3109b26412186d67571992a3ba1363433645/packages/components/src/routes/%24workspaceName/_auth.tsx) binds `currentUser.id` through OneSignal login; the native adapter forwards the user ID. The [official notification guide](https://lody.ai/zh/docs/notification/) describes enabling notifications in the official browser or mobile client.

The official machine calls Convex notification actions with the CLI credential, recipient user ID, workspace, session and event. Those actions do not accept a OneSignal App ID, API key or third-party destination. The public repository exposes the Cloud protocol types but does not contain the hosted notification sender or deployment inventory. No official third-party App registration protocol or official confirmation of `ONE_SIGNAL_APPS` was found in the inspected sources and guide. The configuration below must not be treated as an established capability of the official hosted deployment.

## Third-party integration reference

The [Innei/lody-ios integration reference](https://github.com/Innei/lody-ios/blob/cebe0b9794a9ac1e99cf500aec9bc4758be5c79b/apps/mobile/PUSH_NOTIFICATIONS.md#enable-native-ios-on-the-existing-backend) describes a complete `ONE_SIGNAL_APPS` inventory. If the operator confirms that the deployment serving Kurage supports this contract and accepts Kurage as a destination, the candidate entry is:

```json
{
  "name": "kurage-ios",
  "appId": "199f71a9-c5a2-42c9-ac88-4b8b7593b06f",
  "apiKeyEnv": "ONE_SIGNAL_KURAGE_IOS_API_KEY",
  "push": true,
  "liveActivities": false
}
```

For a deployment confirmed to support this contract, the operator stores the corresponding REST API key in that Cloud environment variable. The contract is documented by lody-ios, not by the inspected official Lody sources. Kurage does not create its own backend or change Lody's notification event rules. In official Lody's current machine implementation, ordinary tool permission events can skip regular push if a Live Activity alert was successfully delivered; question events use ordinary push. Notification clicks open the conversation; they do not grant tool permission.

An explicit `ONE_SIGNAL_APPS` inventory replaces the legacy environment fallback, according to the integration reference. Before setting it, the operator must preserve both existing inventory entries and any targets currently supplied by that fallback. The JSON above is one array entry, not the complete deployment value. Convex environment variables belong to a specific deployment; configure the deployment serving the signed-in Lody account, under Deployment Settings → Environment Variables. See [Convex's environment variable documentation](https://docs.convex.dev/production/environment-variables).

## Sending targets and verification

There are two distinct identities in the delivery path:

- The sending app is Kurage's OneSignal App ID plus its matching server API key. The third-party reference proposes selecting it through a Cloud inventory; official hosted support remains unconfirmed.
- The recipient is the Lody account's user ID. Kurage calls `OneSignal.login(Account.id)`; OneSignal can target that identity through `include_aliases.external_id` with `target_channel: "push"`. See [OneSignal's audience targeting reference](https://documentation.onesignal.com/reference/create-message#aliases-emails-phone-numbers). The hosted backend's actual provider request has not been inspected.

[Official Lody `e73d3109` notification service](https://github.com/LodyAI/Lody/blob/e73d3109b26412186d67571992a3ba1363433645/apps/cli/src/lib/notifications/notification-service.ts) submits `notifications.notifySessionCompleted` and `notifications.notifyPermissionRequested` with the CLI credential, user ID, workspace and session event. It supplies no OneSignal App ID or API key. Its [public Cloud API contract](https://github.com/LodyAI/Lody/blob/e73d3109b26412186d67571992a3ba1363433645/packages/cloud-api/src/index.ts) returns `null` for these actions, with no provider message ID or recipient count; the CLI service also catches failures. An apparently successful turn therefore does not establish push delivery. The currently available Lody MCP tools expose no notification inventory or deployment configuration operation.

On 2026-10-04, the authenticated OneSignal dashboard showed Kurage's iOS platform active with `.p8` authentication for `com.spike.kurage`, one physical iPhone subscription marked `Subscribed`, and a linked user with an external ID. This establishes provider registration; the external ID has not been independently compared with the restored native account in this inspection. No test push was sent and Cloud activation remains unverified.

Validate delivery in this order: send a OneSignal test to that subscription; test targeting the same user external ID; then, after the Cloud operator confirms a supported sending configuration for Kurage, complete a normal Lody turn while the phone is locked and inspect the corresponding provider delivery record. Keep test content neutral and check the notification's session route. Ordinary tool permission events are unsuitable as the first delivery test because of the Live Activity suppression rule above.

## Client behavior

- Settings → Notifications requests iOS authorization only when the user enables notifications. The preference persists on this installation; registration status and iOS authorization are refreshed when returning to the foreground.
- After account restoration or sign-in, the SDK external ID is the authenticated `Account.id`. Sign-out opts out, logs out, clears delivered notifications and the badge, and discards pending clicks and visible-session state. Fixture launches never initialize OneSignal.
- The payload's `additionalData.route` must have the form `/workspaceSlug/sessions/sessionId` (a workspace ID also works). `recipientUserId`, when present, must match the restored account. Legacy payloads without that field use only the SDK identity captured at launch. If that identity is unknown, or the user signs out or restores/signs into another account, ownerless clicks and foreground presentation are rejected for the rest of that launch, including after signing back into the original account. Cold clicks wait for matching account restoration; duplicate IDs are ignored.
- The route is validated against the current account's workspace catalog and freshly synchronized session metadata. Direct child tabs resolve to their root, and a closed tab is reopened. Archived, deleted, side-panel and unavailable sessions are rejected. A workspace or session-list connection failure retains the click for Retry; a manual workspace selection discards it immediately. Retry uses the same foreground task as the initial click, including cancellation on background, account changes or a newer click.
- A foreground notification for the currently visible, connected conversation is suppressed. Notifications for another session or while a modal covers the conversation remain eligible for display, including the composer’s Advanced sheet, attachment preview and Photos, Files or Camera picker. Opening a notification for the same conversation dismisses those composer presentations without clearing its draft; a pending camera authorization cannot reopen the dismissed flow. This policy applies to SDK foreground callbacks; iOS handles background presentation.

## Validation

Fixture tests cover settings, cold clicks, child tabs and account mismatch; native tests cover authorization races, cancellation, workspace isolation and retry after a session-list failure. Native tests of the SDK callbacks' shared identity policy cover ownerless payloads after account changes, sign-out/re-login, unknown startup identity and delayed callbacks, while preserving matching cold restoration and explicit recipients. Hosted SwiftUI tests release new output only after Settings is presented, and verify that Advanced, attachment preview, Photos and Files pause reading and close on a same-session notification while preserving the draft. The iPad UI test checks the existing read state and draft without relying on a fixed loading delay. These tests do not establish APNs delivery, OneSignal device registration, physical-device camera authorization or hosted Cloud configuration.

After configuring the external services, verify on a signed physical device: OneSignal test delivery; actual Lody completion and question events; foreground, background, lock screen and cold launch; tab routing; and sign-out/account switching. Confirm the Cloud payload and recipient before treating ordinary tool-permission delivery as available.
