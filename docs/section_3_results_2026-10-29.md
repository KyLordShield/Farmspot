# Section 3 Android results - October 29, 2026

Scope: the eight Android checks from FarmSpot_Vulnerability_Testing_Guide_Simplified.pdf. Evidence comes from current Flutter/Android source, the available FarmspotV6.apk, read-only installed-package metadata, selected automated Flutter tests and isolated local Laravel tests. This is not a completed installed-release penetration test, nor a verification of all Render API behavior.

## Build identity matters

- Inspected artifact: apk/FarmspotV6.apk, package com.cloudsync.farmspot_app, versionName 1.0.0, versionCode 6, minSdk 26, targetSdk 36.
- APK SHA-256: 140758a7bdd4fdb19a245a6ceb2ff27f91c4fcf4b826e3d7a030ca758d5803e5.
- APK contains AOT libapp.so and no debug kernel snapshot; manifest does not declare debuggable. This is consistent with a release build, but it is signed with an Android Debug certificate.
- The connected phone has versionCode 2, versionName 1.0.0, with DEBUGGABLE and ALLOW_BACKUP package flags. It is not the inspected V6 release artifact. Its account data was not read. No APK was installed, no app was launched, and permissions/device settings were not changed.
- Current pubspec.yaml is version 1.0.0+2, another reason not to assume every current-source test describes the exact V6 binary.

## Checklist results

| No. | Check | Result | Short notes |
| --- | --- | --- | --- |
| 1 | HTTPS only | Not tested fully | V6 binary contains the HTTPS Render API/detector endpoints and did not contain the two searched HTTP localhost endpoint strings. Current release defaults, map tiles, routing and geocoding use HTTPS. APK has no explicit cleartext override or network-security-config attribute. No release-device login traffic capture was performed, so the guide's all-traffic/no-token-over-HTTP condition is not fully verified. |
| 2 | Permissions | Fail | V6 requests RECORD_AUDIO and READ_PHONE_STATE with no identified feature justification in the reviewed app code. Camera code explicitly sets enableAudio:false. Merger report attributes audio to camera_android_camerax and phone state to legacy TensorFlow Lite GPU manifest compatibility. Location, camera, gallery and notification permissions otherwise correspond to features. Merely declaring these extra permissions does not mean they were granted or used; on the connected debug app, audio/phone permissions were denied. |
| 3 | Local storage and logs | Fail | AuthService writes auth_token and the cached user record to SharedPreferences; no secure credential storage wrapper is used there. This confirms a current-source token-storage weakness. APK contains auth_token/user_data strings, but its full storage implementation was not decompiled. No real account storage, device backup or logcat extraction was performed. Ordinary other apps are not assumed able to read sandboxed preferences. |
| 4 | Role-restricted action | Pass, local backend scope | Synthetic Buyer and Farmer requests to admin pages and seller approve/reject actions returned 403; pending farm state stayed unchanged. Authorization is server-enforced rather than relying on hidden app buttons. A modified request from the installed app against Render was not executed, so this is not a hosted end-to-end Pass. |
| 5 | Invalid certificate | Not tested | Source search found no badCertificateCallback, HttpOverrides or custom trust-all certificate code. No staging endpoint with an invalid certificate was used from the installed release app. Absence of bypass code alone is not a runtime Pass. |
| 6 | Bad image | Not tested fully | Automated photo checks reject decoder/model failures and the UI shows an error while keeping failed photos out. Local Laravel gallery tests reject wrong-type/oversized images and accept a valid image with storage simulated. Malformed and oversized files were not submitted through an installed release app to staging. Source image-detection service reads uploads into a multipart request without a client byte cap; the separate detector's upload limits also need verification. |
| 7 | Release build | Fail | apksigner verified the V6 APK and identified its signing certificate as C=US, O=Android, CN=Android Debug. Current Gradle release config explicitly uses signingConfigs.getByName("debug"). Release manifest is not marked debuggable, but debug-key signing still fails release readiness. The phone's installed version 2 is itself debuggable. Dependency versions were recorded; no current vulnerability-advisory audit was completed, so dependency safety is unverified. |
| 8 | Map location | Not tested fully | Map uses API latitude/longitude directly. Farm setup lets the owner move and confirm the pin; bundled privacy text says public map pins are visible and exact location should be shared intentionally. Synthetic map widget tests pass, but the minimum necessary location precision, consent flow and effective published privacy notice were not validated together on the release device. Exact farm pins are not automatically classified as a vulnerability without that context. |

