<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Services\AdminPasswordReset;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;
use Illuminate\Validation\Rules\Password;

class PasswordController extends Controller
{
    /**
     * Update the user's password.
     */
    public function sendCode(Request $request, AdminPasswordReset $reset): RedirectResponse
    {
        $error = $reset->send($request);
        return $error === ''
            ? redirect()->route('profile.edit')->with('status', 'password-code-sent')
            : redirect()->route('profile.edit')->withErrors(['delivery' => $error], 'updatePassword');
    }

    public function verifyCode(Request $request, AdminPasswordReset $reset): RedirectResponse
    {
        if ($reset->authorized($request)) return redirect()->route('profile.edit');
        $key = $this->recordAttempt($request, $reset);
        $validated = $request->validateWithBag('updatePassword', [
            'code' => ['required', 'string', 'regex:/^[0-9]{6}$/D'],
        ], ['code.*' => 'Enter the six numbers from your password reset email.']);
        if (!$reset->verify($request, $validated['code'])) {
            throw ValidationException::withMessages(['code' => 'That code is incorrect or expired. Check the email reference or request a new code.'])->errorBag('updatePassword');
        }
        RateLimiter::clear($key);
        return redirect()->route('profile.edit')->with('status', 'password-email-verified');
    }

    private function recordAttempt(Request $request, AdminPasswordReset $reset): string
    {
        $key = $reset->attemptKey($request);
        if (RateLimiter::tooManyAttempts($key, 5)) {
            throw ValidationException::withMessages(['code' => 'Too many attempts. Please wait five minutes before trying again.'])->errorBag('updatePassword');
        }
        RateLimiter::hit($key, 300);
        return $key;
    }

    public function update(Request $request, AdminPasswordReset $reset): RedirectResponse
    {
        $key = $this->recordAttempt($request, $reset);
        if (!$reset->authorized($request)) {
            throw ValidationException::withMessages(['code' => 'Verify your email code first. Verification is valid for five minutes.'])->errorBag('updatePassword');
        }
        $validated = $request->validateWithBag('updatePassword', [
            'current_password' => ['required', 'current_password'],
            'password' => ['required', Password::defaults(), 'confirmed', 'different:current_password'],
        ]);

        if (!$reset->consumeAuthorization($request)) {
            throw ValidationException::withMessages(['code' => 'Your verification expired or was already used. Please verify a new code.'])->errorBag('updatePassword');
        }

        $request->user()->update([
            'USR_PASSWORD' => Hash::make($validated['password']),
        ]);
        RateLimiter::clear($key);

        Auth::guard('web')->logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('login')->with('status', 'Password updated. Sign in again.');
    }
}
