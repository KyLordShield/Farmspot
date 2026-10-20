@extends('layouts.app')

@section('title', 'Appeal Details')

@section('content')

@php
    $isListing = $appeal->RRQ_TARGET_TYPE === \App\Models\ReviewRequest::TARGET_LISTING;
    $targetLabel = $isListing ? 'Crop listing' : 'User account';
    $targetName = $isListing
        ? $appeal->listing?->farm?->FRM_NAME
        : $appeal->account?->USR_NAME;

    $statusLabel = match ($appeal->RRQ_STATUS) {
        \App\Models\ReviewRequest::STATUS_PENDING => 'Pending',
        \App\Models\ReviewRequest::STATUS_APPROVED => 'Approved',
        default => 'Denied',
    };
    $statusClass = match ($appeal->RRQ_STATUS) {
        \App\Models\ReviewRequest::STATUS_PENDING => 'badge-soft-warning',
        \App\Models\ReviewRequest::STATUS_APPROVED => 'badge-soft-success',
        default => 'badge-soft-neutral',
    };

    $displayTz = config('farmspot.display_timezone');
    $submittedAt = \Carbon\Carbon::parse($appeal->RRQ_CREATED_AT)->timezone($displayTz);
    $decidedAt = $appeal->RRQ_DECIDED_AT
        ? \Carbon\Carbon::parse($appeal->RRQ_DECIDED_AT)->timezone($displayTz)
        : null;
@endphp

<div class="page-head">
    <div>
        <h1 class="page-title">Appeal Details</h1>
        <div class="page-desc">
            Appeal <span class="id-cell">{{ $appeal->RRQ_ID }}</span>
            &middot; {{ $targetLabel }} <span class="id-cell">{{ $appeal->RRQ_TARGET_ID }}</span>
        </div>
    </div>
    <div class="page-actions">
        <span class="badge {{ $statusClass }}">{{ $statusLabel }}</span>
        <a href="{{ route('appeals') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Appeals
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

