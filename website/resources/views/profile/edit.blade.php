@extends('layouts.app')
@section('title', 'My Profile')
@include('partials._admin-refresh')

@section('content')
<div class="admin-refresh admin-refresh-form">
    <div class="page-head">
        <div>
            <nav class="admin-refresh-crumb" aria-label="Breadcrumb"><a href="{{ route('dashboard') }}">Dashboard</a><span aria-hidden="true">/</span><span aria-current="page">My Profile</span></nav>
            <h1 class="page-title">My Profile</h1>
            <p class="page-desc">Your administrator account and password security.</p>
        </div>
    </div>

    <section class="panel form-card">
        <div class="panel-header"><h2 class="panel-title"><i class="bi bi-person-circle me-2" aria-hidden="true"></i>Account details</h2></div>
        <div class="panel-body">
            @if(session('status') === 'profile-updated')<div class="alert alert-success" role="status">Profile updated.</div>@endif
            <form action="{{ route('profile.update') }}" method="POST" data-auto-spinner>
                @csrf
                @method('PATCH')
                <div class="row g-3 mb-3">
                    <div class="col-md-6">
                        <label for="profile-name" class="form-label">Name</label>
                        <input id="profile-name" name="name" class="form-control @error('name') is-invalid @enderror" value="{{ old('name', $user->USR_NAME) }}" maxlength="{{ \App\Rules\PersonName::MAX_LENGTH }}" autocomplete="name" required>
                        @error('name')<div class="invalid-feedback">{{ $message }}</div>@enderror
                    </div>
                    <div class="col-md-6">
                        <label for="profile-phone" class="form-label">Contact number</label>
                        <input id="profile-phone" name="phone" type="tel" class="form-control @error('phone') is-invalid @enderror" value="{{ old('phone', $user->USR_MOBILE_NUMBER) }}" inputmode="numeric" maxlength="11" pattern="09[0-9]{9}" placeholder="09XXXXXXXXX" autocomplete="tel-national">
                        @error('phone')<div class="invalid-feedback">{{ $message }}</div>@enderror
                        <div class="form-text">11 digits, starting with 09.</div>
                    </div>
                    <div class="col-12">
                        <label for="profile-email" class="form-label">Registered email</label>
                        <input id="profile-email" name="email" type="email" class="form-control @error('email') is-invalid @enderror" value="{{ $user->USR_EMAIL }}" readonly>
                        <div class="form-text">Used for sign-in and security verification.</div>
                        @error('email')<div class="invalid-feedback">{{ $message }}</div>@enderror
                    </div>
                </div>
                <button class="btn btn-farm" type="submit">Save profile</button>
            </form>
        </div>
    </section>

    <section class="panel form-card">
        <div class="panel-header"><h2 class="panel-title"><i class="bi bi-shield-lock me-2" aria-hidden="true"></i>Reset password</h2></div>
        <div class="panel-body">
            <p class="admin-reset-step">{{ $resetVerified ? 'Step 2 of 2 · Set your new password' : 'Step 1 of 2 · Verify your email' }}</p>
            <p class="text-muted">{{ $resetVerified ? 'Email verified. You can now enter your current password and choose a new one.' : 'Verify the code sent to your registered email before entering any passwords.' }}</p>
            @if(session('status') === 'password-code-sent')
                <div class="alert alert-success" role="status">A verification code was sent to {{ $user->USR_EMAIL }}. It expires in five minutes.</div>
            @endif
            @error('delivery', 'updatePassword')<div class="alert alert-danger" role="alert">{{ $message }}</div>@enderror
            @if(!$resetCodeSent)
                @error('code', 'updatePassword')<div class="alert alert-danger" role="alert">{{ $message }}</div>@enderror
            @endif

            @if($resetCodeSent && !$resetVerified)
                <div class="admin-reset-reference mb-3">Email reference: <strong>{{ $resetReference }}</strong><br><small>Use the password reset email with this reference, not your sign-in code.</small></div>
                <form action="{{ route('profile.password.verify') }}" method="POST" data-auto-spinner>
                    @csrf
                    <div class="admin-reset-code-wrap mb-3">
                        <label for="profile-code" id="profile-code-label" class="form-label">6-digit verification code</label>
                        <input id="profile-code" name="code" class="form-control admin-reset-code-input" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required aria-describedby="profile-code-help">
                        <div id="profile-code-boxes" class="admin-reset-code-boxes" role="group" aria-labelledby="profile-code-label" hidden>
                            @for($digit = 1; $digit <= 6; $digit++)
                                <input class="form-control" type="text" inputmode="numeric" pattern="[0-9]" maxlength="6" autocomplete="{{ $digit === 1 ? 'one-time-code' : 'off' }}" aria-label="Digit {{ $digit }} of 6" data-code-digit>
                            @endfor
                        </div>
                        <p id="profile-code-help" class="form-text mb-0">Numbers only. You can paste the full code.</p>
                        @error('code', 'updatePassword')<div class="text-danger small mt-2" role="alert">{{ $message }}</div>@enderror
                    </div>
                    <button class="btn btn-farm" type="submit">Verify code &amp; continue</button>
                </form>
            @endif
            @if($resetVerified)
                <form action="{{ route('password.update') }}" method="POST" data-auto-spinner>
                    @csrf
                    @method('PUT')
                    <div class="row g-3 mb-3">
                        @foreach(['current_password' => 'Current password', 'password' => 'New password', 'password_confirmation' => 'Confirm new password'] as $key => $label)
                            <div class="col-md-6">
                                <label class="form-label" for="profile-{{ $key }}">{{ $label }}</label>
                                <input class="form-control @error($key, 'updatePassword') is-invalid @enderror" id="profile-{{ $key }}" name="{{ $key }}" type="password" autocomplete="{{ $key === 'current_password' ? 'current-password' : 'new-password' }}" @if($key !== 'current_password') minlength="8" @endif required>
                                @error($key, 'updatePassword')<div class="invalid-feedback">{{ $message }}</div>@enderror
                            </div>
                        @endforeach
                    </div>
                    <p class="small text-muted">Use at least 8 characters. After resetting, you will need to sign in again.</p>
                    <button class="btn btn-farm" type="submit">Reset password</button>
                </form>
            @endif
            @if(!$resetVerified)
            <form action="{{ route('profile.password.code') }}" method="POST" class="{{ $resetCodeSent ? 'mt-3' : '' }}" data-auto-spinner>
                @csrf
                <button class="btn {{ $resetCodeSent ? 'btn-ghost' : 'btn-farm' }}" type="submit">{{ $resetCodeSent ? 'Send a new code' : 'Send verification code' }}</button>
                @if($resetCodeSent)<span class="small text-muted ms-2">You can request another code after one minute.</span>@endif
            </form>
            @endif
        </div>
    </section>
</div>
@endsection

@push('scripts')
<script src="{{ asset('js/admin-profile.js') }}?v={{ filemtime(public_path('js/admin-profile.js')) }}"></script>
@endpush
