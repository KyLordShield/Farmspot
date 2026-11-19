<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Services\AdminMfa;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Http\Response;

class AuthenticatedSessionController extends Controller
{
    /**
     * Display the login view.
     */
    public function create(): Response
    {
        return response()->view('auth.login')->header('X-Robots-Tag', 'noindex, nofollow');
    }

    /**
     * Handle an incoming authentication request.
     */
    public function store(LoginRequest $request, AdminMfa $mfa): RedirectResponse
    {
        $request->authenticate();

        $request->session()->regenerate(true);
        $request->session()->put('admin_mfa', [
            'pending' => $mfa->fingerprint($request->user()),
            'pending_at' => now()->timestamp,
        ]);

        $error = $mfa->send($request);
        $redirect = redirect()->route('admin.mfa');

        return $error === '' ? $redirect : $redirect->withErrors(['delivery' => $error]);
    }

    /**
     * Destroy an authenticated session.
     */
    public function destroy(Request $request): RedirectResponse
    {
        Auth::guard('web')->logout();

        $request->session()->invalidate();

        $request->session()->regenerateToken();

        return redirect('/');
    }
}
