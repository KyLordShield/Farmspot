<?php

namespace App\Services;

use App\Models\BuyRequest;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class PremiumPushService
{
    private const ZONE = 'Asia/Manila';

    public function enqueue(string $key, string $user, string $type, string $ref, string $crop): void
    {
        $prefs = PremiumAlertService::settings($user);
        if (! $prefs['enabled'] || ! $prefs['push_enabled']) {
            return;
        }
        DB::table('premium_push_event')->insertOrIgnore(['EVENT_KEY' => $key, 'USR_ID' => $user, 'TYPE' => $type, 'REF_ID' => $ref, 'CROP' => $crop, 'GROUP_KEY' => app(CropCatalog::class)->key($crop), 'CREATED_AT' => now()]);
    }

    public function quiet(array $prefs, Carbon $now): bool
    {
        if (! $prefs['quiet_enabled']) {
            return false;
        }
        $time = $now->copy()->setTimezone(self::ZONE)->format('H:i');

        return $prefs['quiet_start'] < $prefs['quiet_end'] ? $time >= $prefs['quiet_start'] && $time < $prefs['quiet_end'] : $time >= $prefs['quiet_start'] || $time < $prefs['quiet_end'];
    }

    private function publicListings()
    {
        return Listing::with('farm.farmer.buyer.user')->where('LST_AVAILABILITY', 'ACTIVE')->whereIn('LST_STATUS', ['AVAILABLE_NOW', 'SOON_TO_HARVEST'])
            ->whereHas('farm', fn ($q) => $q->where('FRM_STATUS', 'APPROVED')->where('FRM_PIN_ACTIVE', 1)->whereHas('farmer.buyer.user', fn ($u) => $u->where('USR_STATUS', 'ACTIVE')->where('USR_IS_SELLER', 1)));
    }

    private function eligible(object $event, User $user, array $prefs): bool
    {
        if ($user->USR_STATUS !== 'ACTIVE' || ! $prefs['enabled'] || ! $prefs['push_enabled']) {
            return false;
        }
        if ($event->TYPE === 'BUY_REQUEST_MATCH') {
            $request = BuyRequest::with('owner')->find($event->REF_ID);
            if (! $prefs['buy_requests'] || ! $user->isFarmer() || ! $request || $request->BRQ_REMOVED_AT || $request->owner?->USR_STATUS !== 'ACTIVE' || ! $request->owner?->USR_IS_PREMIUM) {
                return false;
            }

            return $this->publicListings()->whereHas('farm.farmer.buyer', fn ($q) => $q->where('USR_ID', $user->USR_ID))->get()->contains(fn ($l) => app(CropCatalog::class)->key($l->LST_CROP_ICON ?: $l->category?->CAT_NAME ?: '') === app(CropCatalog::class)->key($request->BRQ_CROP));
        }
        if (! $user->USR_IS_PREMIUM) {
            return false;
        }
        $listing = $this->publicListings()->whereKey($event->REF_ID)->first();
        if (! $listing) {
            return false;
        }
        if (app(CropCatalog::class)->key($listing->LST_CROP_ICON ?: $listing->category?->CAT_NAME ?: '') !== $event->GROUP_KEY) {
            return false;
        }
        if ($event->TYPE === 'CROP_AVAILABLE') {
            return $listing->LST_STATUS === 'AVAILABLE_NOW' && $prefs['crop_alerts'] && in_array($event->GROUP_KEY, array_map(fn ($c) => app(CropCatalog::class)->key($c), $prefs['crops']), true);
        }

        return $prefs['saved_farms'] && ($event->TYPE !== 'SAVED_FARM_AVAILABLE' || $listing->LST_STATUS === 'AVAILABLE_NOW') && DB::table('saved_farm')->where('USR_ID', $user->USR_ID)->where('FRM_ID', $listing->FRM_ID)->exists();
    }

    private function cancel(object $batch): void
    {
        DB::table('premium_push_batch')->where('ID', $batch->ID)->update(['CANCELLED_AT' => now()]);
        DB::table('premium_push_event')->where('BATCH_ID', $batch->ID)->whereNull('HANDLED_AT')->update(['HANDLED_AT' => now()]);
    }

    public function flush(): int
    {
        if (! app(PremiumPushSender::class)->configured()) {
            return 0;
        }
        $sent = 0;
        $users = DB::table('premium_push_event')->whereNull('HANDLED_AT')->select('USR_ID')->distinct()->get();
        foreach ($users as $row) {
            try {
                // Instant mode may have multiple crop groups; other modes create one digest.
                for ($i = 0; $i < 50; $i++) {
                    $id = $this->prepare($row->USR_ID);
                    if (! $id) {
                        break;
                    }
                    if (! $this->send($id)) {
                        break;
                    }
                    $sent++;
                }
            } catch (\Throwable $e) {
                Log::error('Premium push processing failed', ['user' => $row->USR_ID, 'error' => $e->getMessage()]);
            }
        }

        return $sent;
    }

    private function prepare(string $userId): ?string
    {
        return DB::transaction(function () use ($userId) {
            $setting = DB::table('premium_alert_setting')->where('USR_ID', $userId)->lockForUpdate()->first();
            $user = User::find($userId);
            if (! $setting || ! $user) {
                return null;
            }
            $prefs = PremiumAlertService::settings($userId);
            if ($this->quiet($prefs, now())) {
                return null;
            }
            $batch = DB::table('premium_push_batch')->where('USR_ID', $userId)->whereNull('SENT_AT')->whereNull('CANCELLED_AT')->orderBy('CREATED_AT')->first();
            if ($batch) {
                if ($batch->MODE !== $prefs['push_frequency'] || Carbon::parse($batch->CREATED_AT)->lt(now()->subDay()) || $batch->ATTEMPTS >= 3) {
                    $this->cancel($batch);

                    return null;
                }

                return Carbon::parse($batch->NEXT_ATTEMPT_AT)->isFuture() ? null : $batch->ID;
            }
            DB::table('premium_push_event')->where('USR_ID', $userId)->whereNull('HANDLED_AT')->where('CREATED_AT', '<', now()->subDay())->update(['HANDLED_AT' => now()]);
            $events = DB::table('premium_push_event')->where('USR_ID', $userId)->whereNull('HANDLED_AT')->whereNull('BATCH_ID')->orderBy('CREATED_AT')->orderBy('EVENT_KEY')->get();
            $events = $events->filter(function ($event) use ($user, $prefs) {
                if ($this->eligible($event, $user, $prefs)) {
                    return true;
                }
                DB::table('premium_push_event')->where('EVENT_KEY', $event->EVENT_KEY)->update(['HANDLED_AT' => now()]);

                return false;
            });
            if ($events->isEmpty()) {
                return null;
            }
            $mode = $prefs['push_frequency'];
            if ($mode === 'instant') {
                $events = $events->groupBy('GROUP_KEY')->first(fn ($group) => ! DB::table('premium_push_event as e')->join('premium_push_batch as b', 'b.ID', '=', 'e.BATCH_ID')->where('e.USR_ID', $userId)->where('e.GROUP_KEY', $group->first()->GROUP_KEY)->where('b.SENT_AT', '>', now()->subHour())->exists());
                if (! $events) {
                    return null;
                }
            } else {
                $last = DB::table('premium_push_batch')->where('USR_ID', $userId)->max('SENT_AT');
                if ($last && Carbon::parse($last)->gt(now()->subHour())) {
                    return null;
                }
                if ($mode === 'hourly' && Carbon::parse($events->first()->CREATED_AT)->gt(now()->subHour())) {
                    return null;
                }
                if ($mode === 'daily') {
                    $local = now()->setTimezone(self::ZONE);
                    $cutoff = $local->copy()->setTimeFromTimeString($prefs['daily_time']);
                    if ($local->lt($cutoff)) {
                        return null;
                    }
                    $start = $local->copy()->startOfDay()->setTimezone(config('app.timezone'));
                    if (DB::table('premium_push_batch')->where('USR_ID', $userId)->where('MODE', 'daily')->where('SENT_AT', '>=', $start)->exists()) {
                        return null;
                    }
                    $events = $events->filter(fn ($e) => Carbon::parse($e->CREATED_AT)->lte($cutoff));
                    if ($events->isEmpty()) {
                        return null;
                    }
                }
            }
            [$title,$body] = $this->summary($events, $mode);
            $id = (string) Str::uuid();
            DB::table('premium_push_batch')->insert(['ID' => $id, 'USR_ID' => $userId, 'MODE' => $mode, 'GROUP_KEY' => $mode === 'instant' ? $events->first()->GROUP_KEY : 'all', 'TITLE' => $title, 'BODY' => $body, 'CREATED_AT' => now(), 'NEXT_ATTEMPT_AT' => now()]);
            DB::table('premium_push_event')->whereIn('EVENT_KEY', $events->pluck('EVENT_KEY'))->update(['BATCH_ID' => $id]);

            return $id;
        });
    }

    private function summary($events, string $mode): array
    {
        $parts = [];
        foreach ($events->groupBy('GROUP_KEY') as $group) {
            $crop = $group->first()->CROP;
            $requests = $group->where('TYPE', 'BUY_REQUEST_MATCH')->unique('REF_ID')->count();
            $listings = $group->where('TYPE', '!=', 'BUY_REQUEST_MATCH')->pluck('REF_ID')->unique();
            $farms = Listing::whereIn('LST_ID', $listings)->distinct()->count('FRM_ID');
            if ($farms) {
                $parts[] = "$crop: updates from $farms ".($farms === 1 ? 'farm' : 'farms');
            }
            if ($requests) {
                $parts[] = "$crop: $requests matching ".($requests === 1 ? 'buy request' : 'buy requests');
            }
        }

        return [$mode === 'daily' ? 'Your daily FarmSpot summary' : 'FarmSpot crop updates', Str::limit(implode('. ', array_slice($parts, 0, 3)).(count($parts) > 3 ? '. More updates in Notifications.' : '. Open Notifications for details.'), 300, '...')];
    }

    private function send(string $id): bool
    {
        return DB::transaction(function () use ($id) {
            $batch = DB::table('premium_push_batch')->where('ID', $id)->first();
            DB::table('premium_alert_setting')->where('USR_ID', $batch->USR_ID)->lockForUpdate()->first();
            $batch = DB::table('premium_push_batch')->where('ID', $id)->lockForUpdate()->first();
            if ($batch->SENT_AT || $batch->CANCELLED_AT) {
                return false;
            }
            $prefs = PremiumAlertService::settings($batch->USR_ID);
            $user = User::find($batch->USR_ID);
            if ($this->quiet($prefs, now()) || Carbon::parse($batch->NEXT_ATTEMPT_AT)->isFuture()) {
                return false;
            }
            $events = DB::table('premium_push_event')->where('BATCH_ID', $id)->get();
            if (! $user || $batch->MODE !== $prefs['push_frequency'] || $events->contains(fn ($e) => $e->HANDLED_AT !== null || ! $this->eligible($e, $user, $prefs))) {
                $this->cancel($batch);

                return false;
            }
            $sender = app(PremiumPushSender::class);
            if (! $sender->configured()) {
                return false;
            }
            try {
                $success = $sender->send($batch);
            } catch (\Throwable $e) {
                $success = false;
                Log::warning('Premium push transport failed', ['batch' => $id]);
            }
            DB::table('premium_push_batch')->where('ID', $id)->update(['ATTEMPTS' => $batch->ATTEMPTS + 1, 'NEXT_ATTEMPT_AT' => now()->addMinutes(5 * ($batch->ATTEMPTS + 1))]);
            if (! $success) {
                return false;
            }
            DB::table('premium_push_batch')->where('ID', $id)->update(['SENT_AT' => now()]);
            DB::table('premium_push_event')->where('BATCH_ID', $id)->update(['HANDLED_AT' => now()]);

            return true;
        });
    }
}
