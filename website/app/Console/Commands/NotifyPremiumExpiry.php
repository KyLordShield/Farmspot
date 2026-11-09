<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Notifications\PremiumExpiryNotice;
use App\Services\NotificationService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

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
                    $title = $expired ? 'Your Premium has expired' : 'Premium expires soon';
                    $body = $expired
                        ? 'Your Premium access has ended. Renew to restore Premium features. Your saved requests and existing messages remain available.'
                        : 'Your Premium access ends within 24 hours. Renew from the Premium screen to continue using Premium features.';
                    $created = $notifications->notify(
                        $user->USR_ID,
                        $type,
                        $title,
                        $body,
                        $user->USR_ID,
                        dedupKey: hash('sha256', $type.'|'.$user->USR_ID.'|'.$expiry->toIso8601String()),
                    );
                    if ($created && filled($user->USR_EMAIL)) {
                        try {
                            $user->notify(new PremiumExpiryNotice($title, $body));
                        } catch (\Throwable $error) {
                            Log::warning('Premium expiry email could not be sent.', [
                                'user_id' => $user->USR_ID,
                                'type' => $type,
                                'exception' => $error::class,
                            ]);
                        }
                    }
                }
            }, 'USR_ID');

        return self::SUCCESS;
    }
}
