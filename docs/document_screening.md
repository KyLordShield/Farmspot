# Farm setup document screening

Step 2 in the Flutter app captures the government ID and farm permit/certificate
using the in-app camera only. The camera runs at the existing high preset
(typically 720p), and is closed before OCR starts. This avoids launching a second
camera app that can cause Android to kill Farmspot in the background. It runs Latin-script ML Kit text recognition on the phone;
there is no OCR service to host and no OCR API key. The backend continues to store
the photos and create a pending admin review request as before.

The ID needs a supported document-type phrase and a recognizable field. Its text
must contain the seller account's name tokens (case, punctuation, word order and
middle initials are tolerated). The permit/certificate needs a document title
and a supporting field; it does not need the person's name because it can name a
business. The document rules live in `DocumentTextCheck`.

These are client-side convenience checks, not authenticity verification or a
server security boundary. A photo of text mimicking an ID can pass. Admins must
continue inspecting both documents. Blurry images, glare, unsupported document
titles and OCR mistakes can reject legitimate documents; the user can retake.

## Platform and release checks

- Android and iOS only; ML Kit's Flutter plugin does not support web/desktop.
- Minimum iOS version is now 15.5, as required by the plugin.
- On Windows, Flutter plugin setup may require Developer Mode for symlinks.
- Rebuild the app after installing dependencies; a hot reload cannot load a new
  native plugin.
- On a real phone, test camera permission denial, cancellation, glare, a random
  scene, a matching ID, a different person's ID, a permit and certificate, retakes,
  and navigation back from Step 3. Verify admin review still receives both photos.
- Confirm that additional farms still inherit their existing documents and skip
  Step 2, as before.

Automated coverage includes document keyword screening, name matching, rejected
captures, capture cancellation, OCR errors, required documents and wizard routing.
