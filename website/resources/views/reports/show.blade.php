@extends('layouts.app')
@section('title', 'Report Details')
@include('reports._assets')

@section('content')
@php
    $submitted = $report->RPT_CREATED_AT ? \Carbon\Carbon::parse($report->RPT_CREATED_AT) : null;
    $type = ['LISTING' => 'Crop listing', 'MESSAGE' => 'Chat message', 'FARMER' => 'Farmer / seller', 'USER' => 'User account'][$report->RPT_TARGET_TYPE] ?? $report->RPT_TARGET_TYPE;
@endphp
<div class="listing-details mod-page">
    <header class="ld-header">
        <div>
            <nav class="ld-breadcrumb" aria-label="Breadcrumb">
                <a href="{{ route('reports') }}">Reports</a><span aria-hidden="true">/</span>
                <span aria-current="page">#{{ $report->RPT_ID }}</span>
            </nav>
            <div class="ld-title">
                <h1>Report #{{ $report->RPT_ID }}</h1>
                @include('reports._status', ['status' => $report->RPT_STATUS])
                @include('reports._id', ['id' => $report->RPT_ID])
            </div>
            <div class="ld-muted">Submitted @include('reports._date', ['value' => $submitted])</div>
        </div>
        <a href="{{ route('reports') }}" class="ld-button"><i class="bi bi-arrow-left" aria-hidden="true"></i> Back to Reports</a>
    </header>
    @include('reports._feedback')

    @if($report->RPT_FLAGGED_AT && in_array($report->RPT_STATUS, ['New', 'Reviewing'], true))
        <div class="mod-alert">
            <i class="bi bi-exclamation-triangle-fill" aria-hidden="true"></i>
            <span><strong>Mass-report alert.</strong> This target reached the reporting threshold.</span>
            <a href="{{ route('reports.flaggedTarget', [$report->RPT_TARGET_TYPE, $report->RPT_TARGET_ID]) }}">
                See all {{ $reporterCount }} {{ Str::plural('reporter', $reporterCount) }}
            </a>
        </div>
    @endif

    <div class="mod-detail-grid">
        <div class="ld-main">
            <section class="ld-card">
                <h2>Report</h2>
                <dl class="ld-fields">
                    <div><dt>What was reported</dt><dd><span class="mod-type">{{ $type }}</span> @include('reports._id', ['id' => $report->RPT_TARGET_ID])</dd></div>
                    <div><dt>Reason</dt><dd>{{ $report->reasonLabel() }}</dd></div>
                    <div><dt>Status</dt><dd>@include('reports._status', ['status' => $report->RPT_STATUS])</dd></div>
                    <div><dt>Submitted</dt><dd>@include('reports._date', ['value' => $submitted])</dd></div>
                </dl>
            </section>
            <section class="ld-card">
                <h2>Reporter’s description</h2>
                @if(filled($report->RPT_DETAILS))
                    <blockquote class="mod-quote">{{ $report->RPT_DETAILS }}</blockquote>
                @else
                    <em class="ld-muted">Not provided</em>
                @endif
            </section>
            <section class="ld-card">
                <h2>Reporter</h2>
                <dl class="ld-fields">
                    <div><dt>Name</dt><dd>{{ $report->user?->USR_NAME ?? 'Not provided' }}</dd></div>
                    <div><dt>Email</dt><dd>{{ $report->user?->USR_EMAIL ?? 'Not provided' }}</dd></div>
                    <div><dt>Reporter ID</dt><dd>@include('reports._id', ['id' => $report->USR_ID])</dd></div>
                </dl>
                @if($report->USR_ID)
                    <a class="mod-link mt-3 d-inline-block" href="{{ route('reports', ['reporter' => $report->USR_ID, 'except' => $report->RPT_ID]) }}">View other reports by this reporter</a>
                @endif
            </section>
            @include('reports._evidence')
            @include('reports._activity')
        </div>
        <aside class="mod-action-stack" aria-label="Moderation actions">
            <section class="ld-card">
                <h2>Update status</h2>
                @include('reports._status-form')
            </section>
            <section class="ld-card">
                <h2>Take action</h2>
                <p class="mod-info"><i class="bi bi-info-circle" aria-hidden="true"></i> A report is a lead, not a verdict. Review the evidence before acting.</p>
                @forelse($options as $option)
                    @php
                        $accountAction = in_array($option['action'], ['ACCOUNT_DEACTIVATED', 'FARMER_ACCOUNT_DEACTIVATED', 'SELLER_DEACTIVATED'], true);
                        $confirmation = $accountAction ? 'Deactivate '.$option['subject'].'?' : $option['button'].'?';
                        $consequence = match ($option['action']) {
                            'ACCOUNT_DEACTIVATED', 'FARMER_ACCOUNT_DEACTIVATED', 'SELLER_DEACTIVATED' => 'The account will be signed out and lose access to FarmSpot.',
                            'LISTING_TAKEN_DOWN' => 'The listing will be removed from the marketplace.',
                            'FARMER_LISTINGS_TAKEN_DOWN' => 'The seller’s listings will be removed from the marketplace.',
                            'MESSAGE_HIDDEN' => 'The reported message will be hidden.',
                            default => 'The action takes effect immediately.',
                        };
                    @endphp
                    <form method="POST" action="{{ route('reports.applyAction', [$report->RPT_ID, $option['action']]) }}"
                          class="mod-form mod-enforcement" data-mod-enforce>
                        @csrf
                        <h3>{{ $option['button'] }}</h3>
                        <p class="ld-muted mb-0">Affects {{ $option['subject'] }}</p>
                        <label for="note-{{ $option['action'] }}" class="mod-label">{{ $option['requires_reason'] ? 'Reason' : 'Audit note (optional)' }}</label>
                        <textarea id="note-{{ $option['action'] }}" class="form-control" name="note" rows="3" maxlength="500"
                                  aria-describedby="hint-{{ $option['action'] }}" @required($option['requires_reason'])></textarea>
                        <div class="ld-muted" id="hint-{{ $option['action'] }}">{{ $option['requires_reason'] ? 'Shown to the owner' : 'Saved in the audit trail' }}</div>
                        <button type="submit" class="ld-button mod-danger" data-mod-review disabled>
                            <i class="bi bi-shield-exclamation" aria-hidden="true"></i> {{ $option['button'] }}
                        </button>
                        <dialog class="mod-dialog" aria-labelledby="confirm-title-{{ $option['action'] }}">
                            <h2 id="confirm-title-{{ $option['action'] }}">{{ $confirmation }}</h2>
                            <p>{{ $consequence }} This decision is recorded in the audit trail.</p>
                            <div data-mod-note-preview hidden>
                                <span class="mod-label">{{ $option['requires_reason'] ? 'Reason' : 'Audit note' }}</span>
                                <p class="mod-quote" data-mod-note-text></p>
                            </div>
                            <div class="mod-row-actions">
                                <button type="button" class="ld-button" data-mod-close autofocus>Cancel</button>
                                <button type="button" class="ld-button mod-danger mod-danger-solid" data-mod-confirm>Confirm</button>
                            </div>
                        </dialog>
                    </form>
                @empty
                    <p class="ld-muted">{{ $report->actions->contains(fn ($action) => $action->isLive())
                        ? 'All available actions have been applied.' : ($blocked[0] ?? 'No moderation actions are available.') }}</p>
                @endforelse
                @if($report->actions->isNotEmpty())
                    <form method="POST" action="{{ route('reports.undoAction', $report->RPT_ID) }}"
                          data-confirm-title="Undo most recent action?"
                          data-confirm-text="Put the most recent action back exactly as it was?" class="mod-enforcement">
                        @csrf
                        <button type="submit" class="ld-button"><i class="bi bi-arrow-counterclockwise" aria-hidden="true"></i> Undo the most recent action</button>
                    </form>
                @endif
            </section>
        </aside>
    </div>
</div>
@endsection
