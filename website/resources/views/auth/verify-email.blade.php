@extends('layouts.guest')

@section('title', 'Verify Email')

@section('content')

    <p class="text-muted small mb-4">
        Thanks for signing up! Before getting started, could you verify your email address by clicking the link we emailed you? If you didn't receive it, we can send another.
    </p>

    @if (session('status') == 'verification-link-sent')
        <div class="alert alert-success py-2 small">
            A new verification link has been sent to the email address you provided.
        </div>
    @endif

    <div class="d-flex align-items-center justify-content-between mt-3">
        <form method="POST" action="{{ route('verification.send') }}">
            @csrf
            <button type="submit" class="btn btn-farmspot">
                Resend Verification Email
            </button>
        </form>

        <form method="POST" action="{{ route('logout') }}">
            @csrf
            <button type="submit" class="btn btn-link btn-sm text-muted text-decoration-underline">
                Log Out
            </button>
        </form>
    </div>

@endsection