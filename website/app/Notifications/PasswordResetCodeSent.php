<?php

namespace App\Notifications;

use App\Models\PasswordResetCode;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Emails a 6-digit password-reset code to an app user.
 *
 * A code rather than a link, deliberately. The app authenticates with a Sanctum
 * bearer token held in SharedPreferences, so there is no browser session for a
 * link to return to: tapping one would land on a web page that cannot restore an
 * app session. A code the user types in the app works regardless of which device
 * the mail was read on.
 *
 * The code is passed in as a plain string because it exists nowhere else at
 * send time. It is deliberately NOT read back off the PasswordResetCode model -
 * only its bcrypt hash is stored, so this notification is the single moment the
 * cleartext code exists in the process.
 */
class PasswordResetCodeSent extends Notification
{
    use Queueable;

    public function __construct(
        public User $user,
        public string $code,
        public int $expiryMinutes
    ) {
    }

    /**
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $name = $this->user->USR_NAME ?: 'there';

        return (new MailMessage)
            ->from(config('mail.from.address'), self::fromName())
            ->subject('Your FarmSpot password reset code')
            ->greeting("Hi {$name},")
            ->line('Someone asked to reset the password on your FarmSpot account.')
            ->line("If that was you, enter this code in the app within {$this->expiryMinutes} minutes:")
            // Spaced so the digits are hard to mistype when read aloud or
            // copied by hand; the app strips spaces before submitting.
            ->line('**'.substr($this->code, 0, 3).' '.substr($this->code, 3).'**')
            ->line('If it was not you, you can ignore this email. Your password will not change until someone enters this code.')
            // Deliberately no link: see the class docblock.
            ;
    }

    /**
     * Display name for the From header.
     *
     * config('mail.from.name') resolves to env('MAIL_FROM_NAME', config('app.name')),
     * and both of those are still the stock "Laravel" until APP_NAME /
     * MAIL_FROM_NAME are set. Sending a password-reset mail signed "Laravel"
     * reads as a phishing attempt, so never fall through to the framework
     * default here. Setting APP_NAME=FarmSpot in .env also rebrands the mail
     * body, which this cannot do.
     */
    private static function fromName(): string
    {
        $name = trim((string) config('mail.from.name'));

        return ($name === '' || $name === 'Laravel') ? 'FarmSpot' : $name;
    }
}