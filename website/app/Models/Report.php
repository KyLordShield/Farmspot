<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

/**
 * A user-submitted report about a listing, a chat message, or a person.
 *
 * The table arrived with the legacy schema dump as a listing-only complaint
 * queue, and the admin panel reads RPT_REASON as a human-readable label, so that
 * column is still written even though RPT_REASON_CODE is the real value. The
 * two together mean the existing admin search and tables kept working while the
 * report gained a subject that is not a crop.
 */
class Report extends Model
{
    protected $table = 'report';

    protected $primaryKey = 'RPT_ID';

    /**
     * A 6-digit id the model assigns, not the database. RPT_ID used to be
     * int(11) AUTO_INCREMENT — the only numeric id in this schema — and that is
     * exactly why the API was sending a JSON number where every other id was a
     * string, which crashed the app with "type 'int' is not a subtype of type
     * 'String'". Leaving $incrementing true would reintroduce the same
     * mismatch.
     */
    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    /**
     * The report states that mean "nobody has looked at this yet".
     *
     * Used by the seller's My Farm list, which shows a neutral "Under review"
     * chip for a listing carrying one of these. Resolved and Dismissed are
     * deliberately absent: a finished report is not news to the seller, and a
     * chip that outlives the decision would train them to ignore it.
     *
     * Mixed case because that is what the column stores and what the admin
     * triage form writes — the whole report table is inconsistent this way and
     * these constants are the one place that has to agree with it.
     */
    public const OPEN_STATUSES = ['New', 'Reviewing'];

    /**
     * The enforcement steps available per reported subject.
     *
     * A report is a lead, not a verdict, so nothing here happens on a counter:
     * a moderator always looks at the listing, message or person and decides.
     * That is deliberate — wiring "three reports = suspended" would let one
     * buyer bury a competitor by filing three reports against them.
     *
     * A subject can have more than one step, and they are independent. A farmer
     * can be deactivated and have their listings taken down as two separate
     * decisions, either of which can be undone without touching the other.
     */
    public const ENFORCEMENT = [
        'LISTING' => [
            'LISTING_TAKEN_DOWN' => [
                'label' => 'Listing taken off sale',
                'button' => 'Take this listing off sale',
                'subject' => 'LISTING',
            ],
            'SELLER_DEACTIVATED' => [
                'label' => 'Seller account deactivated',
                'button' => 'Deactivate the seller who posted this',
                'subject' => 'USER',
            ],
        ],
        'FARMER' => [
            'FARMER_ACCOUNT_DEACTIVATED' => [
                'label' => 'Farmer account deactivated',
                'button' => 'Deactivate this farmer',
                'subject' => 'USER',
            ],
            'FARMER_LISTINGS_TAKEN_DOWN' => [
                'label' => 'Farmer listings taken off sale',
                'button' => 'Take down all their listings',
                'subject' => 'FARMER',
            ],
        ],
        'USER' => [
            'ACCOUNT_DEACTIVATED' => [
                'label' => 'Account deactivated',
                'button' => 'Deactivate this account',
                'subject' => 'USER',
            ],
        ],
        'MESSAGE' => [
            'MESSAGE_HIDDEN' => [
                'label' => 'Message hidden',
                'button' => 'Hide this message',
                'subject' => 'MESSAGE',
            ],
        ],
    ];

    public const ACTION_LABELS = [
        'LISTING_TAKEN_DOWN' => 'Listing taken off sale',
        'SELLER_DEACTIVATED' => 'Seller account deactivated',
        'FARMER_ACCOUNT_DEACTIVATED' => 'Farmer account deactivated',
        'FARMER_LISTINGS_TAKEN_DOWN' => 'Farmer listings taken off sale',
        'ACCOUNT_DEACTIVATED' => 'Account deactivated',
        'MESSAGE_HIDDEN' => 'Message hidden',
    ];

    /**
     * A 6-digit report id, unique against the table.
     *
     * Random rather than sequential so a buyer cannot walk the complaint queue
     * by counting, and 6 digits to match every other id in this schema. Called
     * explicitly by the API instead of letting the database assign one, because
     * AUTO_INCREMENT was the thing being removed.
     */
    public static function newId(): string
    {
        do {
            $id = (string) random_int(100000, 999999);
        } while (self::where('RPT_ID', $id)->exists());

        return $id;
    }

    /**
     * RPT_STATUS is mass-assignable because the admin triage form posts it.
     * The rest are listed explicitly rather than switching to $guarded = []
     * like the other models: this is the one table whose rows a user creates
     * from their phone, so what a request is allowed to write is worth spelling
     * out. USR_ID in particular is derived from the bearer token server-side
     * and must never arrive from the client.
     *
     * RPT_UPDATED_AT belongs here too. It is written by the triage form's
     * update() call, and leaving it off this list would have Laravel discard it
     * silently - the status would change and the "open for how long" column
     * would stay null forever, with nothing to indicate why.
     *
     * RPT_ID is here because the database no longer assigns it. It is
     * regenerated per request by Report::newId() and never taken from the
     * client, so putting it on the model is not an opening for a caller to
     * choose their own report id.
     */
    protected $fillable = [        'RPT_REASON',
        'USR_ID',
        'LST_ID',
        'RPT_CREATED_AT',
        'RPT_STATUS',
        'RPT_UPDATED_AT',
        'RPT_TARGET_TYPE',
        'RPT_TARGET_ID',
        'RPT_REASON_CODE',
        'RPT_DETAILS',
        'RPT_ID',
    ];

