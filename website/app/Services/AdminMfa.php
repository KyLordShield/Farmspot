<?php

namespace App\Services;

use App\Models\User;
use App\Notifications\AdminSignInCode;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class AdminMfa
{
    public const CODE_LIFETIME = 300;

    public function isPending(Request $request): bool
    {
        $user = $request->user();
        $session = $request->session();
        $started = $session->get('admin_mfa.pending_at', 0);
        $expires = $session->get('admin_mfa.expires_at', $started + self::CODE_LIFETIME);

        return $user?->USR_STATUS === 'ACTIVE'
            && $session->get('admin_mfa.pending') === $this->fingerprint($user)
            && now()->timestamp < $expires;
    }

    public function fingerprint(User $user): string
    {
        return hash_hmac('sha256', json_encode([
            'email-code', $user->getKey(), $user->getAuthPassword(), $user->USR_EMAIL,
        ], JSON_THROW_ON_ERROR), config('app.key'));
    }

    public function send(Request $request): string
    {
        $user = $request->user();
        $key = 'admin-mfa-mail:'.$user->getKey();
        if (! Cache::add($key, true, 60)) {
            return 'Please wait one minute between requests for a new code.';
        }

        $code = sprintf('%06d', random_int(0, 999999));
        $nonce = bin2hex(random_bytes(32));
        $reference = strtoupper(substr($nonce, 0, 8));

        try {
            if (! filter_var($user->USR_EMAIL, FILTER_VALIDATE_EMAIL)) {
                throw new \RuntimeException('Admin sign-in requires a valid admin email.');
            }

            $this->deliver($user, new AdminSignInCode($code, $reference));
        } catch (\Exception $exception) {
            Log::warning('Admin sign-in code delivery failed.', ['exception_type' => $exception::class]);

            return 'We could not send the code. Please try again in a minute.';
        }

        $request->session()->put([
            'admin_mfa.nonce' => $nonce,
            'admin_mfa.code_hash' => $this->digest($nonce, $code),
            'admin_mfa.reference' => $reference,
            'admin_mfa.expires_at' => min(
                now()->timestamp + self::CODE_LIFETIME,
                $request->session()->get('admin_mfa.pending_at') + 2 * self::CODE_LIFETIME,
            ),
        ]);

        return '';
    }

    private function deliver(User $user, AdminSignInCode $notification): void
    {
        $apiKey = config('services.brevo.admin_mail_key');
        $from = config('services.brevo.admin_mail_from');

        if (filled($apiKey) || filled($from)) {
            if (blank($apiKey) || ! filter_var($from, FILTER_VALIDATE_EMAIL)) {
                throw new \RuntimeException('Brevo requires an API key and a valid sender address.');
            }

            $message = $notification->toMail($user);
            $response = Http::withHeaders(['api-key' => $apiKey])
                ->acceptJson()->connectTimeout(5)->timeout(10)
                ->post('https://api.brevo.com/v3/smtp/email', [
                    'sender' => ['email' => $from, 'name' => 'FarmSpot Admin'],
                    'to' => [['email' => $user->USR_EMAIL]],
                    'subject' => $message->subject,
                    'textContent' => implode("\n\n", $message->introLines),
                ]);

            if (! $response->successful() || blank($response->json('messageId'))) {
                Log::warning('Brevo rejected admin sign-in email.', ['http_status' => $response->status()]);
                throw new \RuntimeException('Brevo did not accept the admin sign-in email.');
            }

            return;
        }

        $mailer = config('mail.default');
        $transport = config("mail.mailers.{$mailer}.transport");
        if (in_array($transport, [null, 'log', 'array', 'failover', 'roundrobin'], true)) {
            throw new \RuntimeException('Admin sign-in requires a direct mail transport.');
        }

        $user->notify($notification);
    }

    public function consume(Request $request, string $code): bool
    {
        $nonce = $request->session()->get('admin_mfa.nonce');
        $hash = $request->session()->get('admin_mfa.code_hash');

        return is_string($nonce) && is_string($hash)
            && hash_equals($hash, $this->digest($nonce, $code))
            && Cache::add('admin-mfa-used:'.$nonce, true, self::CODE_LIFETIME);
    }

    private function digest(string $nonce, string $code): string
    {
        return hash_hmac('sha256', $nonce.':'.$code, config('app.key'));
    }
}
