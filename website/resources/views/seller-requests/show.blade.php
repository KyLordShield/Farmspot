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
                    <button type="button"
                            class="btn-photo"
                            data-bs-toggle="modal"
                            data-bs-target="#documentModal"
                            data-document-url="{{ $photo->FPHOTO_FILE_PATH }}"
                            data-document-title="Farm photo"
                            data-document-kind="image">
                        <img src="{{ $photo->FPHOTO_FILE_PATH }}"
                             alt="Farm photo"
                             class="photo-thumb">
                    </button>
                </div>
            @endforeach
        </div>
    </div>
</div>
@endif

@php
    $viewerDocuments = [];

    if ($farm->FRM_VERIFICATION_DOC_PATH) {
        $viewerDocuments[] = [
            'label' => 'Valid ID Document',
            'url'   => $farm->FRM_VERIFICATION_DOC_PATH,
        ];
    }

    if ($farm->FRM_FARM_CERTIFICATE_PATH) {
        $viewerDocuments[] = [
            'label' => 'Farm Permit / Certificate',
            'url'   => $farm->FRM_FARM_CERTIFICATE_PATH,
        ];
    }
@endphp

@foreach($viewerDocuments as $document)
    @php
        $documentExtension = strtolower(pathinfo(parse_url($document['url'], PHP_URL_PATH) ?: '', PATHINFO_EXTENSION));
    @endphp
    <div class="panel">
        <div class="panel-header">
            <h5 class="panel-title">
                <i class="bi bi-file-earmark-check"></i>
                {{ $document['label'] }}
            </h5>
        </div>
        <div class="panel-body">
            <button type="button"
                    class="btn btn-ghost"
                    data-bs-toggle="modal"
                    data-bs-target="#documentModal"
                    data-document-url="{{ $document['url'] }}"
                    data-document-title="{{ $document['label'] }}"
                    data-document-kind="{{ in_array($documentExtension, ['jpg', 'jpeg', 'png', 'gif', 'webp'], true) ? 'image' : 'file' }}">
                <i class="bi bi-file-earmark-arrow-down me-1"></i> View Document
            </button>
        </div>
    </div>
@endforeach

@if($farm->FRM_STATUS == 'PENDING_REVIEW')
<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-check2-square"></i>
            Decision
        </h5>
    </div>
    <div class="panel-body">
        <div class="decision-grid">

            <form method="POST" action="{{ route('seller-requests.approve', $farm->FRM_ID) }}"
                  data-confirm-title="Approve seller request?"
                  data-confirm-text="Approve {{ $farm->FRM_NAME }}? The farm goes live for the owner immediately.">
                @csrf
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-circle me-1"></i> Approve
                </button>
            </form>

            <form method="POST" action="{{ route('seller-requests.reject', $farm->FRM_ID) }}"
                  data-confirm-title="Reject seller request?"
                  data-confirm-text="Reject {{ $farm->FRM_NAME }}? The owner is notified of the rejection."
                  data-confirm-tone="danger">
                @csrf
                <textarea name="reason" class="form-control mb-2" rows="2"
                          placeholder="Reason for rejection (optional)">{{ old('reason') }}</textarea>
                <button type="submit" class="btn btn-danger">
                    <i class="bi bi-x-circle me-1"></i> Reject
                </button>
            </form>

        </div>
    </div>
</div>
@endif

@include('partials._media-modal')

@endsection