<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Services\AdminMfa;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

class AdminMfaController extends Controller
{
    public function show(Request $request, AdminMfa $mfa)
    {
        if ($redirect = $this->checkPending($request, $mfa)) {
            return $redirect;
        }

        return response()->view('auth.admin-mfa', [
            'codeSent' => $request->session()->has('admin_mfa.nonce'),
            'reference' => $request->session()->get('admin_mfa.reference'),
        ])->header('Cache-Control', 'no-store')->header('X-Robots-Tag', 'noindex, nofollow');
    }

    public function resend(Request $request, AdminMfa $mfa)
    {
        if ($redirect = $this->checkPending($request, $mfa)) {
            return $redirect;
        }

        if (RateLimiter::tooManyAttempts('admin-mfa:'.$request->user()->getKey(), 5)) {
            return redirect()->route('admin.mfa')->withErrors(['delivery' => 'Too many code attempts. Please try signing in again in a few minutes.']);
        }

        $error = $mfa->send($request);
        $redirect = redirect()->route('admin.mfa');

        return $error === ''
            ? $redirect->with('verification_status', 'A new code was sent. Use the email with the reference below.')
            : $redirect->withErrors(['delivery' => $error]);
    }

    public function verify(Request $request, AdminMfa $mfa)
    {
        if ($redirect = $this->checkPending($request, $mfa)) {
            return $redirect;
        }

        $user = $request->user();
        $key = 'admin-mfa:'.$user->getKey();
        if (RateLimiter::tooManyAttempts($key, 5)) {
            $retryAfter = RateLimiter::availableIn($key);

            return response()->view('auth.admin-mfa', [
                'codeSent' => $request->session()->has('admin_mfa.nonce'),
                'reference' => $request->session()->get('admin_mfa.reference'),
                'retryAfter' => $retryAfter,
            ], 429)
                ->header('Retry-After', (string) $retryAfter)->header('Cache-Control', 'no-store');
        }
        RateLimiter::hit($key, 300);

        $code = $request->input('code');
        if (is_string($code)) {
            $request->merge(['code' => preg_replace('/[\s\x{00A0}\x{200B}\x{202F}]+/u', '', $code)]);
        }
        $request->validate(
            ['code' => ['bail', 'required', 'string', 'regex:/^[0-9]{6}$/D']],
            ['code.*' => 'Enter all six digits from your email.'],
        );
        if (! $mfa->consume($request, $request->input('code'))) {
            throw ValidationException::withMessages(['code' => 'That code could not be verified. Check that your email has the same sign-in reference, or request a new code.']);
        }

        RateLimiter::clear($key);
        $request->session()->regenerate(true);
        $request->session()->put('admin_mfa', [
            'verified' => $mfa->fingerprint($user),
            'started' => now()->timestamp,
            'last_seen' => now()->timestamp,
        ]);

        return redirect()->intended(route('dashboard', absolute: false));
    }

    private function checkPending(Request $request, AdminMfa $mfa)
    {
        if ($request->session()->has('admin_mfa.verified')) {
            return redirect()->route('dashboard');
        }

        if (! $mfa->isPending($request)) {
            Auth::guard('web')->logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return redirect()->route('login')->withErrors([
                'email' => 'Your verification session expired. Sign in again for a new code.',
            ]);
        }

        return null;
    }
}
