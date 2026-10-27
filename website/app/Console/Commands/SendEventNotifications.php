<?php

namespace App\Console\Commands;

use App\Services\EventNotificationService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Schema;

class SendEventNotifications extends Command
{
    protected $signature = 'events:send-notifications {--batches=2 : Process at most two batches of 100 farmers}';

    protected $description = 'Deliver queued calendar announcements in bounded background batches';

    public function handle(EventNotificationService $service): int
    {
        if (! Schema::hasTable('event_notice_batch')) {
            $this->error('Run database migrations before sending event notifications.');

            return self::FAILURE;
        }
        $count = $service->run((int) $this->option('batches'));
        $this->info("{$count} event notification batches processed.");

        return self::SUCCESS;
    }
}
