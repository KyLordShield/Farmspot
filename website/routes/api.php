<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ListingController;
use App\Http\Controllers\Api\ListingReviewController;
use App\Http\Controllers\Api\ListingCreateController;
use App\Http\Controllers\Api\ListingPhotoController;
use App\Http\Controllers\Api\FarmerListingController;
use App\Http\Controllers\Api\SellerController;
use App\Http\Controllers\Api\SellerDirectoryController;
use App\Http\Controllers\Api\SearchController;
use App\Http\Controllers\Api\UserProfileController;
use App\Http\Controllers\Api\FarmController;
use App\Http\Controllers\Api\UserStatsController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\InsightsController;
use App\Http\Controllers\Api\ConversationController;
use App\Http\Controllers\Api\ReportController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\PasswordResetController;
use App\Http\Controllers\Api\AiChatController;
use App\Http\Controllers\Api\Admin\SellerRequestController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/paymongo/return', [\App\Http\Controllers\Api\PayMongoCheckoutController::class, 'returned']);
Route::post('/paymongo/webhook', [\App\Http\Controllers\Api\PayMongoCheckoutController::class, 'webhook'])->middleware('throttle:60,1');

Route::get('/legal', [\App\Http\Controllers\LegalController::class, 'index']);

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);

// Password reset for app users, by emailed 6-digit code.
//
// Public, and deliberately so - someone who cannot log in is by definition not
// holding a token. The admin panel has no equivalent; those routes and views
// were removed by owner decision (docs/admin_audit_report.md, S1).
//
// Throttled hard because this is the one unauthenticated endpoint that can
// change a credential. 3 requests/minute per IP on request-code, since each one
// can cost an SMTP round trip and, more importantly, 3/minute on reset attempts
// keeps a 6-digit code well out of reach of an online guesser. The per-code
// attempt cap in the controller is the second lock; this is the first.
Route::post('/forgot-password', [PasswordResetController::class, 'requestCode'])
    ->middleware('throttle:3,1');
Route::post('/reset-password', [PasswordResetController::class, 'resetPassword'])
    ->middleware('throttle:5,1');

// Appeals (public for account; listing appeals require auth below). The account
// appeal checks email+password and is heavily throttled to stop someone fishing
// for which deactivated emails exist or guessing passwords against a known email.
Route::post('/appeals/account', [\App\Http\Controllers\Api\AppealController::class, 'storeAccount'])
    ->middleware('throttle:5,1');

Route::get('/listings', [ListingController::class, 'index']);
Route::get('/listings/{id}', [ListingController::class, 'show']);
// Public, like the listing detail it sits on: reviews are shown on a public
// page, and an optional bearer token only adds `my_review` + `can_review`.
Route::get('/listings/{listingId}/reviews', [ListingReviewController::class, 'index']);
Route::get('/crop-categories', [ListingController::class, 'cropCategories']);
Route::get('/insights', [InsightsController::class, 'show']);
Route::get('/farms/public', [FarmController::class, 'mapPins']);
Route::get('/farms/{farmId}/profile', [FarmController::class, 'profile']);

// Combined buyer search: crops + farms + sellers in one call. Side-effect free
// (never writes search_log) because the search screen hits it on every debounced
// keystroke; the crop grid and the logging still come from GET /listings.
Route::get('/search', [SearchController::class, 'index']);
// Seller directory + public seller profile. A seller is a farmer record, the
// same identity a buyer can report against.
Route::get('/sellers', [SellerDirectoryController::class, 'index']);
Route::get('/sellers/{farmerId}', [SellerDirectoryController::class, 'show']);

// Public user profile: the person behind a farm, a chat, or a search seller
// row. Keyed on the account so a pure buyer (no farmer row) can be shown too.
Route::get('/users/{userId}/profile', [UserProfileController::class, 'show']);

