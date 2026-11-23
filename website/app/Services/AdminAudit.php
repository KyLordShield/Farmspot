<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Report;
use App\Models\ListingReview;
use App\Models\ReviewRequest;
use App\Models\AdminPlanner;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/** Collect model changes during one verified admin request. */
class AdminAudit
{
    // Only these business fields can enter the audit trail. Tokens, uploaded
    // verification documents, message contents and authentication codes are excluded.
    private const FIELDS = [
        'user' => ['USR_NAME', 'USR_EMAIL', 'USR_MOBILE_NUMBER', 'USR_ROLE', 'USR_STATUS', 'USR_IS_SELLER', 'USR_TAKEDOWN_REASON', 'USR_PASSWORD'],
        'crop_category' => ['CAT_NAME', 'CAT_ICON', 'CAT_DESCRIPTION'],
        'listing' => ['CAT_ID', 'FMR_ID', 'FRM_ID', 'LST_CROP_ICON', 'LST_DESCRIPTION', 'LST_STATUS', 'LST_AVAILABILITY', 'LST_EXPIRY_DATE', 'LST_HARVEST_DATE', 'LST_IMAGE', 'LST_TAKEDOWN_REASON'],
        'listing_photo' => ['LST_ID', 'LPHOTO_IS_PRIMARY', 'LPHOTO_FILE_PATH'],
        'farm' => ['FRM_NAME', 'FRM_DESCRIPTION', 'FRM_BARANGAY', 'FRM_LATITUDE', 'FRM_LONGITUDE', 'FRM_STATUS', 'FRM_PIN_ACTIVE', 'FRM_REJECTION_REASON'],
        'farmer' => ['BUY_ID', 'FMR_SELLER_MODE_ACTIVE', 'FMR_VERIFIED_AT'],
        'report' => ['RPT_STATUS', 'RPT_TARGET_TYPE', 'RPT_TARGET_ID'],
        'report_action' => ['RPT_ID', 'RAC_ACTION', 'RAC_SUBJECT_TYPE', 'RAC_SUBJECT_ID', 'RAC_REVERTED_AT', 'RAC_REVERTED_BY'],
        'listing_review' => ['LRV_STATUS', 'LRV_RATING', 'LST_ID'],
        'review_request' => ['RRQ_STATUS', 'RRQ_TARGET_TYPE', 'RRQ_TARGET_ID', 'RRQ_ADMIN_NOTE', 'RRQ_DECIDED_BY'],
        'message' => ['MSG_VISIBILITY', 'MSG_HIDDEN_AT'],
        'admin_planner' => ['APL_TYPE', 'APL_TITLE', 'APL_BODY', 'APL_DATETIME', 'APL_IS_DONE', 'APL_NOTIFY_FARMERS'],
    ];

    private const REDACTED = ['USR_PASSWORD', 'APL_TITLE', 'APL_BODY', 'LST_IMAGE', 'LPHOTO_FILE_PATH'];

    private array $records = [];

    public function __construct(private Request $request, private User $actor)
    {
    }

    /** Seed the route's primary target to cover query-builder updates too. */
    public function seedTarget(): void
    {
        $route = $this->request->route();
        $section = Str::before((string) $route->getName(), '.');
        $class = [
            'categories' => CropCategory::class, 'listings' => Listing::class,
            'users' => User::class, 'reviews' => ListingReview::class,
            'reports' => Report::class, 'seller-requests' => Farm::class,
            'appeals' => ReviewRequest::class, 'planner' => AdminPlanner::class,
            'profile' => User::class,
        ][$section] ?? null;
        $id = $route->parameter('id');
        if ($section === 'profile') {
            $id = $this->actor->getKey();
        }
        if ($route->parameter('farmId')) {
            $class = Farm::class;
            $id = $route->parameter('farmId');
        }
        if ($section === 'reports' && $route->parameter('type')) {
            $class = ['LISTING' => Listing::class, 'USER' => User::class, 'MESSAGE' => Message::class, 'FARM' => Farm::class][strtoupper($route->parameter('type'))] ?? null;
        }
        if ($class && is_string($id)) {
            $model = $class::find($id);
            if ($model) {
                $this->capture($model, 'updated');
            }
        }
    }

    public function capture(Model $model, string $event): void
    {
        if (! isset(self::FIELDS[$model->getTable()])) {
            return;
        }
        $key = $model->getTable().':'.$model->getKey();
        if (! array_key_exists($key, $this->records)) {
            $this->records[$key] = [
                'class' => $model::class,
                'id' => $model->getKey(),
                'table' => $model->getTable(),
                'before' => $event === 'created' ? null : $this->snapshot($model),
            ];
        }
    }

    private function snapshot(Model $model): array
    {
        return array_intersect_key($model->getRawOriginal(), array_flip(self::FIELDS[$model->getTable()]));
    }

    public function flush(): void
    {
        foreach ($this->records as $record) {
            try {
                // Read persisted state, so rolled-back writes and no-op saves do
                // not become audit entries, even when a controller catches errors.
                $class = $record['class'];
                $model = (new $class)->newQueryWithoutScopes()->find($record['id']);
                $after = $model ? $this->snapshot($model) : null;
                $before = $record['before'];
                $changes = [];
                foreach (array_unique([...array_keys($before ?? []), ...array_keys($after ?? [])]) as $field) {
                    $old = $before[$field] ?? null;
                    $new = $after[$field] ?? null;
                    if ($old === $new) {
                        continue;
                    }
                    $changes[$field] = in_array($field, self::REDACTED, true)
                        ? ['before' => '[redacted]', 'after' => '[redacted]']
                        : ['before' => is_string($old) ? Str::limit($old, 1000) : $old,
                           'after' => is_string($new) ? Str::limit($new, 1000) : $new];
                }
                if ($before === $after || ($before !== null && $after !== null && ! $changes)) {
                    continue;
                }
                $verb = $before === null ? 'Created' : ($after === null ? 'Deleted' : 'Updated');
                $label = str_replace('_', ' ', $record['table']);
                AuditLog::record(
                    strtoupper($record['table'].'_'.$verb),
                    $verb.' '.$label.' '.$record['id'],
                    User::whereKey($this->actor->getKey())->exists() ? $this->actor->getKey() : null,
                    [
                        'actor_name' => $this->actor->USR_NAME,
                        'target_type' => $record['table'],
                        'target_id' => (string) $record['id'],
                        'route' => $this->request->route()->getName() ?? $this->request->route()->uri(),
                        'changes' => $changes,
                    ],
                );
            } catch (\Throwable $error) {
                Log::error('Admin audit could not be recorded.', ['target_type' => $record['table'], 'target_id' => $record['id'], 'exception' => $error::class]);
            }
        }
    }
}
