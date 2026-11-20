@extends('layouts.app')

@section('title', 'Profile')
@include('partials._admin-refresh')

@section('content')
<div class="admin-refresh admin-refresh-form">
    <div class="page-head">
        <div>
            <nav class="admin-refresh-crumb" aria-label="Breadcrumb">
                <a href="{{ route('dashboard') }}">Dashboard</a><span aria-hidden="true">/</span><span aria-current="page">Profile</span>
            </nav>
            <h1 class="page-title">Profile</h1>
        </div>
    </div>

    @if(in_array(session('status'), ['profile-updated', 'password-updated', 'verification-link-sent'], true))
        <div class="alert alert-success" role="status">{{ match (session('status')) {
            'profile-updated' => 'Profile updated.',
            'password-updated' => 'Password updated.',
            default => 'Verification link sent.',
        } }}</div>
    @endif

    <section class="panel form-card">
        <div class="panel-header"><h2 class="panel-title">Contact details</h2></div>
        <div class="panel-body">
            <form action="{{ route('profile.update') }}" method="POST" data-auto-spinner>
                @csrf
                @method('PATCH')
                <div class="row g-3 mb-3">
                    @foreach(['name' => ['Name', 'text', $user->USR_NAME, 'name'], 'email' => ['Email', 'email', $user->USR_EMAIL, 'username']] as $key => [$label, $type, $value, $autocomplete])
                        <div class="col-md-6">
                            <label class="form-label" for="profile-{{ $key }}">{{ $label }}</label>
                            <input class="form-control @error($key) is-invalid @enderror" id="profile-{{ $key }}"
                                   name="{{ $key }}" type="{{ $type }}" value="{{ old($key, $value) }}"
                                   autocomplete="{{ $autocomplete }}" required>
                            @error($key)<div class="invalid-feedback">{{ $message }}</div>@enderror
                        </div>
                    @endforeach
                </div>
                <button class="btn btn-farm" type="submit">Save changes</button>
            </form>
            @if($user instanceof \Illuminate\Contracts\Auth\MustVerifyEmail && !$user->hasVerifiedEmail())
                <form action="{{ route('verification.send') }}" method="POST" class="mt-3">
                    @csrf
                    <p>Your email address is unverified.</p>
                    <button class="btn btn-ghost" type="submit">Resend verification email</button>
                </form>
            @endif
        </div>
    </section>

    <section class="panel form-card">
        <div class="panel-header"><h2 class="panel-title">Password</h2></div>
        <div class="panel-body">
            <form action="{{ route('password.update') }}" method="POST" data-auto-spinner>
                @csrf
                @method('PUT')
                <div class="row g-3 mb-3">
                    @foreach(['current_password' => 'Current password', 'password' => 'New password', 'password_confirmation' => 'Confirm new password'] as $key => $label)
                        <div class="col-md-6">
                            <label class="form-label" for="profile-{{ $key }}">{{ $label }}</label>
                            <input class="form-control @error($key, 'updatePassword') is-invalid @enderror" id="profile-{{ $key }}"
                                   name="{{ $key }}" type="password" autocomplete="{{ $key === 'current_password' ? 'current-password' : 'new-password' }}" required>
                            @error($key, 'updatePassword')<div class="invalid-feedback">{{ $message }}</div>@enderror
                        </div>
                    @endforeach
                </div>
                <button class="btn btn-farm" type="submit">Update password</button>
            </form>
        </div>
    </section>

    <section class="panel form-card">
        <div class="panel-header"><h2 class="panel-title">Delete account</h2></div>
        <div class="panel-body">
            <p>Deleting your account is permanent.</p>
            @error('password', 'userDeletion')<div class="alert alert-danger" role="alert">{{ $message }}</div>@enderror
            <button class="btn btn-outline-danger" type="button" data-bs-toggle="modal" data-bs-target="#profile-delete-modal">Delete account</button>
        </div>
    </section>

    <div class="modal fade" id="profile-delete-modal" tabindex="-1" aria-labelledby="profile-delete-title" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
            <form class="modal-content" action="{{ route('profile.destroy') }}" method="POST">
                @csrf
                @method('DELETE')
                <div class="modal-header">
                    <h2 class="modal-title fs-6" id="profile-delete-title">Delete your account?</h2>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <p>Enter your password to confirm permanent deletion.</p>
                    <label class="form-label" for="profile-delete-password">Password</label>
                    <input class="form-control" id="profile-delete-password" name="password" type="password" autocomplete="current-password" required>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-ghost" data-bs-dismiss="modal">Cancel</button>
                    <button type="submit" class="btn btn-danger">Delete account</button>
                </div>
            </form>
        </div>
    </div>
</div>
@endsection
