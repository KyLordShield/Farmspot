@extends('layouts.guest')

@section('title', 'Forgot Password')

@section('content')

    <p class="text-muted small mb-4">
        Forgot your password? Enter your email address and we'll send you a link to reset it.
    </p>

    @if (session('status'))
        <div class="alert alert-success py-2">{{ session('status') }}</div>
    @endif

    <form method="POST" action="{{ route('password.email') }}">
        @csrf

        <div class="mb-3">
            <label for="email" class="form-label fw-semibold">Email Address</label>
            <input id="email" type="email" name="email"
                   class="form-control @error('email') is-invalid @enderror"
                   value="{{ old('email') }}" required autofocus>
            @error('email')
                <div class="text-danger small mt-1">{{ $message }}</div>
            @enderror
        </div>

        <button type="submit" class="btn btn-farmspot w-100">
            Email Password Reset Link
        </button>
    </form>

@endsection