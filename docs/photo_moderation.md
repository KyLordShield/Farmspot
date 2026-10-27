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
form interaction while checking. A score >= 0.30 rejects the image. Decode,
unsupported-platform, model, and invalid-score failures also reject it. Safe
photos in a mixed selection remain available. No review queue or external
moderation request is involved. Debug builds log scores, the allow/block decision,
and elapsed time to the local development console. They do not log image bytes,
filenames, or user identifiers. Release builds do not emit these diagnostics.
Debug builds also show a results dialog after every selection batch, with photos
numbered in selection order, scores, allow/block decisions, and elapsed times.
`Copy results` copies this text without image data or filenames. `Done` closes
the dialog; it cannot override a rejection. Failed checks show an unavailable
score and remain blocked. This dialog is guarded by `kDebugMode` and is excluded
from release/profile behavior. No history is saved after the dialog is dismissed.

Android minimum SDK is 26 (Android 8). Android is the build target of this trial;
the Android build aligns tflite_flutter's Kotlin target with its Java 11 target
for compatibility with this project's AGP 9 setup. GPU delegate R8 rules are
included for release packaging; release signing remains the app's existing setup.
iOS needs separate build/device verification and the package's documented Xcode
Strip Linked Product setting before it can be considered supported. Web/desktop
native inference is not supported by this integration and fails closed.

## Verification

Initial trial validation: 24 relevant widget tests passed, including the moderation gate,
photo limits/renewal, category suggestions, farm verification, and input limits.
The new screening files passed static analysis. The connected screens have one
pre-existing braces-style lint in AddCropScreen. The Android debug APK built
successfully; its archive contains the model and ARM64 TensorFlow CPU/GPU runtime
libraries. A release APK also built successfully after adding targeted R8 rules
for the optional non-Latin OCR modules and was copied to `apk/FarmspotV4.apk`.
The release uses the project's existing signing setup.

User testing subsequently confirmed blocking of some obvious adult images, but
also reported exposed-breast and partial-nudity images passing. The threshold was
subsequently lowered from 0.70 to 0.40 for stricter debug testing, with local score
diagnostics added. This rejects borderline scores previously allowed but cannot
correct images that the model confidently misclassifies. No replacement model has
been implemented. The previously built V4 APK still uses the original 0.70 cutoff.
Further user testing reported scores of 0.0831 and 0.3260 for images described as
explicit. At the user's request, the debug trial cutoff was lowered again to
0.30. This blocks the 0.3260 example but still allows the 0.0831 example. It is a
trial setting, not a validated safety boundary, and may reject harmless photos.
Accuracy and performance have not been systematically measured. Development
continues in debug mode; build another release only when requested.
The stricter cutoff passed 15 targeted tests covering score boundaries, invalid
scores, inference failures, the moderation gate, photo limits, and renewal flows.
These use injected model results and do not establish accuracy on real photos.

Run from `mobile/farmspot_app`:

```
flutter test test/photo_moderation_test.dart test/photo_moderation_gate_test.dart test/photo_limits_test.dart test/renew_listing_sheet_test.dart
flutter run
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
