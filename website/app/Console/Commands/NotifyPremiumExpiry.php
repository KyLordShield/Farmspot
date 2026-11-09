<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\NotificationService;
use Illuminate\Console\Command;

class NotifyPremiumExpiry extends Command
{
    protected $signature = 'premium:notify-expiry';

    protected $description = 'Notify accounts before Premium expires and once it has ended';

    public function handle(NotificationService $notifications): int
    {
        $now = now();
        User::where('USR_STATUS', 'ACTIVE')
            ->whereNotNull('USR_PREMIUM_EXPIRES_AT')
            ->where('USR_PREMIUM_EXPIRES_AT', '<=', $now->copy()->addDay())
            ->chunkById(200, function ($users) use ($notifications, $now) {
                foreach ($users as $candidate) {
                    // Re-read so a renewal since the batch query suppresses stale notices.
                    $user = $candidate->fresh();
                    $expiry = $user?->USR_PREMIUM_EXPIRES_AT;
                    if (! $expiry || $user->USR_STATUS !== 'ACTIVE' || $expiry->gt($now->copy()->addDay())) {
                        continue;
                    }
                    $expired = $expiry->lte($now);
                    $type = $expired ? 'PREMIUM_EXPIRED' : 'PREMIUM_EXPIRING_SOON';
                    $notifications->notify(
                        $user->USR_ID,
                        $type,
                        $expired ? 'Your Premium has expired' : 'Premium expires soon',
                        $expired
                            ? 'Your Premium access has ended. Renew to restore Premium features. Your saved requests and existing messages remain available.'
                            : 'Your Premium access ends within 24 hours. Renew from the Premium screen to continue using Premium features.',
                        $user->USR_ID,
                        dedupKey: hash('sha256', $type.'|'.$user->USR_ID.'|'.$expiry->toIso8601String()),
                    );
                }
            }, 'USR_ID');

        return self::SUCCESS;
    }
}