    /**
     * Every enforcement step applied to this report, oldest first.
     */
    public function actions()
    {
        return $this->hasMany(ReportAction::class, 'RPT_ID', 'RPT_ID');
    }

    /**
     * The steps still in force. A rolled-back action stays in the history but
     * stops counting, so undo is a pop of the newest live one.
     */
    public function liveActions()
    {
        return $this->actions()->whereNull('RAC_REVERTED_AT');
    }
    /**
     * The reason codes, matching the RPT_REASON_CODE enum in the migration.
     *
     * The project has no PHP enums anywhere, so this is a plain array used for
     * validation, the admin filter and the label lookup below. Keeping the
     * label here is what lets the mobile app, the API and the admin views agree
     * on what a reason is called without three copies of the wording.
     */
    public const REASONS = [
        'MISLEADING_INFO' => 'Misleading or false information',
        'FAKE_LISTING' => 'Item is not real or not available',
        'HARASSMENT' => 'Harassment or bullying',
        'INAPPROPRIATE_CONTENT' => 'Inappropriate or offensive content',
        'FRAUD_OR_SCAM' => 'Fraud, scam or asking for money',
        'SPAM' => 'Spam or repeated messages',
        'UNSAFE_BEHAVIOR' => 'Unsafe or off-platform behaviour',
        'OTHER' => 'Something else',
    ];

    /**
     * What kind of thing was reported.
     *
     * FARMER is deliberately separate from USER even though a farmer is also a
     * user: they mean different moderator actions. A report against a farmer
     * is about their selling account and their farm, which is what a
     * moderator can suspend. A report against a plain user is about the
     * account itself.
     */
    public const TARGET_LISTING = 'LISTING';

    public const TARGET_MESSAGE = 'MESSAGE';

    public const TARGET_FARMER = 'FARMER';

    public const TARGET_USER = 'USER';

    public const TARGET_TYPES = [
        self::TARGET_LISTING,
        self::TARGET_MESSAGE,
        self::TARGET_FARMER,
        self::TARGET_USER,
    ];

    /**
     * The person who filed the report.
     *
     * Named user() rather than reporter() because the admin views have
     * traversed $report->user->USR_NAME since before reports could be created
     * at all, and renaming it would silently break them.
     */
    public function user()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }

    /**
     * The reported crop listing.
     *
     * Null for reports about a message or a person. Present as context for a
     * message report, where the listing the conversation was opened over tells
     * a moderator whether this was a live sale or an unsolicited approach.
     */
    public function listing()
    {
        return $this->belongsTo(Listing::class, 'LST_ID', 'LST_ID');
    }

    public function farmer()
    {
        return $this->belongsTo(Farmer::class, 'RPT_TARGET_ID', 'FMR_ID');
    }

    public function message()
    {
        return $this->belongsTo(Message::class, 'RPT_TARGET_ID', 'MSG_ID');
    }

    /**
     * The reported account, for reports that name a person rather than a
     * farmer profile. Resolved off RPT_TARGET_ID so it does not collide with
     * user(), which is the reporter.
     */
    public function reportedUser()
    {
        return $this->belongsTo(User::class, 'RPT_TARGET_ID', 'USR_ID');
    }

    /**
     * The readable form of RPT_REASON_CODE, falling back to whatever text the
     * row already carried so a row written before the taxonomy existed still
     * renders.
     */
    public function reasonLabel(): string
    {
        return self::REASONS[$this->RPT_REASON_CODE] ?? $this->RPT_REASON;
    }

    /**
     * The human-readable name of whatever was reported, for the admin list.
     *
     * Resolved lazily through the relations already loaded by the controller.
     * Returns null when the reported row is gone, which a listing delete can
     * cause through the cascade.
     */
    public function targetLabel(): ?string
    {
        return match ($this->RPT_TARGET_TYPE) {
            self::TARGET_LISTING => $this->listing
                ? $this->listing->LST_CROP_ICON.' ('.$this->listing->LST_ID.')'
                : null,
            self::TARGET_MESSAGE => $this->message
                ? Str::limit($this->message->MSG_CONTENT, 60).' ('.$this->message->MSG_ID.')'
                : null,
            self::TARGET_FARMER => $this->farmer?->buyer?->user?->USR_NAME,
            self::TARGET_USER => $this->reportedUser?->USR_NAME,
            default => null,
        };
    }
}
