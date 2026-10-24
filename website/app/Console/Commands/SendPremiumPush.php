<?php

namespace App\Console\Commands;

use App\Services\PremiumPushService;
use Illuminate\Console\Command;

class SendPremiumPush extends Command
{
    protected $signature = 'premium:send-push';

    protected $description = 'Send due, grouped premium alert pushes with quiet hours and rate limits';

    public function handle(PremiumPushService $service): int
    {
        $this->info($service->flush().' grouped pushes accepted.');

        return self::SUCCESS;
    }
}