<div class="row g-4">

    <div class="col-lg-8">

        <div class="panel">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-file-earmark-text"></i>
                        Appeal summary
                    </h5>
                    <div class="panel-sub">Who filed it, what it is about, and when.</div>
                </div>
                <span class="badge {{ $statusClass }}">{{ $statusLabel }}</span>
            </div>
            <div class="panel-body p-0">
                <table class="detail-table">
                    <tr>
                        <th>Appeal ID</th>
                        <td><span class="id-cell">{{ $appeal->RRQ_ID }}</span></td>
                    </tr>
                    <tr>
                        <th>Target</th>
                        <td>
                            <span class="badge badge-soft-neutral">{{ $targetLabel }}</span>
                            <span class="id-cell ms-2">{{ $appeal->RRQ_TARGET_ID }}</span>
                            @if($targetName)
                                <div class="cell-secondary mt-1">{{ $targetName }}</div>
                            @endif
                        </td>
                    </tr>
                    <tr>
                        <th>Requester</th>
                        <td>
                            {{ $appeal->user?->USR_NAME ?? '-' }}
                            @if($appeal->user?->USR_EMAIL)
                                <div class="cell-secondary">{{ $appeal->user->USR_EMAIL }}</div>
                            @endif
                            <span class="id-cell ms-2">{{ $appeal->USR_ID }}</span>
                        </td>
                    </tr>
                    <tr>
                        <th>Submitted</th>
                        <td class="cell-secondary">{{ $submittedAt->format('M d, Y h:i A') }}</td>
                    </tr>
                </table>
            </div>
        </div>

        <div class="panel">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-chat-left-text"></i>
                        Reason for appeal
                    </h5>
                    <div class="panel-sub">The requester's explanation, in their own words.</div>
                </div>
            </div>
            <div class="panel-body">
                @if($appeal->RRQ_REASON)
                    <div class="appeal-quote">{{ $appeal->RRQ_REASON }}</div>
                @else
                    <p class="cell-faint mb-0">No reason was provided.</p>
                @endif
            </div>
        </div>

        @if($isListing)
            <div class="panel">
                <div class="panel-header">
                    <div>
                        <h5 class="panel-title">
                            <i class="bi bi-basket"></i>
                            Listing details
                        </h5>
                        <div class="panel-sub">The listing this appeal is about.</div>
                    </div>
                    @if($appeal->listing)
                        <a href="{{ route('listings') }}" class="btn btn-ghost btn-sm">
                            <i class="bi bi-box-arrow-up-right me-1"></i> Open listings
                        </a>
                    @endif
                </div>
                <div class="panel-body p-0">
                    <table class="detail-table">
                        <tr>
                            <th>Listing ID</th>
                            <td><span class="id-cell">{{ $appeal->listing?->LST_ID ?? $appeal->RRQ_TARGET_ID }}</span></td>
                        </tr>
                        <tr>
                            <th>Crop</th>
                            <td>{{ $appeal->listing?->LST_CROP_ICON ?: '-' }}</td>
                        </tr>
                        <tr>
                            <th>Category</th>
                            <td>{{ $appeal->listing?->category?->CAT_NAME ?? '-' }}</td>
                        </tr>
                        <tr>
                            <th>Farm</th>
                            <td>{{ $appeal->listing?->farm?->FRM_NAME ?? '-' }}</td>
                        </tr>
                        <tr>
                            <th>Listing status</th>
                            <td>
                                @php $listingStatus = $appeal->listing?->LST_STATUS; @endphp
                                @if($listingStatus === 'AVAILABLE_NOW')
                                    <span class="badge badge-soft-success">Available now</span>
                                @elseif($listingStatus === 'SOON_TO_HARVEST')
                                    <span class="badge badge-soft-warning">Soon to harvest</span>
                                @elseif($listingStatus)
                                    <span class="badge badge-soft-neutral">Not available</span>
                                @else
                                    -
                                @endif
                            </td>
                        </tr>
                        <tr>
                            <th>Availability</th>
                            <td>
                                @php $availability = $appeal->listing?->LST_AVAILABILITY; @endphp
                                @if($availability === 'ACTIVE')
                                    <span class="badge badge-soft-success">Active</span>
                                @elseif($availability === 'REMOVED')
                                    <span class="badge badge-soft-danger">Removed</span>
                                @elseif($availability)
                                    <span class="badge badge-soft-neutral">Not available</span>
                                @else
                                    -
                                @endif
                            </td>
                        </tr>
                        <tr>
                            <th>Takedown reason</th>
                            <td class="cell-secondary">{{ $appeal->listing?->LST_TAKEDOWN_REASON ?? '-' }}</td>
                        </tr>
                        @if($appeal->listing?->LST_IMAGE)
                            <tr>
                                <th>Photo</th>
                                <td>
                                    <img src="{{ $appeal->listing->LST_IMAGE }}"
                                         alt="Listing photo"
                                         class="appeal-thumb">
                                </td>
                            </tr>
                        @endif
                    </table>
                </div>
            </div>
        @else
            <div class="panel">
                <div class="panel-header">
                    <div>
                        <h5 class="panel-title">
                            <i class="bi bi-person-badge"></i>
                            Account details
                        </h5>
                        <div class="panel-sub">The account this appeal is about.</div>
                    </div>
                    @if($appeal->account)
                        <a href="{{ route('users.show', $appeal->RRQ_TARGET_ID) }}" class="btn btn-ghost btn-sm">
                            <i class="bi bi-box-arrow-up-right me-1"></i> Open account
                        </a>
                    @endif
                </div>
                <div class="panel-body p-0">
                    <table class="detail-table">
                        <tr>
                            <th>Account ID</th>
                            <td><span class="id-cell">{{ $appeal->RRQ_TARGET_ID }}</span></td>
                        </tr>
                        <tr>
                            <th>Name</th>
                            <td>{{ $appeal->account?->USR_NAME ?? '-' }}</td>
                        </tr>
                        <tr>
                            <th>Email</th>
                            <td>{{ $appeal->account?->USR_EMAIL ?? '-' }}</td>
                        </tr>
                        <tr>
                            <th>Mobile number</th>
                            <td>{{ $appeal->account?->USR_MOBILE_NUMBER ?? '-' }}</td>
                        </tr>
                        <tr>
                            <th>Account status</th>
                            <td>
                                @php $accountStatus = $appeal->account?->USR_STATUS; @endphp
                                @if($accountStatus === 'ACTIVE')
                                    <span class="badge badge-soft-success">Active</span>
                                @elseif($accountStatus === 'PENDING_VERIFICATION')
                                    <span class="badge badge-soft-warning">Pending verification</span>
                                @elseif($accountStatus === 'DEACTIVATED')
                                    <span class="badge badge-soft-danger">Deactivated</span>
                                @else
                                    -
                                @endif
                            </td>
                        </tr>
                        <tr>
                            <th>Takedown reason</th>
                            <td class="cell-secondary">{{ $appeal->account?->USR_TAKEDOWN_REASON ?? '-' }}</td>
                        </tr>
                        <tr>
                            <th>Registered</th>
                            <td class="cell-secondary">
                                @if($appeal->account?->USR_CREATED_AT)
                                    {{ \Carbon\Carbon::parse($appeal->account->USR_CREATED_AT)->timezone($displayTz)->format('M d, Y h:i A') }}
                                @else
                                    -
                                @endif
                            </td>
                        </tr>
                    </table>
                </div>
            </div>
        @endif

        @if(! $appeal->isPending())
            <div class="panel">
                <div class="panel-header">
                    <div>
                        <h5 class="panel-title">
                            <i class="bi bi-clipboard-check"></i>
                            Decision
                        </h5>
                        <div class="panel-sub">The outcome recorded for this appeal.</div>
                    </div>
                    <span class="badge {{ $statusClass }}">{{ $statusLabel }}</span>
                </div>
                <div class="panel-body p-0">
                    <table class="detail-table">
                        <tr>
                            <th>Outcome</th>
                            <td><span class="badge {{ $statusClass }}">{{ $statusLabel }}</span></td>
                        </tr>
                        <tr>
                            <th>Decided at</th>
                            <td class="cell-secondary">{{ $decidedAt?->format('M d, Y h:i A') ?? '-' }}</td>
                        </tr>
                        <tr>
                            <th>Decided by</th>
                            <td>{{ $appeal->decidedBy?->USR_NAME ?? 'an admin' }}</td>
                        </tr>
                        <tr>
                            <th>Admin note</th>
                            <td>
                                @if($appeal->RRQ_ADMIN_NOTE)
                                    <div class="appeal-quote is-note">{{ $appeal->RRQ_ADMIN_NOTE }}</div>
                                @else
                                    <span class="cell-faint">No note was recorded.</span>
                                @endif
                            </td>
                        </tr>
                    </table>
                </div>
            </div>
        @endif

    </div>

    <div class="col-lg-4">

        <div class="panel">
            <div class="panel-header">
                <h5 class="panel-title">
                    <i class="bi bi-activity"></i>
                    Progress
                </h5>
            </div>
            <div class="panel-body">
                <div class="appeal-steps">
                    <div class="appeal-step is-done">
                        <span class="appeal-step-dot"><i class="bi bi-check-lg"></i></span>
                        <div>
                            <div class="appeal-step-title">Appeal submitted</div>
                            <div class="appeal-step-meta">{{ $submittedAt->format('M d, Y h:i A') }}</div>
                        </div>
                    </div>
                    <div class="appeal-step {{ $appeal->isPending() ? 'is-current' : 'is-done' }}">
                        <span class="appeal-step-dot">
                            <i class="bi {{ $appeal->isPending() ? 'bi-hourglass-split' : 'bi-check-lg' }}"></i>
                        </span>
                        <div>
                            <div class="appeal-step-title">{{ $appeal->isPending() ? 'Under review' : 'Decision made' }}</div>
                            <div class="appeal-step-meta">
                                {{ $appeal->isPending() ? 'Waiting for a moderator.' : ($decidedAt?->format('M d, Y h:i A') ?? '-') }}
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        @if($appeal->isPending())
            <div class="panel">
                <div class="panel-header">
                    <h5 class="panel-title">
                        <i class="bi bi-info-circle"></i>
                        Before you decide
                    </h5>
                </div>
                <div class="panel-body">
                    <p class="cell-secondary mb-2">
                        <strong>Approve</strong> restores the target and dismisses the reports filed against it.
                    </p>
                    <p class="cell-secondary mb-2">
                        <strong>Deny</strong> keeps the takedown in place and resolves those reports.
                    </p>
                    <p class="cell-faint mb-0">
                        A denied appeal is final until the target is taken down again.
                    </p>
                </div>
            </div>
        @endif

    </div>

