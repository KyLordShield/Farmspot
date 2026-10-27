# On-device farm and listing photo screening trial

Farm setup, farm editing, listing creation/editing, and listing renewal screen
newly selected photos before adding them to the form. Existing uploaded photos,
profile pictures, identity documents, chat attachments, and image searches are
outside this trial's scope.

The app uses `nsfw_detector_flutter` 2.0.2 and its bundled Yahoo/open_nsfw-derived
TensorFlow Lite model. This is **not** NSFWJS/MobileNet. The actual model file is
23,591,976 bytes (about 22.5 MiB); runtime libraries also affect installed size.
The package and model retain their MIT and BSD notices in the dependency.

Each photo is checked sequentially using the package's background-isolate API.
The package loads and closes a native interpreter per check. It resizes input
internally; original upload files are retained. The modal blocks navigation and
form interaction while checking. A score >= 0.70 rejects the image. Decode,
unsupported-platform, model, and invalid-score failures also reject it. Safe
photos in a mixed selection remain available. No review queue or external
moderation request is involved. No scores or image bytes are logged by this code.

Android minimum SDK is 26 (Android 8). Android is the build target of this trial;
the Android build aligns tflite_flutter's Kotlin target with its Java 11 target
for compatibility with this project's AGP 9 setup. GPU delegate R8 rules are
included for release packaging; release signing remains the app's existing setup.
iOS needs separate build/device verification and the package's documented Xcode
Strip Linked Product setting before it can be considered supported. Web/desktop
native inference is not supported by this integration and fails closed.

## Verification

Trial validation: 24 relevant widget tests passed, including the moderation gate,
photo limits/renewal, category suggestions, farm verification, and input limits.
The new screening files passed static analysis. The connected screens have one
pre-existing braces-style lint in AddCropScreen. The Android debug APK built
successfully; its archive contains the model and ARM64 TensorFlow CPU/GPU runtime
libraries. A release APK also built successfully after adding targeted R8 rules
for the optional non-Latin OCR modules and was copied to `apk/FarmspotV4.apk`.
The release uses the project's existing signing setup.

User testing subsequently confirmed blocking of some obvious adult images, but
also reported exposed-breast and partial-nudity images passing. The threshold is
still 0.70; no stricter threshold or replacement model has been implemented.
Accuracy and performance have not been systematically measured. Development
continues in debug mode; build another release only when requested.

Run from `mobile/farmspot_app`:

```
flutter test test/photo_moderation_gate_test.dart test/photo_limits_test.dart test/renew_listing_sheet_test.dart
flutter build apk --debug
```

Widget tests use injected decisions, not native inference. They verify rejection,
check failures, mixed selections, navigation blocking, and existing photo limits
and renewal behavior. They cannot establish model accuracy or device performance.

On an Android phone, try gallery and camera selection for all four flows, an
ordinary crop/farm image, an unreadable file, and representative images from a
lawfully held moderation evaluation set. Confirm rejected photos never enter the
form, approved ones can upload, and back navigation cannot interrupt a check.
Measure cold and subsequent check times, memory, responsiveness, and APK size on
a lower-end phone. Calibrate the threshold using safe farm photos and an appropriate
evaluation set before treating the filter as production-ready.

This is probabilistic device-side screening: false positives and false negatives
remain possible. It is bypassable by modified clients/direct API requests. The
server does not independently enforce the moderation decision.
