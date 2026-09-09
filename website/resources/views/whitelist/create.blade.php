@extends('layouts.app')

@section('title', 'Add Mobile Number')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Add Mobile Number</h1>
        <div class="page-desc">Pre-approve a new mobile number</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('whitelist') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Whitelist
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
            <i class="bi bi-plus-circle"></i>
            New Number
        </h5>
    </div>
    <div class="panel-body">
        <form method="POST" action="{{ route('whitelist.store') }}">
            @csrf

            <div class="mb-3">
                <label for="WLST_MOBILE_NUMBER" class="form-label">Mobile Number</label>
                <input type="text" class="form-control @error('WLST_MOBILE_NUMBER') is-invalid @enderror"
                       id="WLST_MOBILE_NUMBER" name="WLST_MOBILE_NUMBER"
                       value="{{ old('WLST_MOBILE_NUMBER') }}" required>
                @error('WLST_MOBILE_NUMBER')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="alert alert-info d-flex align-items-center" role="alert">
                <i class="bi bi-info-circle me-2"></i>
                <div>
                    This number will be marked as <strong>Active</strong> immediately upon adding.
                </div>
            </div>

            <div class="d-flex gap-2">
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-lg me-1"></i> Add Number
                </button>
                <a href="{{ route('whitelist') }}" class="btn btn-ghost">Cancel</a>
            </div>
        </form>
    </div>
</div>

@endsection