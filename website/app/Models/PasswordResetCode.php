<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Hash;

/**
 * One live password-reset code for one app user.
 *
 * Deliberately keyed on USR_ID rather than email, so it can carry a foreign key
 * and cascade when a user is deleted. See the migration for why Laravel's own
 * `password_reset_tokens` could not be used here.
 *
 * The 6-digit code is never held in memory on this model after
 * `PasswordResetController::requestCode` has hashed it. What is stored is
 * RSTC_CODE_HASH, which is what makes a leaked row useless.
 */
class PasswordResetCode extends Model
{
    /**
     * How long a freshly issued code stays valid.
     *
     * Short on purpose. A 6-digit code has ~1e6 values, so the window is the
     * main thing standing between an attacker and a taken-over account; the
     * attempt cap is the second thing.
     */
    public const EXPIRY_MINUTES = 10;

    /**
     * Wrong guesses allowed before the code is locked for good.
     *
     * 5 guesses against 1e6 candidates is a 1-in-200,000 shot per issued code,
     * which is small enough that locking out is the better trade for a user who
     * fat-fingers their code twice. Issuing a new code is one tap away.
     */
    public const MAX_ATTEMPTS = 5;

    protected $table = 'PASSWORD_RESET_CODE';

    protected $primaryKey = 'USR_ID';

    /**
     * USR_ID is a random 6-char string, not an auto-increment number.
     */
    public $incrementing = false;

    protected $keyType = 'string';

    /**
     * The columns here are RSTC_CREATED_AT and friends, not created_at/updated_at.
     */
    public $timestamps = false;

    protected $fillable = [
        'USR_ID',
        'RSTC_CODE_HASH',
        'RSTC_EXPIRES_AT',
        'RSTC_ATTEMPTS',
        'RSTC_CONSUMED_AT',
        'RSTC_CREATED_AT',
    ];

    /**
     * The hash must never reach an API response or a log line.
     */
    protected $hidden = [
        'RSTC_CODE_HASH',
    ];

    protected function casts(): array
    {
        return [
            'RSTC_EXPIRES_AT' => 'datetime',
            'RSTC_CONSUMED_AT' => 'datetime',
            'RSTC_CREATED_AT' => 'datetime',
            'RSTC_ATTEMPTS' => 'integer',
        ];
    }

    /**
     * Config-overridable expiry, defaulting to the constant above.
     *
     * Exposed as a static helper so the controller and this model cannot end up
     * reading different windows from different places.
     */
    public static function expiryMinutes(): int
    {
        return (int) config('auth.password_reset_code.expiry_minutes', self::EXPIRY_MINUTES);
    }

    /**
     * Config-overridable attempt cap, defaulting to the constant above.
     */
    public static function maxAttempts(): int
    {
        return (int) config('auth.password_reset_code.max_attempts', self::MAX_ATTEMPTS);
    }

    /**
     * Whether this code can still be used, and if not, why.
     *
     * Returned as a reason string rather than a bool so the controller can tell
     * the user something useful ("expired" vs "too many attempts") without
     * re-deriving the same three conditions in two places.
     */
    public function usability(): string
    {
        if ($this->RSTC_CONSUMED_AT !== null) {
            return 'used';
        }

        if ($this->RSTC_EXPIRES_AT->isPast()) {
            return 'expired';
        }

        if ($this->RSTC_ATTEMPTS >= self::maxAttempts()) {
            return 'locked';
        }

        return 'usable';
    }

    /**
     * Check a submitted code and count the attempt, whether or not it matched.
     *
     * The counter is incremented on failure only. Incrementing on success would
     * be harmless but would blur the meaning of the column, which exists purely
     * to count guesses.
     */
    public function attempt(string $code): bool
    {
        if (Hash::check($code, $this->RSTC_CODE_HASH)) {
            return true;
        }

        $this->forceFill([
            'RSTC_ATTEMPTS' => $this->RSTC_ATTEMPTS + 1,
        ])->save();

        return false;
    }
}