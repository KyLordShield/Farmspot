@extends('layouts.app')

@section('title', 'Seller Request Details')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">
    <div>
        <h2 class="fw-bold mb-0">Seller Request Details</h2>
        <small class="text-muted">Farm #{{ $farm->FRM_ID }}</small>
    </div>
    <a href="{{ route('seller-requests') }}" class="btn btn-outline-secondary">
        <i class="bi bi-arrow-left"></i> Back to Seller Requests
    </a>
</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

@if(session('error'))
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        {{ session('error') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="card shadow-sm border-0 rounded-4">
    <div class="card-header bg-success text-white">
        <h4 class="mb-0"><i class="bi bi-house-fill"></i> {{ $farm->FRM_NAME }}</h4>
    </div>
    <div class="card-body">
        <table class="table">

            <tr>
                <th>Status</th>
                <td>
                    @if($farm->FRM_STATUS == 'APPROVED')
                        <span class="badge bg-success">Approved</span>
                    @elseif($farm->FRM_STATUS == 'REJECTED')
                        <span class="badge bg-danger">Rejected</span>
                    @else
                        <span class="badge bg-warning text-dark">Pending Review</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Farm Name</th>
                <td>{{ $farm->FRM_NAME }}</td>
            </tr>

            <tr>
                <th>Description</th>
                <td>{{ $farm->FRM_DESCRIPTION ?? '-' }}</td>
            </tr>

            <tr>
                <th>Barangay</th>
                <td>{{ $farm->FRM_BARANGAY }}</td>
            </tr>

            <tr>
                <th>Coordinates</th>
                <td>{{ $farm->FRM_LATITUDE }}, {{ $farm->FRM_LONGITUDE }}</td>
            </tr>

            <tr>
                <th>Submitted At</th>
                <td>{{ \Carbon\Carbon::parse($farm->FRM_CREATED_AT)->format('M d, Y h:i A') }}</td>
            </tr>

        </table>
    </div>
</div>

<div class="card shadow-sm border-0 rounded-4 mt-4">
    <div class="card-header bg-primary text-white">
        <h4 class="mb-0"><i class="bi bi-person-fill"></i> Owner Information</h4>
    </div>
    <div class="card-body">
        <table class="table">

            <tr>
                <th>Owner Name</th>
                <td>{{ $farm->farmer?->buyer?->user?->USR_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Email</th>
                <td>{{ $farm->farmer?->buyer?->user?->USR_EMAIL ?? '-' }}</td>
            </tr>

            <tr>
                <th>Mobile Number</th>
                <td>{{ $farm->farmer?->buyer?->user?->USR_MOBILE_NUMBER ?? '-' }}</td>
            </tr>

        </table>
    </div>
</div>

@if($farm->photos->isNotEmpty())
<div class="card shadow-sm border-0 rounded-4 mt-4">
    <div class="card-header bg-info text-white">
        <h4 class="mb-0"><i class="bi bi-images"></i> Farm Photos</h4>
    </div>
    <div class="card-body">
        <div class="row g-3">
            @foreach($farm->photos as $photo)
                <div class="col-6 col-md-3">
                    <a href="{{ $photo->FPHOTO_FILE_PATH }}" target="_blank">
                        <img src="{{ $photo->FPHOTO_FILE_PATH }}"
                             alt="Farm photo"
                             class="img-fluid rounded-3"
                             style="width: 100%; height: 180px; object-fit: cover;">
                    </a>
                </div>
            @endforeach
        </div>
    </div>
</div>
@endif

@if($farm->FRM_VERIFICATION_DOC_PATH)
<div class="card shadow-sm border-0 rounded-4 mt-4">
    <div class="card-header bg-secondary text-white">
        <h4 class="mb-0"><i class="bi bi-file-earmark-check-fill"></i> Verification Document</h4>
    </div>
    <div class="card-body">
        <a href="{{ $farm->FRM_VERIFICATION_DOC_PATH }}" target="_blank" class="btn btn-outline-secondary">
            <i class="bi bi-file-earmark-arrow-down"></i> View Document
        </a>
    </div>
</div>
@endif

@if($farm->FRM_STATUS == 'PENDING_REVIEW')
<div class="card shadow-sm border-0 rounded-4 mt-4">
    <div class="card-header bg-dark text-white">
        <h4 class="mb-0"><i class="bi bi-check2-square"></i> Decision</h4>
    </div>
    <div class="card-body">

        <form method="POST" action="{{ route('seller-requests.approve', $farm->FRM_ID) }}"
              class="d-inline"
              onsubmit="return confirm('Are you sure you want to approve this seller request?');">
            @csrf
            <button type="submit" class="btn btn-success">
                <i class="bi bi-check-circle"></i> Approve
            </button>
        </form>

        <form method="POST" action="{{ route('seller-requests.reject', $farm->FRM_ID) }}"
              class="d-inline-block align-top ms-2"
              style="max-width: 420px;"
              onsubmit="return confirm('Are you sure you want to reject this seller request?');">
            @csrf
            <div class="mb-2">
                <textarea name="reason" class="form-control" rows="2"
                          placeholder="Reason (optional)">{{ old('reason') }}</textarea>
            </div>
            <button type="submit" class="btn btn-danger">
                <i class="bi bi-x-circle"></i> Reject
            </button>
        </form>

    </div>
</div>
@endif

@endsection
