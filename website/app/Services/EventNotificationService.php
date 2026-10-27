<?php

namespace App\Services;

use App\Models\AdminPlanner;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/** Durable outbox: no fan-out or external network work in an admin request. */
class EventNotificationService
{
    public const BATCH_SIZE = 100;

    public function enqueue(AdminPlanner $event): void
    {
        if ($event->APL_TYPE !== AdminPlanner::TYPE_EVENT || ! $event->APL_NOTIFY_FARMERS) {
            return;
        }
        $date = $event->APL_DATETIME?->format('M j, Y, g:i A');
        $body = trim(($date ? $date.' (Philippine time). ' : '').($event->APL_BODY ?? ''));
        DB::table('event_notice')->insertOrIgnore([
            'ID' => (string) Str::uuid(), 'APL_ID' => $event->APL_ID,
            'TITLE' => $event->APL_TITLE, 'BODY' => Str::limit($body, 299, '…'),
            'CURSOR' => '', 'CREATED_AT' => now(),
        ]);
    }

    public function cancel(string $eventId): void
    {
        DB::table('event_notice')->where('APL_ID', $eventId)->update(['CANCELLED_AT' => now()]);
    }

    /** At most two 100-account batches per scheduled run; callers may lower it. */
    public function run(int $limit = 2): int
    {
        // A worker that died during its fifth attempt must not strand the notice.
        $failed = DB::table('event_notice_batch')->where('STATE', 'pending')->where('ATTEMPTS', '>=', 5)
            ->where('LEASE_UNTIL', '<=', now())->update(['STATE' => 'failed', 'LEASE_UNTIL' => null]);
        if ($failed) {
            Log::error('Event push workers exhausted retries', ['batches' => $failed]);
        }
        $processed = 0;
        for ($i = 0; $i < max(1, min(2, $limit)); $i++) {
            $batch = $this->claim();
            if (! $batch) {
                $this->prepare();
                $batch = $this->claim();
            }
            if (! $batch) {
                continue;
            }
            $notice = DB::table('event_notice')->where('ID', $batch->NOTICE_ID)->first();
            if (! $notice || $notice->CANCELLED_AT) {
                $this->finish($batch, 'cancelled');

                continue;
            }
            try {
                $sender = app(EventPushSender::class);
                if (! $sender->configured()) {
                    // The inbox was saved transactionally even without push keys.
                    $this->finish($batch, 'inbox_only');
                } elseif ($sender->send($batch, $notice)) {
                    $this->finish($batch, 'sent');
                } else {
                    $this->retry($batch);
                }
            } catch (\Throwable $e) {
                Log::warning('Event push transport failed', ['batch' => $batch->ID]);
                $this->retry($batch);
            }
            $processed++;
        }

        return $processed;
    }

    private function claim(): ?object
    {
        return DB::transaction(function () {
            $batch = DB::table('event_notice_batch')->where('STATE', 'pending')
                ->where('NEXT_AT', '<=', now())
                ->where(fn ($q) => $q->whereNull('LEASE_UNTIL')->orWhere('LEASE_UNTIL', '<=', now()))
                ->orderBy('CREATED_AT')->orderBy('ID')->lockForUpdate()->first();
            if (! $batch) {
                return null;
            }
            DB::table('event_notice_batch')->where('ID', $batch->ID)->update([
                'LEASE_UNTIL' => now()->addMinute(), 'ATTEMPTS' => $batch->ATTEMPTS + 1,
            ]);
            $batch->ATTEMPTS++;

            return $batch;
        });
    }

    private function prepare(): void
    {
        DB::transaction(function () {
            $notice = DB::table('event_notice')->whereNull('FINISHED_AT')->whereNull('CANCELLED_AT')
                ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('event_notice_batch as b')
                    ->whereColumn('b.NOTICE_ID', 'event_notice.ID')->where('b.STATE', 'pending'))
                ->orderBy('CREATED_AT')->orderBy('ID')->lockForUpdate()->first();
            if (! $notice) {
                return;
            }
            $users = User::where('USR_STATUS', 'ACTIVE')->where('USR_IS_SELLER', 1)
                ->where('USR_CREATED_AT', '<=', $notice->CREATED_AT)->where('USR_ID', '>', $notice->CURSOR)
                ->whereHas('buyer.farmer.farms', fn ($q) => $q->where('FRM_STATUS', 'APPROVED'))
                ->orderBy('USR_ID')->limit(self::BATCH_SIZE)->pluck('USR_ID')->all();
            if (! $users) {
                DB::table('event_notice')->where('ID', $notice->ID)->update(['FINISHED_AT' => now()]);

                return;
            }
            // Allocate collision-free six-character inbox IDs in a few queries,
            // then bulk-insert. Never spawn a PHP process for each recipient.
            $ids = [];
            while (count($ids) < count($users)) {
                $candidates = [];
                for ($i = count($ids); $i < count($users); $i++) {
                    $candidates[] = strtoupper(Str::random(6));
                }
                $used = DB::table('notification')->whereIn('NOTIF_ID', $candidates)->pluck('NOTIF_ID')->all();
                $ids = array_values(array_unique([...$ids, ...array_diff($candidates, $used)]));
            }
            $rows = [];
            foreach ($users as $i => $user) {
                $rows[] = ['NOTIF_ID' => $ids[$i], 'USR_ID' => $user, 'NOTIF_TYPE' => 'CALENDAR_EVENT',
                    'NOTIF_TITLE' => $notice->TITLE, 'NOTIF_BODY' => $notice->BODY,
                    'NOTIF_REF_ID' => $notice->APL_ID, 'NOTIF_IS_READ' => 0, 'NOTIF_CREATED_AT' => now()];
            }
            DB::table('notification')->insert($rows);
            DB::table('event_notice_batch')->insert([
                'ID' => (string) Str::uuid(), 'NOTICE_ID' => $notice->ID, 'USERS' => json_encode($users),
                'STATE' => 'pending', 'ATTEMPTS' => 0, 'NEXT_AT' => now(), 'CREATED_AT' => now(),
            ]);
            DB::table('event_notice')->where('ID', $notice->ID)->update(['CURSOR' => end($users)]);
        });
    }

    private function finish(object $batch, string $state): void
    {
        DB::table('event_notice_batch')->where('ID', $batch->ID)->update([
            'STATE' => $state, 'LEASE_UNTIL' => null, 'SENT_AT' => $state === 'sent' ? now() : null,
        ]);
    }

    private function retry(object $batch): void
    {
        if ($batch->ATTEMPTS >= 5) {
            $this->finish($batch, 'failed');
            Log::error('Event push exhausted retries; inbox notifications remain available', ['batch' => $batch->ID]);

            return;
        }
        DB::table('event_notice_batch')->where('ID', $batch->ID)->update([
            'LEASE_UNTIL' => null, 'NEXT_AT' => now()->addMinutes(min(30, 2 ** $batch->ATTEMPTS)),
        ]);
    }
}
