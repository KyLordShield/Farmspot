<?php

namespace App\Console\Commands;

use App\Services\NotificationService;
use Illuminate\Console\Command;

/**
 * Sends a single OneSignal push and exits.
 *
 * NotificationService hands work to this command in a detached background
 * process when a push is triggered by an HTTP request, so the farmer's phone
 * is answered without waiting on OneSignal. Everything the command needs is
 * passed as one base64 JSON argument: no queue, no worker daemon, and nothing
 * that would be lost if the web request's PHP process has already exited by the
 * time the push actually goes out.
 */
class SendOneSignalPush extends Command
{
    protected $signature = 'notifications:send-push {payload : base64 encoded JSON of usr_id, title and body}';

    protected $description = 'Deliver one queued OneSignal push (used by NotificationService in the background)';

    public function handle(NotificationService $notifications): int
    {
        $raw = base64_decode($this->argument('payload'), true);

        if ($raw === false) {
            $this->error('Payload was not valid base64.');

            return self::FAILURE;
        }

        $data = json_decode($raw, true);

        if (! is_array($data) || ! isset($data['usr_id'], $data['title'], $data['body'])) {
            $this->error('Payload was not the expected JSON shape.');

            return self::FAILURE;
        }

        // The service is resolved in console, so this sends inline: there is no
        // response to get out of the way of and nothing left to defer behind.
        $notifications->sendPushNow($data['usr_id'], $data['title'], $data['body']);

        return self::SUCCESS;
    }
}