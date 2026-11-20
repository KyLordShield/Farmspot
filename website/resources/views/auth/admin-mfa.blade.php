@extends('layouts.guest')

@section('title', 'Verify your sign-in | FarmSpot Admin')
@section('card-class', 'verification-card')

@push('head')
    <link rel="stylesheet" href="{{ asset('css/admin-verification.css') }}">
    <script src="{{ asset('js/admin-verification.js') }}?v={{ filemtime(public_path('js/admin-verification.js')) }}" defer></script>
@endpush

@section('content')
    <div class="verification-icon" aria-hidden="true"><i class="bi bi-envelope-check"></i></div>
    <h1 class="verification-title">Check your email</h1>
    <p id="verification-help" class="verification-help">
        @if ($codeSent)
            Enter the six-digit code sent to your admin email. Check Spam if you don’t see it.
        @else
            Request a six-digit code to continue to the admin dashboard.
        @endif
    </p>

    @if ($codeSent && $reference)
        <p id="verification-reference" class="verification-reference">Sign-in reference <strong>{{ $reference }}</strong></p>
    @endif

    <div id="verification-feedback">
        @if (isset($retryAfter) || $errors->has('delivery') || $errors->has('code'))
            <div class="verification-message verification-message-error" role="alert">
                <strong>{{ isset($retryAfter) ? 'Too many attempts' : ($errors->has('delivery') ? 'Email delivery' : 'Check your code') }}</strong>
                <span>{{ isset($retryAfter) ? "Try again in {$retryAfter} seconds." : ($errors->first('delivery') ?: $errors->first('code')) }}</span>
            </div>
        @elseif (session('verification_status'))
            <p class="verification-message verification-message-success" role="status">{{ session('verification_status') }}</p>
        @endif
    </div>

    @if ($codeSent)
        <form method="POST" action="{{ route('admin.mfa.verify') }}">
            @csrf
            <label for="code" class="verification-label">Verification code</label>
            <div class="verification-code @error('code') verification-code-error @enderror" data-verification-code>
                <input id="code" name="code" type="text" class="form-control"
                       inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}"
                       aria-describedby="verification-help{{ $reference ? ' verification-reference' : '' }} verification-feedback"
                       @error('code') aria-invalid="true" @enderror required>
                <div class="verification-digits" aria-hidden="true">
                    @for ($digit = 0; $digit < 6; $digit++)
                        <span></span>
                    @endfor
                </div>
            </div>
            <button type="submit" class="btn btn-farmspot verification-submit" @disabled(isset($retryAfter))>
                <span data-verify-label>Verify and sign in</span>
                <span data-verify-loading hidden>
                    <span class="spinner-border spinner-border-sm me-1" aria-hidden="true"></span>
                    Verifying…
                </span>
            </button>
            <span class="visually-hidden" role="status" data-verify-status></span>
        </form>
    @endif

    <div class="verification-actions">
        @unless(isset($retryAfter))
            <form method="POST" action="{{ route('admin.mfa.resend') }}">
                @csrf
                <button type="submit" class="verification-link">{{ $codeSent ? 'Send a new code' : 'Send code' }}</button>
            </form>
        @endunless
        <form method="POST" action="{{ route('logout') }}">
            @csrf
            <button type="submit" class="verification-link verification-back">Sign out</button>
        </form>
    </div>
@endsection
