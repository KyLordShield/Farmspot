@extends('layouts.app')

@section('title', 'Edit User')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Edit User</h1>
        <div class="page-desc">Update details for {{ $user->USR_ID }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('users') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Users
        </a>
    </div>
</div>

@if($errors->any())
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        <ul class="mb-0">
            @foreach($errors->all() as $error)
                <li>{{ $error }}</li>
            @endforeach
        </ul>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="panel form-card">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-pencil"></i>
            {{ $user->USR_NAME }}
        </h5>
    </div>
    <div class="panel-body">
        <form method="POST" action="{{ route('users.update', $user->USR_ID) }}">
            @csrf
            @method('PUT')

            <div class="mb-3">
                <label for="USR_NAME" class="form-label">Name</label>
                <input type="text" class="form-control @error('USR_NAME') is-invalid @enderror"
                       id="USR_NAME" name="USR_NAME"
                       value="{{ old('USR_NAME', $user->USR_NAME) }}" required>
                @error('USR_NAME')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="USR_EMAIL" class="form-label">Email</label>
                <input type="email" class="form-control @error('USR_EMAIL') is-invalid @enderror"
                       id="USR_EMAIL" name="USR_EMAIL"
                       value="{{ old('USR_EMAIL', $user->USR_EMAIL) }}" required>
                @error('USR_EMAIL')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="USR_MOBILE_NUMBER" class="form-label">Mobile Number</label>
                <input type="text" class="form-control @error('USR_MOBILE_NUMBER') is-invalid @enderror"
                       id="USR_MOBILE_NUMBER" name="USR_MOBILE_NUMBER"
                       value="{{ old('USR_MOBILE_NUMBER', $user->USR_MOBILE_NUMBER) }}" required>
                @error('USR_MOBILE_NUMBER')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="USR_ROLE" class="form-label">Role</label>
                <select class="form-select @error('USR_ROLE') is-invalid @enderror"
                        id="USR_ROLE" name="USR_ROLE" required>
                    <option value="GENERAL_USER"
                        {{ old('USR_ROLE', $user->USR_ROLE) == 'GENERAL_USER' ? 'selected' : '' }}>
                        General User
                    </option>
                    <option value="ADMIN"
                        {{ old('USR_ROLE', $user->USR_ROLE) == 'ADMIN' ? 'selected' : '' }}>
                        Admin
                    </option>
                </select>
                @error('USR_ROLE')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
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

            <div class="alert alert-secondary d-flex align-items-center" role="alert">
                <i class="bi bi-lock me-2"></i>
                <div>
                    Passwords are not edited here, and User ID <strong>{{ $user->USR_ID }}</strong>
                    cannot be changed.
                </div>
            </div>

            <div class="d-flex gap-2">
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-lg me-1"></i> Update User
                </button>
                <a href="{{ route('users') }}" class="btn btn-ghost">Cancel</a>
            </div>
        </form>
    </div>
</div>

@endsection