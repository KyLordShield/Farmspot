# PayMongo test Premium checkout

The app uses PayMongo hosted checkout for one month of Premium. The fixed test amount is PHP 99.00 (9900 centavos). This is a test amount, not a finalized selling price. There is no real charge and no automatic renewal. Live keys and live checkout sessions are rejected.

## Local setup

Keep the secret test key only in `website/.env`; never put it in Flutter or Git.

```
PAYMONGO_TEST_CHECKOUT_ENABLED=true
PAYMONGO_SECRET_KEY=<your secret test key>
PAYMONGO_RETURN_BASE_URL=http://127.0.0.1:8000
PAYMONGO_TEST_METHODS=card,gcash
```

Apply `2026_10_25_000003_create_premium_checkout.php` and restart the local backend if configuration is cached. USB debug builds use the existing port 8000 reverse connection. Internet access is needed for both the backend and phone.

Use a free test account: Profile → Premium → Continue to checkout → Continue to PayMongo. Complete PayMongo's test flow using test payment details only. Return to FarmSpot and tap Check payment if it has not checked automatically. A successful server verification activates one month and refreshes Home/Profile. Existing Premium accounts keep their access and cannot buy another month while active.

Closing the browser, a pending payment, a failed payment, or visiting the success return page does not activate Premium. Pending orders are reused when reopening checkout. If account refresh fails after payment, Check payment can be retried without granting another month.

## Backend behavior

- `POST /api/premium/checkouts`: authenticated creation/reuse; account, amount and duration are server controlled.
- `GET /api/premium/checkouts/{id}`: authenticated owner only.
- `POST /api/premium/checkouts/{id}/verify`: retrieves the saved provider session. Checks test mode, session ID, order reference, paid status, amount and currency before a transaction credits Premium exactly once.
- `GET /api/paymongo/return`: instructions only; never grants access.
- `POST /api/paymongo/webhook`: optional signed test event followed by authoritative provider retrieval.

The `premium_checkout` table stores order ownership, stable provider creation payload, session/payment references, test amount, status and activation dates. It stores no card details. Creation retries use a stable UUID Idempotency-Key and the identical payload. An unresolved order older than 23 hours requires investigation rather than silently risking another payable session. Verify an existing saved session to detect expiry before replacing it. A CREATING order that remains unresolved beyond the idempotency window requires operator reconciliation with PayMongo before replacement.

When PayMongo test checkout is enabled, the old direct simulate-purchase endpoint is blocked. The existing simulation remains available only on servers explicitly running with PayMongo disabled. This is development behavior; live billing is not implemented.

## Optional webhook

Local testing works through authenticated verification without a public webhook. For background activation while the app is closed, register a public HTTPS `/api/paymongo/webhook` endpoint for `checkout_session.payment.paid`, and set `PAYMONGO_WEBHOOK_SECRET` to that endpoint's signing secret. The handler verifies the test signature, raw body and a five minute timestamp window before looking up the saved session. Repeated events cannot extend the same purchase twice. This public webhook was not configured locally.

## Verification

- Backend: 14 tests, 84 assertions across PayMongoCheckoutTest and PremiumPurchaseTest, using an isolated in-memory database and fake provider responses.
- Flutter: 14 tests across premium_checkout_test, premium_access_test and premium_loading_test.
- Real provider connection check: created, retrieved and immediately expired one unpaid TEST checkout. Card and GCash were accepted. No account was changed and no payment was submitted. PayMongo v2 creation omits reference_number in its response, so the integration retrieves the canonical session before accepting it.
- A completed payment on the physical phone remains a manual test.

Official references: [Create checkout](https://docs.paymongo.com/reference/create_checkout_sessions_2), [Retrieve checkout](https://docs.paymongo.com/reference/get_checkout_sessions), [Idempotency](https://docs.paymongo.com/reference/idempotent-requests), [Hosted checkout](https://docs.paymongo.com/docs/payment-channels-hosted-checkout).

## Presentation wording

The app uses regular subscription wording, and new PayMongo sessions display “FarmSpot Business Premium - Monthly Plan” with a feature description. Payment mode is still test-only. Existing provider sessions retain their original copy; replace an unpaid session only after confirming provider expiry.
