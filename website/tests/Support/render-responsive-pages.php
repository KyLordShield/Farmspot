<?php
// Render real templates with synthetic data only; no database or login needed.
require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
config(['session.driver' => 'array']);
view()->share('errors', new Illuminate\Support\ViewErrorBag);
$user = new App\Models\User(['USR_ID' => 'MOB001', 'USR_NAME' => 'Maria Jane Dela Cruz',
    'USR_EMAIL' => 'maria.jane.delacruz@example.test', 'USR_ROLE' => 'GENERAL_USER',
    'USR_STATUS' => 'ACTIVE', 'USR_IS_SELLER' => 1, 'USR_MOBILE_NUMBER' => '09171234567']);
auth()->setUser($user);
$buyer = new App\Models\Buyer;
$buyer->setRelation('user', $user);
$farmer = new App\Models\Farmer;
$farmer->setRelation('buyer', $buyer);
$farm = new App\Models\Farm(['FRM_ID' => 'FARM01', 'FRM_NAME' => 'Fresh Produce Community Farm',
    'FRM_BARANGAY' => 'Agus, Lapu-Lapu City, Cebu', 'FRM_STATUS' => 'PENDING_REVIEW', 'FRM_CREATED_AT' => now()]);
$farm->setRelation('farmer', $farmer)->setRelation('photos', collect());
$farmer->setRelation('farms', collect([$farm]));
$listing = new App\Models\Listing(['LST_ID' => 'LIST01', 'LST_CROP_ICON' => 'Freshly harvested cabbage',
    'LST_DESCRIPTION' => str_repeat('Locally grown produce. ', 15), 'LST_STATUS' => 'AVAILABLE_NOW', 'LST_AVAILABILITY' => 'ACTIVE',
    'LST_PRICE' => 45, 'LST_QUANTITY' => 100, 'LST_UNIT' => 'kg', 'LST_CREATED_AT' => now()]);
$listing->setRelation('farmer', $farmer)->setRelation('farm', $farm)->setRelation('category', null)->setRelation('photos', collect());
$appeal = new App\Models\ReviewRequest(['RRQ_ID' => 'APPE01', 'USR_ID' => 'MOB001',
    'RRQ_TARGET_TYPE' => 'USER', 'RRQ_TARGET_ID' => 'MOB001', 'RRQ_STATUS' => 'PENDING', 'RRQ_CREATED_AT' => now()]);
$appeal->setRelation('user', $user)->setRelation('account', $user)->setRelation('decidedBy', null);
$page = fn ($items) => new Illuminate\Pagination\LengthAwarePaginator($items, 50, 10);
$report = new App\Models\Report(['RPT_ID' => 'REP001', 'RPT_TARGET_TYPE' => 'USER', 'RPT_TARGET_ID' => 'MOB001',
    'RPT_STATUS' => 'Reviewing', 'RPT_REASON' => 'Review requested', 'RPT_CREATED_AT' => now(), 'RPT_DETAILS' => 'Please review this account.']);
$report->setRelation('user', $user)->setRelation('reportedUser', $user)->setRelation('actions', collect());
$pages = [
    'users' => ['users', ['users' => $page([$user]), 'counts' => ['total' => 50, 'active' => 40, 'farmers' => 20, 'deactivated' => 10]]],
    'listings' => ['listings', ['listings' => $page([$listing]), 'categories' => collect()]],
    'listing-edit' => ['listings.edit', ['listing' => $listing, 'categories' => collect(), 'farms' => collect([$farm])]],
    'listing-details' => ['listings.show', ['listing' => $listing]],
    'user-details' => ['users.show', ['user' => $user, 'farmer' => $farmer]],
    'seller-requests' => ['seller-requests', ['sellerRequests' => $page([$farm])]],
    'seller-details' => ['seller-requests.show', ['farm' => $farm]],
    'appeals' => ['appeals', ['appeals' => $page([$appeal]), 'counts' => collect(['PENDING' => 1])]],
    'appeal-details' => ['appeals.show', ['appeal' => $appeal]],
    'reports' => ['reports', ['reports' => $page([]), 'totalReports' => 20, 'flaggedTargetCount' => 1, 'counts' => collect()]],
    'reports-populated' => ['reports', ['reports' => $page([$report]), 'totalReports' => 20, 'flaggedTargetCount' => 1, 'counts' => collect()]],
    'mass-reports' => ['reports.flagged', ['threshold' => 10, 'alerts' => [[
        'type' => 'USER', 'id' => 'MOB001', 'icon' => 'person', 'name' => $user->USR_NAME,
        'url' => route('users.show', 'MOB001'), 'type_label' => 'User',
        'subtitle' => 'User account · '.$user->USR_EMAIL, 'first_at' => now(), 'last_at' => now(),
        'reporter_count' => 10, 'open_count' => 10,
    ]]]],
    'reviews' => ['reviews', ['reviews' => $page([]), 'visibleCount' => 10, 'hiddenCount' => 2]],
    'report-details' => ['reports.show', ['report' => $report, 'reporterCount' => 10,
        'actionLabels' => App\Models\Report::ACTION_LABELS, 'options' => [], 'blocked' => []]],
    'dashboard' => ['dashboard', ['users' => 50, 'buyers' => 40, 'farmers' => 20, 'listings' => 50, 'reports' => 12,
        'recentUsers' => collect([$user]), 'recentListings' => collect([$listing]), 'recentReports' => collect([$report]),
        'notes' => collect(), 'events' => collect(), 'calendarItems' => [], 'plannerReady' => true,
        'newReports' => 12, 'flaggedTargets' => 2, 'pendingSellerRequests' => 3, 'pendingAppeals' => 1,
        'recentActivity' => collect(), 'weather' => null]],
    'analytics' => ['analytics', ['totalUsers' => 50, 'totalFarmers' => 20, 'totalBuyers' => 40,
        'totalListings' => 30, 'totalReports' => 15, 'searchesToday' => 12, 'asOf' => now(), 'range' => 'week',
        'filters' => ['start' => '2026-11-01', 'end' => '2026-11-22'], 'weekLabel' => 'This week', 'monthLabel' => 'November',
        'topSearches' => collect(), 'allSearches' => 0, 'growthLabels' => ['October', 'November'], 'growthValues' => [5, 10],
        'monthlyTrends' => [['month' => 'November 2026', 'crop' => 'Cabbage', 'top_count' => 10, 'total' => 20]]]],
    'profile' => ['profile.edit', ['user' => $user, 'resetVerified' => false, 'resetCodeSent' => false]],
    'profile-code' => ['profile.edit', ['user' => $user, 'resetVerified' => false, 'resetCodeSent' => true, 'resetReference' => 'RESET-1234']],
    'login' => ['auth.login', []],
];
$out = storage_path('framework/testing/responsive');
if (!is_dir($out)) mkdir($out, 0777, true);
foreach ($pages as $name => [$view, $data]) {
    try {
        file_put_contents($out.'/'.$name.'.html', view($view, $data)->render());
        echo $name." rendered\n";
    } catch (Throwable $e) { fwrite(STDERR, $name.': '.$e->getMessage()."\n"); exit(1); }
}