Summary: **1 scoped Pass, 3 Fail, 4 Not tested/incomplete, 0 N/A**. No overall Android security clearance is assigned. In particular, the scoped role result does not prove deployed Render authorization. Debug-only localhost defaults are not treated as proof that V6 sends credentials over HTTP.

## Evidence and tests

Inspected V6 with Android SDK aapt dump badging, aapt dump xmltree and apksigner verify --print-certs. Used ZIP inspection to check build artifacts and selected endpoint strings in arm64 libapp.so. Read installed package metadata via adb shell dumpsys package; did not inspect real user data or dump device logs.

V6 declares no debuggable, usesCleartextTraffic, networkSecurityConfig, allowBackup, fullBackupContent or dataExtractionRules attributes. Android platform defaults must be considered rather than treating an absent attribute as a failure. The release package has no explicit backup exclusions in the inspected manifest; actual device backup behavior was not tested.

Exported components in the release merged manifest include the launcher and OneSignal notification-open activity. Other exported Firebase/OneSignal receivers and AndroidX job/diagnostic components have sender, job-service or DUMP permission requirements. No exploit of an exported component was demonstrated.

Flutter run completed **25 tests, all passed** across:

- test/photo_moderation_test.dart
- test/photo_moderation_gate_test.dart
- test/camera_permission_service_test.dart
- test/map_screen_test.dart
- test/session_state_test.dart

Tests inject model responses and mocked platform/services; they do not establish native device inference, certificate handling or actual network traffic. Flutter cache access was required to run the selected tests. No live-account network tests were run.

Laravel rerun: **2 tests, 26 assertions, all passed**, selecting test_02_and_04 and test_14 in BackendChecklistTest.php. These use synthetic in-memory data and simulated valid-upload storage.

## Dependency inventory

Direct non-SDK versions from current pubspec.lock (not proof of every dependency packaged in V6): camera 0.12.1; cross_file 0.3.5+5; cupertino_icons 1.0.9; flutter_map 8.3.2; flutter_staggered_grid_view 0.7.0; geolocator 14.0.3; google_mlkit_text_recognition 0.17.1; http 1.6.0; image_picker 1.2.3; latlong2 0.9.1; lottie 3.6.1; nsfw_detector_flutter 2.0.2; onesignal_flutter 5.7.0; permission_handler 12.0.3; photo_manager 3.12.0; shared_preferences 2.5.5; url_launcher 6.3.2. Native transitive dependency CVEs were not audited. No statement that these dependencies are vulnerability-free is supported.

## Corrections and remaining work

1. Move bearer tokens to platform-backed secure storage and define backup exclusions. Avoid persisting unnecessary contact information in user_data.
2. Remove unjustified microphone/phone-state declarations from the final merged manifest after checking plugin compatibility.
3. Sign distribution builds with a dedicated release/upload key. The V6 app is not claimed to be debuggable merely because its certificate says Android Debug.
4. Use a known staging build and dummy accounts to capture traffic, test invalid certificates, test full malformed/oversized uploads, verify modified-role requests and inspect location/privacy behavior. Keep the installed debug app and V6 release artifact separate in the evidence.

Only this report was added for section 3; no app/backend code, signing keys, accounts, APK installation or device settings were changed.

Android reference: [Network security configuration](https://developer.android.com/privacy-and-security/security-config) documents platform cleartext defaults; [application manifest attributes](https://developer.android.com/guide/topics/manifest/application-element) documents debuggable, backup and cleartext attributes. These references explain defaults, not the unperformed runtime checks.
