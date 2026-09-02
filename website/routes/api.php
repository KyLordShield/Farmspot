<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ListingController;
use App\Http\Controllers\Api\ListingCreateController;
use App\Http\Controllers\Api\SellerController;
use App\Http\Controllers\Api\FarmController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);

Route::get('/listings', [ListingController::class, 'index']);
Route::get('/listings/{id}', [ListingController::class, 'show']);

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::post('/seller/activate', [SellerController::class, 'activate']);
    Route::post('/seller/deactivate', [SellerController::class, 'deactivate']);
    Route::post('/farms', [FarmController::class, 'store']);
    Route::get('/farms', [FarmController::class, 'index']);
    Route::post('/listings', [ListingCreateController::class, 'store']);

    Route::get('/user', function (Request $request) {
        return $request->user();
    });
});