@extends('layouts.app')

@section('title', 'Report Details')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Report Details</h1>
        <div class="page-desc">Report #{{ $report->RPT_ID }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('reports') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Reports
        </a>
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-flag"></i>
            Report #{{ $report->RPT_ID }}
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">

            @php
                $typeLabels = [
                    'LISTING' => 'Crop listing',
                    'MESSAGE' => 'Chat message',
                    'FARMER' => 'Farmer / seller',
                    'USER' => 'User account',
                ];
            @endphp

            <tr>
                <th>What was reported</th>
                <td>
                    <span class="badge badge-soft-neutral">{{ $typeLabels[$report->RPT_TARGET_TYPE] ?? $report->RPT_TARGET_TYPE }}</span>
                    @if($report->RPT_TARGET_ID)
                        <span class="id-cell ms-2">{{ $report->RPT_TARGET_ID }}</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Reason</th>
                <td>{{ $report->reasonLabel() }}</td>
            </tr>

            <tr>
                <th>Status</th>
                <td>
                    @if($report->RPT_STATUS == 'New')
                        <span class="badge badge-soft-danger">New</span>
                    @elseif($report->RPT_STATUS == 'Reviewing')
                        <span class="badge badge-soft-warning">Reviewing</span>
                    @elseif($report->RPT_STATUS == 'Resolved')
                        <span class="badge badge-soft-success">Resolved</span>
                    @else
                        <span class="badge badge-soft-neutral">Dismissed</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Submitted</th>
                <td class="cell-secondary">{{ \Carbon\Carbon::parse($report->RPT_CREATED_AT)->format('M d, Y h:i A') }}</td>
            </tr>

            <tr>
                <th>Reporter</th>
                <td>{{ $report->user?->USR_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Reporter Email</th>
                <td>{{ $report->user?->USR_EMAIL ?? '-' }}</td>
            </tr>

            <tr>
                <th>Reporter ID</th>
                <td><span class="id-cell">{{ $report->USR_ID }}</span></td>
            </tr>

            {{-- The reporter's own words, when they wrote any. --}}
            @if($report->RPT_DETAILS)
                <tr>
                    <th>Reporter's description</th>
                    <td class="cell-secondary" style="white-space: pre-wrap;">{{ $report->RPT_DETAILS }}</td>
                </tr>
            @endif

        </table>
    </div>
</div>

{{-- One block per kind of subject. A moderator needs to see the thing that
     was reported before deciding anything, and a message or a person has none
     of the crop/farm fields the old view assumed. --}}
@if($report->RPT_TARGET_TYPE == 'LISTING')
    <div class="panel">
        <div class="panel-header">
            <h5 class="panel-title">
                <i class="bi bi-basket"></i>
                Reported Crop Listing
            </h5>
        </div>
        <div class="panel-body p-0">
            <table class="detail-table">
                <tr>
                    <th>Listing ID</th>
                    <td><span class="id-cell">{{ $report->listing?->LST_ID ?? 'Deleted since' }}</span></td>
                </tr>
                <tr>
                    <th>Categories</th>
                    <td>{{ $report->listing?->category?->CAT_NAME ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Crop Name</th>
                    <td>{{ $report->listing?->LST_CROP_ICON ?: '-' }}</td>
                </tr>
                <tr>
                    <th>Status</th>
                    <td>
                        @php($reportedListingStatus = $report->listing?->LST_STATUS ?? null)
                        @if($reportedListingStatus === 'AVAILABLE_NOW')
                            <span class="badge badge-soft-success">Available Now</span>
                        @elseif($reportedListingStatus === 'SOON_TO_HARVEST')
                            <span class="badge badge-soft-warning">Soon to Harvest</span>
                        @elseif($reportedListingStatus)
                            <span class="badge badge-soft-neutral">Not Available</span>
                        @else
                            -
                        @endif
                    </td>
                </tr>
                <tr>
                    <th>Farm</th>
                    <td>{{ $report->listing?->farm?->FRM_NAME ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Seller</th>
                    <td>{{ $report->listing?->farmer?->buyer?->user?->USR_NAME ?? '-' }}</td>
                </tr>
            </table>
        </div>
    </div>
@elseif($report->RPT_TARGET_TYPE == 'MESSAGE')
    <div class="panel">
        <div class="panel-header">
            <h5 class="panel-title">
                <i class="bi bi-chat-quote"></i>
                Reported Message
            </h5>
        </div>
        <div class="panel-body p-0">
            <table class="detail-table">
                <tr>
                    <th>Message ID</th>
                    <td><span class="id-cell">{{ $report->RPT_TARGET_ID }}</span></td>
                </tr>
                <tr>
                    <th>Sent by</th>
                    <td>
                        {{ $report->message?->sender?->USR_NAME ?? 'Unknown' }}
                        <span class="id-cell ms-2">{{ $report->message?->USR_ID ?? '' }}</span>
                    </td>
                </tr>
                <tr>
                    <th>Sent</th>
                    <td class="cell-secondary">{{ $report->message ? \Carbon\Carbon::parse($report->message->MSG_CREATED_AT)->format('M d, Y h:i A') : '-' }}</td>
                </tr>
                <tr>
                    <th>Message</th>
                    {{-- Escaped by {{ }}. A reported message is attacker-chosen
                         text, so it must never be rendered as markup. --}}
                    <td style="white-space: pre-wrap;">{{ $report->message?->MSG_CONTENT ?? 'Message deleted' }}</td>
                </tr>
                {{-- Kept as context: was this a live sale or an approach about
                     something the buyer had already dismissed? --}}
                <tr>
                    <th>About listing</th>
                    <td>
                        @if($report->listing)
                            <span class="id-cell">{{ $report->listing->LST_ID }}</span>
                            {{ $report->listing->farm?->FRM_NAME ?? '' }}
                        @else
                            -
                        @endif
                    </td>
                </tr>
            </table>
        </div>
    </div>
@else
    {{-- FARMER and USER both name a person. --}}
    @php
        $accused = $report->RPT_TARGET_TYPE == 'FARMER'
            ? $report->farmer?->buyer?->user
            : $report->reportedUser;
    @endphp
    <div class="panel">
        <div class="panel-header">
            <h5 class="panel-title">
                <i class="bi bi-person-badge"></i>
                Reported {{ $report->RPT_TARGET_TYPE == 'FARMER' ? 'Farmer' : 'User' }}
            </h5>
        </div>
        <div class="panel-body p-0">
            <table class="detail-table">
                <tr>
                    <th>Name</th>
                    <td>{{ $accused?->USR_NAME ?? 'Unknown' }}</td>
                </tr>
                <tr>
                    <th>Email</th>
                    <td>{{ $accused?->USR_EMAIL ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Mobile</th>
                    <td>{{ $accused?->USR_MOBILE_NUMBER ?? '-' }}</td>
                </tr>
                <tr>
                    <th>User ID</th>
                    <td><span class="id-cell">{{ $report->RPT_TARGET_ID }}</span></td>
                </tr>
                @if($report->RPT_TARGET_TYPE == 'FARMER')
                    <tr>
                        <th>Farmer ID</th>
                        <td><span class="id-cell">{{ $report->RPT_TARGET_ID }}</span></td>
                    </tr>
                    <tr>
                        <th>Account status</th>
                        <td>
                            @php($accusedStatus = $accused?->USR_STATUS ?? null)
                            @if($accusedStatus === 'ACTIVE')
                                <span class="badge badge-soft-success">Active</span>
                            @elseif($accusedStatus === 'PENDING_VERIFICATION')
                                <span class="badge badge-soft-warning">Pending Verification</span>
                            @elseif($accusedStatus)
                                <span class="badge badge-soft-neutral">Deactivated</span>
                            @else
                                -
                            @endif
                        </td>
                    </tr>
                    <tr>
                        <th>Selling mode</th>
                        <td>{{ (int) ($report->farmer?->FMR_SELLER_MODE_ACTIVE ?? 0) === 1 ? 'Active' : 'Inactive' }}</td>
                    </tr>
                @endif
            </table>
        </div>
    </div>
@endif

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-shield-exclamation"></i>
            Take Action
        </h5>
    </div>
    <div class="panel-body">
        {{-- Everything already in force on this report. Each is a separate
             decision with its own undo, so they are listed rather than collapsed
             into one current state. --}}
        @if($report->actions->isNotEmpty())
            <table class="detail-table mb-3">
                <thead>
                    <tr>
                        <th>Action</th>
                        <th>Applied</th>
                        <th>State</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($report->actions as $action)
                        <tr>
                            <td>
                                {{ $actionLabels[$action->RAC_ACTION] ?? $action->RAC_ACTION }}
                                @if($action->RAC_NOTE)
                                    <div class="cell-secondary" style="white-space: pre-wrap;">{{ $action->RAC_NOTE }}</div>
                                @endif
                            </td>
                            <td class="cell-secondary">
                                {{ \Carbon\Carbon::parse($action->RAC_APPLIED_AT)->format('M d, Y h:i A') }}
                                <div class="cell-faint">by {{ $action->moderator?->USR_NAME ?? 'an admin' }}</div>
                            </td>
                            <td>
                                @if($action->isLive())
                                    <span class="badge badge-soft-danger">In force</span>
                                @else
                                    <span class="badge badge-soft-neutral">
                                        Undone {{ \Carbon\Carbon::parse($action->RAC_REVERTED_AT)->format('M d') }}
                                        by {{ $action->revertedBy?->USR_NAME ?? 'an admin' }}
                                    </span>
                                @endif
                            </td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        @endif

        @if($report->actions->isNotEmpty())
            {{-- Undo pops the newest action still in force, so undoing twice in
                 a row walks back through a multi-step decision. It sits
                 alongside the remaining options rather than replacing them: a
                 moderator who has taken a listing down may still want to
                 deactivate the seller who posted it. --}}
            <form method="POST" action="{{ route('reports.undoAction', $report->RPT_ID) }}"
                  data-confirm-title="Undo most recent action?"
                  data-confirm-text="Put the most recent action back exactly as it was?"
                  class="mb-3">
                @csrf
                <button type="submit" class="btn btn-ghost">
                    <i class="bi bi-arrow-counterclockwise me-1"></i> Undo the most recent action
                </button>
            </form>
        @endif

        @if(count($options))
            <p class="text-muted">
                You are looking at report #{{ $report->RPT_ID }} about
                <strong>{{ $typeLabels[$report->RPT_TARGET_TYPE] ?? $report->RPT_TARGET_TYPE }}
                    <span class="id-cell">{{ $report->RPT_TARGET_ID }}</span></strong>.
                Decide for yourself before acting — a report is a lead, not a verdict, and nothing here
                happens automatically.
            </p>

            {{-- One button per available step. They are independent: taking a
                 listing down does not stop a moderator also deactivating the
                 seller who posted it, and undoing one leaves the other alone. --}}
            @foreach($options as $option)
                <form method="POST" action="{{ route('reports.applyAction', [$report->RPT_ID, $option['action']]) }}"
                      data-confirm-title="{{ $option['button'] }}?"
                      data-confirm-text="This takes effect immediately and is recorded in the audit trail."
                      data-confirm-tone="danger"
                      class="mb-3">
                    @csrf
                    <div class="row g-3 align-items-end">
                        <div class="col-md-6">
                            <label class="form-label" for="note-{{ $option['action'] }}">
                                {{ $option['button'] }}
                                <span class="text-muted fw-normal">— affects {{ $option['subject'] }}</span>
                            </label>
                            <input type="text" class="form-control" id="note-{{ $option['action'] }}" name="note" maxlength="500"
                                   placeholder="Note for the audit trail (optional)">
                        </div>
                        <div class="col-auto">
                            <button type="submit" class="btn btn-farm">
                                <i class="bi bi-shield-fill-exclamation me-1"></i> {{ $option['button'] }}
                            </button>
                        </div>
                    </div>
                </form>
            @endforeach
        @elseif($report->actions->contains(fn ($a) => $a->isLive()))
            <p class="text-muted mb-0">
                <i class="bi bi-check-circle me-1"></i>Everything this report could act on has been acted on.
            </p>
        @else
            {{-- No button, but say why. A missing button with no explanation is
                 how a moderator ends up thinking the queue cannot act at all. --}}
            <p class="text-muted mb-0">
                <i class="bi bi-info-circle me-1"></i>{{ $blocked[0] ?? 'Nothing can be done about this report.' }}
            </p>
        @endif
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-pencil-square"></i>
            Update Status
        </h5>
    </div>
    <div class="panel-body">
        <form method="POST" action="{{ route('reports.updateStatus', $report->RPT_ID) }}" class="row g-3 align-items-end" data-auto-spinner>
            @csrf
            @method('PATCH')

            <div class="col-md-4">
                <label for="status" class="form-label">Status</label>
                <select class="form-select" id="status" name="status" required>
                    <option value="New" {{ old('status', $report->RPT_STATUS) == 'New' ? 'selected' : '' }}>New</option>
                    <option value="Reviewing" {{ old('status', $report->RPT_STATUS) == 'Reviewing' ? 'selected' : '' }}>Reviewing</option>
                    <option value="Resolved" {{ old('status', $report->RPT_STATUS) == 'Resolved' ? 'selected' : '' }}>Resolved</option>
                    <option value="Dismissed" {{ old('status', $report->RPT_STATUS) == 'Dismissed' ? 'selected' : '' }}>Dismissed</option>
                </select>
            </div>

            <div class="col-auto">
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-lg me-1"></i> Update Status
                </button>
            </div>
        </form>
    </div>
</div>

@endsection