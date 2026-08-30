@extends('layouts.app')

@section('title', 'Add Mobile Number')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">
    <div>
        <h2 class="fw-bold mb-0">Add Mobile Number</h2>
        <small class="text-muted">Pre-approve a new mobile number</small>
    </div>
    <a href="{{ route('whitelist') }}" class="btn btn-outline-secondary">
        <i class="bi bi-arrow-left"></i> Back to Whitelist
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
        <h4 class="mb-0"><i class="bi bi-plus-circle-fill"></i> New Number</h4>
    </div>
    <div class="card-body">
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

            <div class="alert alert-info" role="alert">
                <i class="bi bi-info-circle-fill me-2"></i>
                This number will be marked as <strong>Active</strong> immediately upon adding.
            </div>

            <div class="d-flex gap-2">
                <button type="submit" class="btn btn-success">
                    <i class="bi bi-check-lg"></i> Add Number
                </button>
                <a href="{{ route('whitelist') }}" class="btn btn-secondary">Cancel</a>
            </div>
        </form>
    </div>
</div>

@endsection