</div>

@if($appeal->isPending())
    <div class="panel">
        <div class="panel-header">
            <div>
                <h5 class="panel-title">
                    <i class="bi bi-check2-square"></i>
                    Decide appeal
                </h5>
                <div class="panel-sub">Choose one outcome. The requester is notified either way.</div>
            </div>
        </div>
        <div class="panel-body">
            <div class="decision-grid">

                <form method="POST"
                      action="{{ route('appeals.approve', $appeal->RRQ_ID) }}"
                      data-auto-spinner
                      data-confirm-title="Approve appeal?"
                      data-confirm-text="The target is restored and the reports against it are dismissed.">
                    @csrf
                    <label class="form-label" for="note-approve">Admin note (optional)</label>
                    <textarea id="note-approve"
                              name="note"
                              rows="2"
                              maxlength="500"
                              class="form-control mb-2"
                              placeholder="Shown to the requester or kept for the audit trail">{{ old('note') }}</textarea>
                    <button type="submit" class="btn btn-farm">
                        <i class="bi bi-check-lg me-1"></i> Approve &amp; restore
                    </button>
                </form>

                <form method="POST"
                      action="{{ route('appeals.deny', $appeal->RRQ_ID) }}"
                      data-auto-spinner
                      data-confirm-title="Deny appeal?"
                      data-confirm-text="This keeps the takedown in place. The decision is final until a new takedown occurs."
                      data-confirm-tone="danger">
                    @csrf
                    <label class="form-label" for="note-deny">Admin note (optional)</label>
                    <textarea id="note-deny"
                              name="note"
                              rows="2"
                              maxlength="500"
                              class="form-control mb-2"
                              placeholder="Reason to keep the decision in place">{{ old('note') }}</textarea>
                    <button type="submit" class="btn btn-danger">
                        <i class="bi bi-x-lg me-1"></i> Deny appeal
                    </button>
                </form>

            </div>
        </div>
    </div>
@endif

@endsection
