# PayMongo Premium checkout

The app uses PayMongo Hosted Checkout to sell one month of Premium for PHP 2.00. Live checkout accepts QR Ph. Customers renew by making a new purchase after their access expires. Previously created checkouts retain their original prices and payment modes.

## Live QR Ph setup

1. Confirm QR Ph is active in your PayMongo dashboard in Live mode. Deploy the backend at a public HTTPS URL and run `php artisan migrate` to add the checkout mode field. Rebuild the mobile app and point it to that backend.
2. In the live PayMongo dashboard, register `https://YOUR_DOMAIN/api/paymongo/webhook` for `checkout_session.payment.paid`. Use the same backend base URL (including any deployment subpath) for the webhook and the return URL.
3. Set the following only on the server. Obtain the live secret API key and webhook signing secret from PayMongo. Refresh cached configuration after changing the values.

```dotenv
PAYMONGO_LIVE_CHECKOUT_ENABLED=true
PAYMONGO_TEST_CHECKOUT_ENABLED=false
PAYMONGO_SECRET_KEY=<live secret API key>
PAYMONGO_WEBHOOK_SECRET=<live endpoint signing secret>
PAYMONGO_RETURN_BASE_URL=https://YOUR_DOMAIN
```

4. Sign in as a user without active Premium. Open Premium checkout, confirm the PHP 2.00 amount, and open PayMongo. Display the QR code on a second screen and scan it with Maya, GCash, or a participating bank app. Confirm the payment in your wallet, return to FarmSpot, and tap **Check payment** if needed. Confirm that the payment is paid in the live PayMongo dashboard and that FarmSpot shows one month of access.

## Local setup

Keep the secret test key only in `website/.env`; never put it in Flutter or Git.

```
PAYMONGO_TEST_CHECKOUT_ENABLED=true
PAYMONGO_SECRET_KEY=<your secret test key>
PAYMONGO_RETURN_BASE_URL=http://127.0.0.1:8000
PAYMONGO_TEST_METHODS=card,gcash
```

Apply the checkout migrations and restart the local backend if configuration is cached. USB debug builds use the existing port 8000 reverse connection. Internet access is needed for both the backend and phone.

Use a free test account: Profile → Premium → Continue to checkout → Continue to PayMongo. Complete PayMongo's test flow using test payment details only. Return to FarmSpot and tap Check payment if it has not checked automatically. A successful server verification activates one month and refreshes Home/Profile. Existing Premium accounts keep their access and cannot buy another month while active.

Closing the browser, a pending payment, a failed payment, or visiting the success return page does not activate Premium. Pending orders are reused when reopening checkout. If account refresh fails after payment, Check payment can be retried without granting another month.

## Backend behavior

- `POST /api/premium/checkouts`: authenticated creation/reuse; account, amount and duration are server controlled.
- `GET /api/premium/checkouts/{id}`: authenticated owner only.
- `POST /api/premium/checkouts/{id}/verify`: retrieves the saved provider session. Checks the payment mode, session ID, order reference, paid status, amount and currency before a transaction credits Premium exactly once.
- `GET /api/paymongo/return`: instructions only; never grants access.
- `POST /api/paymongo/webhook`: checks the test or live signature, then retrieves the session from PayMongo before crediting the payment.

The `premium_checkout` table stores order ownership, provider creation payload, session/payment references, payment mode, amount, status and activation dates. Creation retries use a stable UUID Idempotency-Key and the identical payload. A CREATING order that remains unresolved beyond the idempotency window requires operator reconciliation with PayMongo before replacement. Verify an existing saved session to detect expiry before replacing it.

The simulate-purchase endpoint is blocked whenever PayMongo checkout is enabled.

## Test webhook

Local testing works through authenticated verification without a public webhook. For background activation while the app is closed, register a public HTTPS `/api/paymongo/webhook` endpoint for `checkout_session.payment.paid`, and set `PAYMONGO_WEBHOOK_SECRET` to that endpoint's signing secret. The handler verifies the test signature, raw body and a five minute timestamp window before looking up the saved session. Repeated events cannot extend the same purchase twice. This public webhook was not configured locally.

## Verification

- Backend: 14 tests, 84 assertions across PayMongoCheckoutTest and PremiumPurchaseTest, using an isolated in-memory database and fake provider responses.
- Flutter: 14 tests across premium_checkout_test, premium_access_test and premium_loading_test.
- Real provider connection check: created, retrieved and immediately expired one unpaid TEST checkout. Card and GCash were accepted. No account was changed and no payment was submitted. PayMongo v2 creation omits reference_number in its response, so the integration retrieves the canonical session before accepting it.
- A completed payment on the physical phone remains a manual test.

Official references: [Create checkout](https://docs.paymongo.com/reference/create_checkout_sessions_2), [Retrieve checkout](https://docs.paymongo.com/reference/get_checkout_sessions), [Idempotency](https://docs.paymongo.com/reference/idempotent-requests), [Hosted checkout](https://docs.paymongo.com/docs/payment-channels-hosted-checkout).

## Presentation wording

New PayMongo sessions display “FarmSpot Business Premium - Monthly Plan” with a feature description. Existing provider sessions retain their original copy.
