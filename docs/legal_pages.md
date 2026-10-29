# Farmspot policy pages and explicit agreement

The owner approved the content and modal design on 28 October 2026, including a general contact route through the association secretary or a Farmspot administrator. The current source catalog is version `2026-10-28-v2`, published in configuration. This does not mean the code/APK has been deployed or that the pages have received independent legal review.

## Content and presentation

The Terms of Service, Privacy Policy, Seller Agreement and ID & Permit Privacy Notice use short introductions and bullet points. The app index is Profile → Privacy & Terms. Inline links and index cards open a centered, bounded, scrollable modal without navigating away from the current flow.

Required agreement opens from an unchecked checkbox. The agreement button is disabled until the modal reaches the bottom (or all short content already fits). Cancel, close and the device back button do not accept anything. Scrolling is an interface requirement, not proof that a person understood every word.

## Flow locations

- Registration: review Terms and acknowledge Privacy before account creation.
- Seller activation: review the Seller Agreement; the server checks existing acceptance for this version.
- ID/permit setup: a separate document-processing checkbox before capture and before advancing with documents.
- Premium checkout: review the one-month plan/payment terms and Privacy before opening PayMongo. Checking an existing payment remains available so previously paid users can recover access.
- Login and Profile: policies remain readable without accepting them merely by opening a page.
- Public website: `/legal/terms`, `/legal/privacy`, `/legal/seller`, `/legal/verification`, linked from admin login.

## Real operational policies

General contact is the association secretary or a Farmspot administrator. No email address is invented. Replace `contact_text` with more specific details when the owner supplies them; `contact_email` is optional when a contact route is provided.

Documents are retained while needed for seller verification/administration. Removal requests are reviewed manually, considering open moderation, disputes and required records. **No automatic document-deletion job was added.** The team must actually handle requests using the published contact route.

Premium provides one month, with no automatic renewal. Duplicate/incorrect charges and paid access not delivered are reviewed individually using the payment reference. No automatic refund guarantee or blanket no-refunds rule is imposed; **no automated refund endpoint was added**.

## Updating/deploying

The canonical content is `website/resources/legal/policies.json`; copy it unchanged to `mobile/farmspot_app/assets/legal/policies.json`. A test checks equality. Content changes need a new version. Fill the operator, contact route and retention/refund fields before setting `published` true; incomplete catalogs are treated as drafts.

Run the legal-acceptances migration before deploying the backend, then rebuild the APK with the matching bundled policy version. New bundled content needs a new APK; existing V5 is unchanged unless explicitly rebuilt.

## Compatibility and evidence

Existing accounts are not backfilled as having agreed, and login is not blocked. Registration fields remain optional for older APKs; when supplied, version/acceptance fields are validated and recorded in the account-creation transaction. This is not blanket server enforcement against old/custom clients; mandatory whole-user enforcement requires a separate minimum-version transition.

Authenticated legal records contain account, document, version, immutable content snapshot/hash, action and server timestamp. Repeating acceptance does not replace the original timestamp. New versions do not automatically inherit prior acceptance. Additional farms do not repeat identity setup.

Official drafting references, not legal approval:
- https://privacy.gov.ph/the-right-to-be-informed/
- https://privacy.gov.ph/data-privacy-act-/
