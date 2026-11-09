<?php

namespace App\Providers;

use App\Models\BuyRequest;
use App\Models\Listing;
use App\Models\Report;
use App\Models\ReviewRequest;
use App\Observers\PremiumBuyRequestObserver;
use App\Observers\PremiumListingObserver;
use App\Services\MassReportService;
use Illuminate\Pagination\Paginator;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\View;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Authenticated limits follow the account across devices and tokens.
        $identity = fn (Request $request) => $request->user()
            ? 'user:'.$request->user()->getAuthIdentifier()
            : 'ip:'.$request->ip();

        RateLimiter::for('api', fn (Request $request) =>
            Limit::perMinute(180)->by($identity($request)));
        RateLimiter::for('website', fn (Request $request) =>
            Limit::perMinute(120)->by($identity($request)));
        RateLimiter::for('writes', fn (Request $request) => $request->isMethodSafe()
            ? Limit::none()
            : Limit::perMinute(60)->by($identity($request)));
        RateLimiter::for('login', function (Request $request) {
            $email = $request->input('email');
            $email = is_string($email) ? strtolower(trim($email)) : '';

            return [
                Limit::perMinute(20)->by('ip:'.$request->ip()),
                Limit::perMinute(5)->by('account:'.hash('sha256', $email.'|'.$request->ip())),
            ];
        });
        RateLimiter::for('registration', fn (Request $request) =>
            Limit::perMinute(3)->by('ip:'.$request->ip()));

        Paginator::useBootstrapFive();
        Listing::observe(PremiumListingObserver::class);
        BuyRequest::observe(PremiumBuyRequestObserver::class);

        // Share light-weight sidebar counts for the admin layout. Doing it as a
        // composer avoids the temptation to compute them in every controller
        // that renders a view under the admin group, and keeps the badge
        // consistent. Queries are cheap (indexed counts) and only run when the
        // admin layout is actually rendered and an admin is signed in; in tests
        // and console commands we simply share nulls.
        View::composer('layouts.app', function ($view) {
            if (app()->runningInConsole()) {
                $view->with('sidebarNewReports', null);
                $view->with('sidebarMassReports', null);
                $view->with('sidebarPendingAppeals', null);
                $view->with('sidebarReportThreshold', MassReportService::THRESHOLD);

                return;
            }

            $user = Auth::user();

            if (! $user || ($user->USR_ROLE ?? null) !== 'ADMIN') {
                $view->with('sidebarNewReports', null);
                $view->with('sidebarMassReports', null);
                $view->with('sidebarPendingAppeals', null);
                $view->with('sidebarReportThreshold', MassReportService::THRESHOLD);

                return;
            }

            // Two numbers side by side, and deliberately different colours:
            // red is the pile of work nobody has opened yet (new reports),
            // orange is how many targets have been piled on hard enough to
            // reach the threshold. Reporting "10" for a single target that ten
            // people complained about is the exact confusion these separate.
            $view->with('sidebarNewReports', Report::where('RPT_STATUS', 'New')->count());
            $view->with('sidebarMassReports', app(MassReportService::class)->openFlaggedTargetCount());
            $view->with('sidebarPendingAppeals', ReviewRequest::where('RRQ_STATUS', ReviewRequest::STATUS_PENDING)->count());
            $view->with('sidebarReportThreshold', app(MassReportService::class)->threshold());
        });
    }
}
