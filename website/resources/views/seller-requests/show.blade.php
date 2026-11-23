@extends('layouts.app')

@section('title', isset($farmOwner) ? 'Farm Details' : 'Seller Request Details')

@include('partials._admin-refresh')

@section('content')
<div class="admin-refresh admin-refresh-detail">
<div class="page-head">
    <div>
        <nav class="admin-refresh-crumb" aria-label="Breadcrumb">
            @if(isset($farmOwner))
                <a href="{{ route('users') }}">Users</a><span aria-hidden="true">/</span>
                <a href="{{ route('users.show', $farmOwner->USR_ID) }}">{{ $farmOwner->USR_NAME }}</a><span aria-hidden="true">/</span>
                <span aria-current="page">Farm details</span>
            @else
                <a href="{{ route('seller-requests') }}">Seller Requests</a><span aria-hidden="true">/</span><span aria-current="page">Request details</span>
            @endif
        </nav>
        <h1 class="page-title">{{ isset($farmOwner) ? 'Farm Details' : 'Seller Request Details' }}</h1>
        <div class="page-desc">{{ $farm->FRM_NAME }} · Farm #{{ $farm->FRM_ID }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ isset($farmOwner) ? route('users.show', $farmOwner->USR_ID) : route('seller-requests') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> {{ isset($farmOwner) ? 'Back to User Profile' : 'Back to Seller Requests' }}
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

<div class="admin-refresh-split">
    <div class="admin-refresh-stack">
        <div class="panel">
            <div class="panel-header">
                <h5 class="panel-title">
                    <i class="bi bi-house"></i>
                    {{ $farm->FRM_NAME }}
                </h5>
            </div>
            <div class="panel-body p-0">
                <dl class="admin-refresh-fields">

                    <div>
                        <dt>Status</dt>
                        <dd>
                            @if($farm->FRM_STATUS == 'APPROVED')
                                <span class="badge badge-soft-success">Approved</span>
                            @elseif($farm->FRM_STATUS == 'REJECTED')
                                <span class="badge badge-soft-danger">Rejected</span>
                            @else
                                <span class="badge badge-soft-warning">Pending Review</span>
                            @endif
                        </dd>
                    </div>

                    <div>
                        <dt>Farm Name</dt>
                        <dd>{{ $farm->FRM_NAME }}</dd>
                    </div>

                    <div class="admin-refresh-wide">
                        <dt>Description</dt>
                        <dd>{{ $farm->FRM_DESCRIPTION ?? '-' }}</dd>
                    </div>

                    <div>
                        <dt>Barangay</dt>
                        <dd>{{ $farm->FRM_BARANGAY }}</dd>
                    </div>

                    <div>
                        <dt>Coordinates</dt>
                        <dd><span class="id-cell">{{ $farm->FRM_LATITUDE }}, {{ $farm->FRM_LONGITUDE }}</span></dd>
                    </div>

                    <div>
                        <dt>Submitted At</dt>
                        <dd class="cell-secondary">{{ \Carbon\Carbon::parse($farm->FRM_CREATED_AT)->timezone(config('farmspot.display_timezone'))->format('M d, Y h:i A') }}</dd>
                    </div>

                </dl>
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
                <dl class="admin-refresh-fields">

                    <div>
                        <dt>Owner Name</dt>
                        <dd>{{ $farm->farmer?->buyer?->user?->USR_NAME ?? '-' }} @include('users.partials.profile-link', ['profileUser' => $farm->farmer?->buyer?->user])</dd>
                    </div>

                    <div>
                        <dt>Email</dt>
                        <dd>{{ $farm->farmer?->buyer?->user?->USR_EMAIL ?? '-' }}</dd>
                    </div>

                    <div>
                        <dt>Mobile Number</dt>
                        <dd>{{ $farm->farmer?->buyer?->user?->USR_MOBILE_NUMBER ?? '-' }}</dd>
                    </div>

                </dl>
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
                    'url'   => route('seller-requests.document', ['id' => $farm->FRM_ID, 'document' => 'id']),
                    'source' => $farm->FRM_VERIFICATION_DOC_PATH,
                ];
            }

            if ($farm->FRM_FARM_CERTIFICATE_PATH) {
                $viewerDocuments[] = [
                    'label' => 'Farm Permit / Certificate',
                    'url'   => route('seller-requests.document', ['id' => $farm->FRM_ID, 'document' => 'permit']),
                    'source' => $farm->FRM_FARM_CERTIFICATE_PATH,
                ];
            }
        @endphp

        @foreach($viewerDocuments as $document)
            @php
                $documentExtension = strtolower(pathinfo(parse_url($document['source'], PHP_URL_PATH) ?: '', PATHINFO_EXTENSION));
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
    </div>
    @if($farm->FRM_STATUS == 'PENDING_REVIEW')
    <aside class="admin-refresh-sidebar" aria-label="Seller request decision">
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
                        <label for="seller-rejection-reason" class="form-label">Reason for rejection (optional)</label>
                        <textarea id="seller-rejection-reason" name="reason" class="form-control mb-2" rows="2"
                                  placeholder="Reason for rejection (optional)">{{ old('reason') }}</textarea>
                        <button type="submit" class="btn btn-outline-danger">
                            <i class="bi bi-x-circle me-1"></i> Reject
                        </button>
                    </form>

                </div>
            </div>
        </div>
    </aside>
    @endif
</div>

@include('partials._media-modal')
</div>
@endsection
