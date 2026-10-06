<?php

use App\Http\Controllers\ProfileController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\AnalyticsController;
use App\Http\Controllers\CropCategoryController;
use App\Http\Controllers\ListingController;
use App\Http\Controllers\ReportController;
use App\Http\Controllers\UserController;
use App\Http\Controllers\WhitelistController;
use App\Http\Controllers\ReviewController;
use App\Http\Controllers\SellerRequestController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return redirect()->route('login');
});

// The whole block below is the admin panel. It was guarded by `auth` alone, so
// any signed-in web account could open /reports and read reported message text
// and the names of the people accused, or reach /users and /whitelist. Now that
// reports can be filed from the app, that is a real leak rather than a
// theoretical one.
Route::middleware(['auth', 'admin'])->group(function () {
    Route::get('/dashboard', [DashboardController::class, 'index'])->name('dashboard');
    Route::get('/analytics', [AnalyticsController::class, 'index'])->name('analytics');
    Route::get('/listings', [ListingController::class, 'index'])->name('listings');
    Route::get('/listings/{id}/edit', [ListingController::class, 'edit'])->name('listings.edit');
    Route::get('/listings/{id}', [ListingController::class, 'show'])->name('listings.show');
    Route::put('/listings/{id}', [ListingController::class, 'update'])->name('listings.update');
    Route::delete('/listings/{id}', [ListingController::class, 'destroy'])->name('listings.destroy');

    // Crop categories, managed from a panel on the Listings page rather than from a
    // page of their own — a category only matters here because of the listings it
    // classifies, and an extra nav item for five rows is not worth it.
    //
    // There is deliberately no GET /categories: the only way to see the list is
    // alongside the listings it filters, which keeps the two in one place. The
    // writes are real POST/PUT/DELETE rather than an ajax endpoint, so they carry
    // CSRF protection like every other admin action.
    Route::post('/categories', [CropCategoryController::class, 'store'])->name('categories.store');
    Route::put('/categories/{id}', [CropCategoryController::class, 'update'])->name('categories.update');
    Route::delete('/categories/{id}', [CropCategoryController::class, 'destroy'])->name('categories.destroy');
    Route::get('/reports', [ReportController::class, 'index'])->name('reports');
    Route::get('/reports/{id}', [ReportController::class, 'show'])->name('reports.show');
    Route::patch('/reports/{id}/status', [ReportController::class, 'updateStatus'])->name('reports.updateStatus');
    // The part that makes the queue worth having: a moderator who agrees a
    // listing is fraudulent needs to be able to take it off sale, and needs to be
    // able to put it back when they were wrong.
    //
    // The literal undo path has to be declared before the {action} wildcard,
    // otherwise "undo" is just another action name and undoAction is never
    // reachable.
    Route::post('/reports/{id}/action/undo', [ReportController::class, 'undoAction'])->name('reports.undoAction');
    Route::post('/reports/{id}/action/{action}', [ReportController::class, 'applyAction'])->name('reports.applyAction');
    Route::get('/users', [UserController::class, 'index'])->name('users');
    Route::get('/users/create', [UserController::class, 'create'])->name('users.create');
    Route::post('/users', [UserController::class, 'store'])->name('users.store');
    Route::get('/users/{id}/edit', [UserController::class, 'edit'])->name('users.edit');
    Route::put('/users/{id}', [UserController::class, 'update'])->name('users.update');
    Route::delete('/users/{id}', [UserController::class, 'destroy'])->name('users.destroy');
    Route::get('/users/{id}', [UserController::class, 'show'])->name('users.show');
    Route::get('/whitelist', [WhitelistController::class, 'index'])->name('whitelist');
    Route::get('/whitelist/create', [WhitelistController::class, 'create'])->name('whitelist.create');
    Route::post('/whitelist', [WhitelistController::class, 'store'])->name('whitelist.store');
    Route::get('/whitelist/{id}', [WhitelistController::class, 'show'])->name('whitelist.show');
    Route::patch('/whitelist/{id}/toggle', [WhitelistController::class, 'toggleStatus'])->name('whitelist.toggle');

    // Reviews. Only /reviews and /reviews/{id}/visibility exist — a review can
    // be hidden or shown again and nothing else. No create/edit/delete, which
    // is why there is no /reviews/{id} edit route to collide with a wildcard.
    Route::get('/reviews', [ReviewController::class, 'index'])->name('reviews');
    Route::patch('/reviews/{id}/visibility', [ReviewController::class, 'toggleStatus'])
        ->name('reviews.toggleStatus');

    Route::get('/seller-requests', [SellerRequestController::class, 'index'])->name('seller-requests');
    Route::get('/seller-requests/{id}', [SellerRequestController::class, 'show'])->name('seller-requests.show');
    Route::post('/seller-requests/{id}/approve', [SellerRequestController::class, 'approve'])->name('seller-requests.approve');
    Route::post('/seller-requests/{id}/reject', [SellerRequestController::class, 'reject'])->name('seller-requests.reject');

    Route::get('/profile', [ProfileController::class, 'edit'])->name('profile.edit');
    Route::patch('/profile', [ProfileController::class, 'update'])->name('profile.update');
    Route::delete('/profile', [ProfileController::class, 'destroy'])->name('profile.destroy');
});

require __DIR__.'/auth.php';