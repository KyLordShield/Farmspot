@extends('layouts.app')

@section('title', 'Add User')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">
    <div>
        <h2 class="fw-bold mb-0">Add User</h2>
        <small class="text-muted">Create a new general user account</small>
    </div>
    <a href="{{ route('users') }}" class="btn btn-outline-secondary">
        <i class="bi bi-arrow-left"></i> Back to Users
    </a>
</div>

@if($errors->any())
    <div class="alert alert-danger">
        <ul class="mb-0">
            @foreach($errors->all() as $error)
                <li>{{ $error }}</li>
            @endforeach
        </ul>
    </div>
@endif

<div class="card shadow-sm border-0 rounded-4">
    <div class="card-header bg-success text-white">
        <h4 class="mb-0"><i class="bi bi-person-plus-fill"></i> New User</h4>
    </div>
    <div class="card-body">
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
                <i class="bi bi-info-circle-fill me-2"></i>
                New users are created with role <strong>GENERAL_USER</strong> and status
                <strong>ACTIVE</strong>. Admin accounts can only be created via the seeder.
            </div>

            <div class="d-flex gap-2">
                <button type="submit" class="btn btn-success">
                    <i class="bi bi-check-lg"></i> Create User
                </button>
                <a href="{{ route('users') }}" class="btn btn-secondary">Cancel</a>
            </div>
        </form>
    </div>
</div>

@endsection