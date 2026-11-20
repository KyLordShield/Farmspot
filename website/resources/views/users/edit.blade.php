@extends('layouts.app')

@section('title', 'Edit User')

@push('styles')
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap">
    <link rel="stylesheet" href="{{ asset('css/user-details.css') }}?v={{ filemtime(public_path('css/user-details.css')) }}">
@endpush

@push('scripts')
    <script src="{{ asset('js/user-edit.js') }}?v={{ filemtime(public_path('js/user-edit.js')) }}" defer></script>
@endpush

@section('content')
@php
    $canDeactivate = $user->USR_STATUS !== 'DEACTIVATED';
    $showReason = $canDeactivate && old('USR_STATUS', $user->USR_STATUS) === 'DEACTIVATED';
@endphp

<div class="user-details">
    <nav class="user-details-breadcrumb" aria-label="Breadcrumb">
        <a href="{{ route('users') }}">Users</a>
        <span aria-hidden="true">/</span>
        <a href="{{ route('users.show', $user->USR_ID) }}">{{ $user->USR_NAME }}</a>
        <span aria-hidden="true">/</span>
        <span aria-current="page">Edit User</span>
    </nav>
    <header class="user-details-header">
        <h1>Edit User</h1>
        <a href="{{ route('users') }}" class="user-details-button user-details-back">
            <i class="bi bi-arrow-left" aria-hidden="true"></i> Back to Users
        </a>
    </header>

    @if($errors->any())
        <div class="alert alert-danger" role="alert">
            <ul class="mb-0">
                @foreach($errors->all() as $error)
                    <li>{{ $error }}</li>
                @endforeach
            </ul>
        </div>
    @endif

    <form method="POST" action="{{ route('users.update', $user->USR_ID) }}" class="user-details-sections user-edit-form" data-auto-spinner>
        @csrf
        @method('PUT')

        <section class="user-details-card" aria-labelledby="edit-contact-heading">
            <h2 id="edit-contact-heading">Contact Information</h2>
            <div class="user-details-fields">
                <div class="user-edit-field">
                    <label for="USR_NAME" class="form-label">Name</label>
                    <input type="text" class="form-control @error('USR_NAME') is-invalid @enderror"
                           id="USR_NAME" name="USR_NAME"
                           value="{{ old('USR_NAME', $user->USR_NAME) }}" required>
                    @error('USR_NAME')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>

                <div class="user-edit-field">
                    <label for="USR_EMAIL" class="form-label">Email</label>
                    <input type="email" class="form-control @error('USR_EMAIL') is-invalid @enderror"
                           id="USR_EMAIL" name="USR_EMAIL"
                           value="{{ old('USR_EMAIL', $user->USR_EMAIL) }}" required>
                    @error('USR_EMAIL')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>

                <div class="user-edit-field">
                    <label for="USR_MOBILE_NUMBER" class="form-label">Mobile Number</label>
                    <input type="text" class="form-control @error('USR_MOBILE_NUMBER') is-invalid @enderror"
                           id="USR_MOBILE_NUMBER" name="USR_MOBILE_NUMBER"
                           value="{{ old('USR_MOBILE_NUMBER', $user->USR_MOBILE_NUMBER) }}" required>
                    @error('USR_MOBILE_NUMBER')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>
            </div>
        </section>

        <section class="user-details-card" aria-labelledby="edit-account-heading">
            <h2 id="edit-account-heading">Account Details</h2>
            <div class="user-details-fields">
                <div>
                    <span class="user-details-label">Role</span>
                    <div class="mt-1">
                        <span class="user-details-pill user-details-blue">{{ $user->USR_ROLE === 'ADMIN' ? 'Admin' : ($user->isFarmer() ? 'Farmer' : 'Buyer') }}</span>
                    </div>
                </div>
                <div class="user-edit-field">
                    <label for="USR_STATUS" class="form-label">Status</label>
                    <select class="form-select @error('USR_STATUS') is-invalid @enderror"
                            id="USR_STATUS" name="USR_STATUS" required>
                        <option value="ACTIVE"
                            {{ old('USR_STATUS', $user->USR_STATUS) == 'ACTIVE' ? 'selected' : '' }}>
                            Active
                        </option>
                        <option value="PENDING_VERIFICATION"
                            {{ old('USR_STATUS', $user->USR_STATUS) == 'PENDING_VERIFICATION' ? 'selected' : '' }}>
                            Pending Verification
                        </option>
                        <option value="DEACTIVATED"
                            {{ old('USR_STATUS', $user->USR_STATUS) == 'DEACTIVATED' ? 'selected' : '' }}>
                            Deactivated
                        </option>
                    </select>
                    @error('USR_STATUS')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>
                <div>
                    <span class="user-details-label">User ID</span>
                    <div class="mt-1"><code>{{ $user->USR_ID }}</code></div>
                </div>
                @if($canDeactivate)
                    <div class="user-details-wide user-edit-reason" data-deactivation-reason @if(!$showReason) hidden @endif>
                        <label for="USR_TAKEDOWN_REASON" class="form-label">Reason for deactivation</label>
                        <textarea class="form-control @error('USR_TAKEDOWN_REASON') is-invalid @enderror"
                                  id="USR_TAKEDOWN_REASON" name="USR_TAKEDOWN_REASON"
                                  rows="3" maxlength="500" aria-describedby="deactivation-help"
                                  @required($showReason) @disabled(!$showReason)>{{ old('USR_TAKEDOWN_REASON') }}</textarea>
                        <div class="form-text" id="deactivation-help">The user sees this at sign-in and can request a review.</div>
                        @error('USR_TAKEDOWN_REASON')
                            <div class="text-danger small mt-1">{{ $message }}</div>
                        @enderror
                    </div>
                @endif
            </div>
        </section>

        <div class="user-details-actions">
            <button type="submit" class="user-details-button user-details-edit">
                <i class="bi bi-check-lg" aria-hidden="true"></i> Update User
            </button>
            <a href="{{ route('users') }}" class="user-details-button user-details-back">Cancel</a>
        </div>
    </form>
</div>
@endsection
