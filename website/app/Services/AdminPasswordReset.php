<?php

namespace App\Services;

use App\Notifications\AdminPasswordResetCode;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\RateLimiter;

class AdminPasswordReset
{
    public function attemptKey(Request $request): string
    {
        return 'admin-password-attempts:'.$request->user()->getKey();
    }

    public function active(Request $request): bool
    {
        return $request->session()->get('admin_password.expires', 0) > now()->timestamp
            && $request->session()->get('admin_password.owner') === app(AdminMfa::class)->fingerprint($request->user());
    }

    public function send(Request $request): string
    {
        if (!filter_var($request->user()->USR_EMAIL, FILTER_VALIDATE_EMAIL)) {
            return 'Your administrator account needs a valid registered email before you can reset its password.';
        }
        if (RateLimiter::tooManyAttempts($this->attemptKey($request), 5)) {
            return 'Too many attempts. Please wait five minutes before trying again.';
        }
        if (!Cache::add('admin-password-mail:'.$request->user()->getKey(), true, 60)) {
            return 'Please wait one minute before requesting another code.';
        }
        $code = sprintf('%06d', random_int(0, 999999));
        $nonce = bin2hex(random_bytes(32));
        $reference = strtoupper(substr($nonce, 0, 8));
        try {
            app(AdminMfa::class)->deliverCode($request->user(), new AdminPasswordResetCode($code, $reference));
        } catch (\Exception $exception) {
            Log::warning('Admin password reset code delivery failed.', ['exception_type' => $exception::class]);
            return 'We could not send your verification code. Please try again in a minute.';
        }
        $request->session()->put('admin_password', [
            'owner' => app(AdminMfa::class)->fingerprint($request->user()),
            'nonce' => $nonce, 'hash' => $this->digest($nonce, $code),
            'reference' => $reference, 'expires' => now()->timestamp + 300,
        ]);
        return '';
    }

    public function verify(Request $request, string $code): bool
    {
        if (!$this->active($request)) return false;
        $nonce = $request->session()->get('admin_password.nonce');
        $hash = $request->session()->get('admin_password.hash');
        $valid = is_string($nonce) && is_string($hash)
            && hash_equals($hash, $this->digest($nonce, $code))
            && Cache::add('admin-password-used:'.$nonce, true, 300);
        if (!$valid) return false;
        $request->session()->put('admin_password.verified_until', now()->timestamp + 300);
        $request->session()->forget('admin_password.hash');
        return true;
    }

    public function authorized(Request $request): bool
    {
        return $request->session()->get('admin_password.verified_until', 0) > now()->timestamp
            && $request->session()->get('admin_password.owner') === app(AdminMfa::class)->fingerprint($request->user());
    }

    public function consumeAuthorization(Request $request): bool
    {
        $nonce = $request->session()->get('admin_password.nonce');
        return $this->authorized($request) && is_string($nonce)
            && Cache::add('admin-password-reset-used:'.$nonce, true, 300);
    }

    private function digest(string $nonce, string $code): string
    {
        return hash_hmac('sha256', 'password-reset:'.$nonce.':'.$code, config('app.key'));
    }
}
