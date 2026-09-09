@extends('layouts.app')

@section('title', 'Add User')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Add User</h1>
        <div class="page-desc">Create a new general user account</div>
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
            <i class="bi bi-person-plus"></i>
            New User
        </h5>
    </div>
    <div class="panel-body">
        <form method="POST" action="{{ route('users.store') }}">
            @csrf

            <div class="mb-3">
                <label for="USR_NAME" class="form-label">Name</label>
                <input type="text" class="form-control @error('USR_NAME') is-invalid @enderror"
                       id="USR_NAME" name="USR_NAME" value="{{ old('USR_NAME') }}" required>
                @error('USR_NAME')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="USR_EMAIL" class="form-label">Email</label>
                <input type="email" class="form-control @error('USR_EMAIL') is-invalid @enderror"
                       id="USR_EMAIL" name="USR_EMAIL" value="{{ old('USR_EMAIL') }}" required>
                @error('USR_EMAIL')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="USR_PASSWORD" class="form-label">Password</label>
                <input type="password" class="form-control @error('USR_PASSWORD') is-invalid @enderror"
                       id="USR_PASSWORD" name="USR_PASSWORD" required autocomplete="new-password">
                @error('USR_PASSWORD')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="USR_PASSWORD_confirmation" class="form-label">Confirm Password</label>
                <input type="password" class="form-control"
                       id="USR_PASSWORD_confirmation" name="USR_PASSWORD_confirmation"
                       required autocomplete="new-password">
            </div>

            <div class="mb-3">
                <label for="USR_MOBILE_NUMBER" class="form-label">Mobile Number</label>
                <input type="text" class="form-control @error('USR_MOBILE_NUMBER') is-invalid @enderror"
                       id="USR_MOBILE_NUMBER" name="USR_MOBILE_NUMBER"
                       value="{{ old('USR_MOBILE_NUMBER') }}" required>
                @error('USR_MOBILE_NUMBER')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="alert alert-info d-flex align-items-center" role="alert">
                <i class="bi bi-info-circle me-2"></i>
                <div>
                    New users are created with role <strong>GENERAL_USER</strong> and status
                    <strong>ACTIVE</strong>. Admin accounts can only be created via the seeder.
                </div>
            </div>

            <div class="d-flex gap-2">
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-lg me-1"></i> Create User
                </button>
                <a href="{{ route('users') }}" class="btn btn-ghost">Cancel</a>
            </div>
        </form>
    </div>
</div>

@endsection