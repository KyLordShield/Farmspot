<?php

namespace App\Jobs;

use App\Models\UserNotification;
use App\Services\EventPushSender;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class SendBuyRequestUpdate implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public int $timeout = 20;

    public array $backoff = [60, 300];

    public function __construct(public string $requestId, public array $users, public string $body, public string $deliveryKey)
    {
        $this->onConnection('database');
        $this->onQueue('request-updates');
    }

    public function handle(EventPushSender $sender): void
    {
        foreach ($this->users as $user) {
            UserNotification::firstOrCreate(['NOTIF_DEDUP_KEY' => $this->deliveryKey.':'.$user], [
                'NOTIF_ID' => UserNotification::newId(), 'USR_ID' => $user,
                'NOTIF_TYPE' => 'BUY_REQUEST_UPDATED', 'NOTIF_REF_ID' => $this->requestId,
                'NOTIF_TITLE' => 'Buy request updated', 'NOTIF_BODY' => $this->body,
                'NOTIF_IS_READ' => 0, 'NOTIF_CREATED_AT' => now(),
            ]);
        }
        if ($sender->configured() && ! $sender->send(
            (object) ['ID' => $this->deliveryKey, 'USERS' => json_encode($this->users)],
            (object) ['TITLE' => 'Buy request updated', 'BODY' => $this->body]
        )) {
            // Both inbox and push are idempotent across retries.
            throw new \RuntimeException('Buy request update push was not accepted.');
        }
    }
}
