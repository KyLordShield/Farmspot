@extends('layouts.app')

@section('title', 'Add User')

@include('partials._admin-refresh')

@section('content')
<div class="admin-refresh admin-refresh-form">
<div class="page-head">
    <div>
        <nav class="admin-refresh-crumb" aria-label="Breadcrumb">
            <a href="{{ route('users') }}">Users</a><span aria-hidden="true">/</span><span aria-current="page">Add User</span>
        </nav>
        <h1 class="page-title">Add User</h1>
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
        <h2 class="panel-title">
            <i class="bi bi-person-plus"></i>
            Contact details
        </h2>
    </div>
    <div class="panel-body">
        <form method="POST" action="{{ route('users.store') }}" data-auto-spinner>
            @csrf

            <div class="row g-4 mb-4">
                <div class="col-12">
                    <label for="USR_NAME" class="form-label">Full Name</label>
                    <input type="text" class="form-control @error('USR_NAME') is-invalid @enderror"
                           id="USR_NAME" name="USR_NAME" value="{{ old('USR_NAME') }}" autocomplete="name" required>
                    @error('USR_NAME')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>

                <div class="col-12 col-md-6">
                    <label for="USR_EMAIL" class="form-label">Email</label>
                    <input type="email" class="form-control @error('USR_EMAIL') is-invalid @enderror"
                           id="USR_EMAIL" name="USR_EMAIL" value="{{ old('USR_EMAIL') }}" autocomplete="email" required>
                    @error('USR_EMAIL')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>

                <div class="col-12 col-md-6">
                    <label for="USR_MOBILE_NUMBER" class="form-label">Mobile Number</label>
                    <input type="tel" class="form-control @error('USR_MOBILE_NUMBER') is-invalid @enderror"
                           id="USR_MOBILE_NUMBER" name="USR_MOBILE_NUMBER"
                           value="{{ old('USR_MOBILE_NUMBER') }}" autocomplete="tel" required>
                    @error('USR_MOBILE_NUMBER')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>

                <div class="col-12"><h2 class="panel-title admin-form-divider">Sign-in details</h2></div>

                <div class="col-12 col-md-6">
                    <label for="USR_PASSWORD" class="form-label">Password</label>
                    <input type="password" class="form-control @error('USR_PASSWORD') is-invalid @enderror"
                           id="USR_PASSWORD" name="USR_PASSWORD" required autocomplete="new-password">
                    @error('USR_PASSWORD')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>

                <div class="col-12 col-md-6">
                    <label for="USR_PASSWORD_confirmation" class="form-label">Confirm Password</label>
                    <input type="password" class="form-control"
                           id="USR_PASSWORD_confirmation" name="USR_PASSWORD_confirmation"
                           required autocomplete="new-password">
                </div>
            </div>

            <div class="d-flex align-items-start gap-2 rounded border bg-body-tertiary p-3 mb-4">
                <i class="bi bi-info-circle mt-1" aria-hidden="true"></i>
                <div>
                    <div class="fw-semibold">Account access</div>
                    <p class="small mb-0">The new account will be active immediately and have standard user access.</p>
                </div>
            </div>

            <div class="d-flex flex-wrap gap-2 border-top pt-3">
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-lg me-1"></i> Create User
                </button>
                <a href="{{ route('users') }}" class="btn btn-ghost">Cancel</a>
            </div>
        </form>
    </div>
</div>
</div>
@endsection