Route::middleware(['auth:sanctum', 'active'])->group(function () {
    Route::get('/legal/acceptances', [\App\Http\Controllers\LegalController::class, 'acceptances']);
    Route::post('/legal/acceptances', [\App\Http\Controllers\LegalController::class, 'accept'])->middleware('throttle:20,1');
    Route::get('/premium/alert-settings', [\App\Http\Controllers\Api\PremiumAlertSettingsController::class, 'show']);
    Route::put('/premium/alert-settings', [\App\Http\Controllers\Api\PremiumAlertSettingsController::class, 'update']);
    Route::get('/sourcing/list', [\App\Http\Controllers\Api\SourcingController::class, 'show']);
    Route::put('/sourcing/list', [\App\Http\Controllers\Api\SourcingController::class, 'update']);
    Route::post('/sourcing/matches', [\App\Http\Controllers\Api\SourcingController::class, 'matches'])->middleware('throttle:30,1');
    Route::get('/saved-farms', [\App\Http\Controllers\Api\SavedFarmController::class, 'index']);
    Route::put('/saved-farms/{farmId}', [\App\Http\Controllers\Api\SavedFarmController::class, 'store'])->middleware('throttle:30,1');
    Route::delete('/saved-farms/{farmId}', [\App\Http\Controllers\Api\SavedFarmController::class, 'destroy']);
    Route::get('/buy-request-crops', [\App\Http\Controllers\Api\BuyRequestController::class, 'crops']);
    Route::get('/buy-requests/mine', [\App\Http\Controllers\Api\BuyRequestController::class, 'mine']);
    Route::get('/buy-requests', [\App\Http\Controllers\Api\BuyRequestController::class, 'index']);
    Route::post('/buy-requests', [\App\Http\Controllers\Api\BuyRequestController::class, 'store'])->middleware('throttle:10,1');
    Route::patch('/buy-requests/{id}', [\App\Http\Controllers\Api\BuyRequestController::class, 'update'])->middleware('throttle:10,1');
    Route::delete('/buy-requests/{id}', [\App\Http\Controllers\Api\BuyRequestController::class, 'destroy']);
    Route::post('/buy-requests/{id}/conversation', [ConversationController::class, 'storeForBuyRequest'])->middleware('throttle:20,1');
    Route::get('/buy-requests/{id}/conversations', [ConversationController::class, 'requestResponses']);
    Route::post('/premium/checkouts', [\App\Http\Controllers\Api\PayMongoCheckoutController::class, 'store'])->middleware('throttle:5,1');
    Route::get('/premium/checkouts/{id}', [\App\Http\Controllers\Api\PayMongoCheckoutController::class, 'show']);
    Route::post('/premium/checkouts/{id}/verify', [\App\Http\Controllers\Api\PayMongoCheckoutController::class, 'verify'])->middleware('throttle:20,1');
    Route::get('/premium', [\App\Http\Controllers\Api\PremiumController::class, 'show']);
    Route::post('/premium/simulate-purchase', [\App\Http\Controllers\Api\PremiumController::class, 'simulatePurchase'])
        ->middleware('throttle:5,1');
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::post('/seller/activate', [SellerController::class, 'activate']);
    Route::post('/seller/deactivate', [SellerController::class, 'deactivate']);
    Route::post('/farms', [FarmController::class, 'store']);
    Route::get('/farms', [FarmController::class, 'index']);
    Route::post('/farms/{farmId}/log-visit', [FarmController::class, 'logVisit']);
    Route::get('/farms/{farmId}/stats', [FarmController::class, 'stats']);
    Route::post('/listings', [ListingCreateController::class, 'store']);
    Route::post('/listings/{listingId}/log-contact', [ListingController::class, 'logContact']);
    Route::post('/listings/{listingId}/reviews', [ListingReviewController::class, 'store']);
    Route::delete('/listings/{listingId}/reviews', [ListingReviewController::class, 'destroy']);
    Route::get('/my-listings', [FarmerListingController::class, 'myListings']);
    Route::post('/listings', [ListingCreateController::class, 'store']);
    Route::patch('/listings/{id}', [FarmerListingController::class, 'update']);
    Route::post('/listings/{id}/photo', [FarmerListingController::class, 'uploadPhoto']);
    Route::post('/listings/{id}/photos', [ListingPhotoController::class, 'store']);
    Route::patch('/listings/{id}/photos/{photoId}/primary', [ListingPhotoController::class, 'setPrimary']);
    Route::delete('/listings/{id}/photos/{photoId}', [ListingPhotoController::class, 'destroy']);
    Route::post('/listings/{listing}/appeal', [\App\Http\Controllers\Api\AppealController::class, 'storeListing']);
    Route::delete('/listings/{id}', [FarmerListingController::class, 'destroy']);
    Route::patch('/listings/{id}/status', [FarmerListingController::class, 'updateStatus']);
    Route::post('/listings/{id}/renew', [FarmerListingController::class, 'renew']);
    Route::patch('/farms/{id}', [FarmController::class, 'update']);
Route::delete('/farms/{farmId}', [FarmController::class, 'destroy']);
    Route::post('/farms/{id}/photos', [FarmController::class, 'addPhotos']);
Route::put('/farms/{farmId}/photos/{photoId}/primary', [FarmController::class, 'setPrimaryPhoto']);
Route::delete('/farms/{farmId}/photos/{photoId}', [FarmController::class, 'destroyPhoto']);

    // Farming assistant. Throttled per user to sit under the provider's free
    // 30 requests/minute, so one client cannot eat the shared budget.
    Route::post('/ai/chat', [AiChatController::class, 'chat'])->middleware('throttle:20,1');

    // In-app buyer <-> seller messaging.
    Route::get('/conversations', [ConversationController::class, 'index']);
    Route::post('/conversations', [ConversationController::class, 'store']);
    Route::get('/conversations/{id}/messages', [ConversationController::class, 'messages']);
    Route::post('/conversations/{id}/messages', [ConversationController::class, 'sendMessage']);

    // Reporting a listing, a chat message, a farmer/seller or another user.
    // Throttled because a report is a moderation accusation: one client must
    // not be able to fill a moderator's queue faster than it can be read. The
    // controller also refuses an identical repeat within a day, so a retry on a
    // dropped connection does not become a second row.
Route::post('/reports', [ReportController::class, 'store'])->middleware('throttle:10,1');

    // The notification inbox, served from the `notification` table (lowercase,
    // as UserNotification declares it — MySQL on Linux compares table names
    // case-sensitively, and an uppercase spelling here is a production-only 500).
    //
    // This replaces the two placeholder routes that used to sit here
    // (GET /notifications and POST /notifications/read), which read Laravel's
    // own `notifications` table. That table cannot be de-duplicated against and
    // was a second, parallel inbox; report updates now land here as
    // REPORT_UPDATE rows, so everything is in one list.
    //
    // The two static paths are declared before the {id} route on purpose. With
    // the wildcard first, "unread-count" and "read-all" are just another id:
    // Laravel would try to mark a notification whose id is the string
    // "unread-count" read, find nothing, and answer 404 to both of them.
    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::patch('/notifications/read-all', [NotificationController::class, 'markAllAsRead']);
    Route::patch('/notifications/{id}/read', [NotificationController::class, 'markAsRead']);

    Route::get('/user', function (Request $request) {
        return $request->user();
    });
    Route::patch('/user', [UserController::class, 'update']);
    Route::post('/user/photo', [UserController::class, 'uploadPhoto']);
    Route::get('/user/stats', [UserStatsController::class, 'show']);
});

Route::middleware(['auth:sanctum', 'active', 'admin'])->prefix('admin')->group(function () {
    Route::get('/seller-requests', [SellerRequestController::class, 'index']);
    Route::post('/seller-requests/{farmId}/approve', [SellerRequestController::class, 'approve']);
    Route::post('/seller-requests/{farmId}/reject', [SellerRequestController::class, 'reject']);
});
