@extends('layouts.app')

@section('title', 'Seller Request Details')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Seller Request Details</h1>
        <div class="page-desc">{{ $farm->FRM_NAME }} · Farm #{{ $farm->FRM_ID }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('seller-requests') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Seller Requests
        </a>
    </div>
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

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-house"></i>
            {{ $farm->FRM_NAME }}
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">

            <tr>
                <th>Status</th>
                <td>
                    @if($farm->FRM_STATUS == 'APPROVED')
                        <span class="badge badge-soft-success">Approved</span>
                    @elseif($farm->FRM_STATUS == 'REJECTED')
                        <span class="badge badge-soft-danger">Rejected</span>
                    @else
                        <span class="badge badge-soft-warning">Pending Review</span>
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
                <td><span class="id-cell">{{ $farm->FRM_LATITUDE }}, {{ $farm->FRM_LONGITUDE }}</span></td>
            </tr>

            <tr>
                <th>Submitted At</th>
                <td class="cell-secondary">{{ \Carbon\Carbon::parse($farm->FRM_CREATED_AT)->format('M d, Y h:i A') }}</td>
            </tr>

        </table>
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-person"></i>
            Owner Information
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">

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
<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-images"></i>
            Farm Photos
        </h5>
    </div>
    <div class="panel-body">
        <div class="row g-3 photo-grid">
            @foreach($farm->photos as $photo)
                <div class="col-6 col-md-3">
                    <a href="{{ $photo->FPHOTO_FILE_PATH }}" target="_blank">
                        <img src="{{ $photo->FPHOTO_FILE_PATH }}"
                             alt="Farm photo"
                             class="photo-thumb">
                    </a>
                </div>
            @endforeach
        </div>
    </div>
</div>
@endif

@if($farm->FRM_VERIFICATION_DOC_PATH)
<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-file-earmark-check"></i>
            Verification Document
        </h5>
    </div>
    <div class="panel-body">
        <a href="{{ $farm->FRM_VERIFICATION_DOC_PATH }}" target="_blank" class="btn btn-ghost">
            <i class="bi bi-file-earmark-arrow-down me-1"></i> View Document
        </a>
    </div>
</div>
@endif

@if($farm->FRM_STATUS == 'PENDING_REVIEW')
<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-check2-square"></i>
            Decision
        </h5>
    </div>
    <div class="panel-body">
        <div class="detail-actions">

            <form method="POST" action="{{ route('seller-requests.approve', $farm->FRM_ID) }}"
                  class="d-inline"
                  onsubmit="return confirm('Are you sure you want to approve this seller request?');">
                @csrf
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-circle me-1"></i> Approve
                </button>
            </form>

            <form method="POST" action="{{ route('seller-requests.reject', $farm->FRM_ID) }}"
                  class="d-inline-block"
                  style="max-width: 420px;"
                  onsubmit="return confirm('Are you sure you want to reject this seller request?');">
                @csrf
                <div class="mb-2">
                    <textarea name="reason" class="form-control" rows="2"
                              placeholder="Reason (optional)">{{ old('reason') }}</textarea>
                </div>
                <button type="submit" class="btn btn-danger">
                    <i class="bi bi-x-circle me-1"></i> Reject
                </button>
            </form>

        </div>
    </div>
</div>
@endif

@endsection