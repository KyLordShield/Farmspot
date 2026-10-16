@extends('layouts.app')

@section('title', 'Mass Report — '.$subject['name'])

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Mass Report Alert</h1>
        <div class="page-desc">Who reported this, and why</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('reports.flagged') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Alerts
        </a>
    </div>
</div>

@if(session('error'))
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        {{ session('error') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

{{-- The subject of the wave, named first. A moderator deciding whether the
     volume is real needs to know what is being piled on before reading who. --}}
<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-{{ $subject['icon'] }}"></i>
            Reported {{ $type === 'LISTING' ? 'Crop Listing' : ($type === 'MESSAGE' ? 'Message' : ($type === 'FARMER' ? 'Farmer / Seller' : 'User Account')) }}
        </h5>
    </div>
    <div class="panel-body">
        <div class="d-flex align-items-start justify-content-between flex-wrap gap-3">
            <div>
                <h5 class="mb-1">
                    @if($subject['url'])
                        <a href="{{ $subject['url'] }}" class="text-decoration-none">
                            {{ $subject['name'] }}
                            <i class="bi bi-box-arrow-up-right small"></i>
                        </a>
                    @else
                        {{ $subject['name'] }}
                    @endif
                </h5>
                <div class="cell-secondary">{{ $subject['subtitle'] }}</div>
                <div class="id-cell mt-2">{{ $id }}</div>
            </div>
            <div class="d-flex align-items-center gap-3 flex-wrap">
                <div class="text-center">
                    <div class="stat-value" style="color: var(--bs-danger, #b02a37);">{{ $byReporter->count() }}</div>
                    <div class="stat-label">Distinct reporters</div>
                </div>
                <div class="text-center">
                    <div class="stat-value">{{ $reports->count() }}</div>
                    <div class="stat-label">Open reports</div>
                </div>
                <div class="text-center">
                    <div class="stat-value">{{ $threshold }}</div>
                    <div class="stat-label">Threshold</div>
                </div>
            </div>
        </div>
    </div>
</div>

{{-- One row per person. The threshold counts distinct reporters, so the list a
     moderator reads has to count them the same way: a person who filed twice is
     one voice here, with both of their reasons, not two rows. --}}
<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-people"></i>
            Reporters &amp; Reasons
        </h5>
    </div>
    <div class="table-responsive">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Reporter</th>
                    <th>Reason(s)</th>
                    <th>Reports</th>
                    <th>Latest</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
            @foreach($byReporter as $item)
                <tr>
                    <td>
                        <div class="fw-semibold">{{ $item['reporter']?->USR_NAME ?? 'Unknown user' }}</div>
                        <div class="cell-secondary">{{ $item['reporter']?->USR_EMAIL ?? '-' }}</div>
                    </td>
                    <td>
                        @foreach($item['reasons'] as $reason)
                            <span class="badge badge-soft-danger mb-1">{{ $reason }}</span>
                        @endforeach
                        {{-- The reporter's own words, when they wrote any. A label
                             alone ("Fraud or scam") is a category; the sentence is
                             the actual complaint. --}}
                        @foreach($item['reports'] as $r)
                            @if($r->RPT_DETAILS)
                                <div class="cell-secondary" style="white-space: pre-wrap;">{{ $r->RPT_DETAILS }}</div>
                            @endif
                        @endforeach
                    </td>
                    <td>
                        @foreach($item['reports'] as $r)
                            <a href="{{ route('reports.show', $r->RPT_ID) }}" class="id-cell d-block">
                                {{ $r->RPT_ID }}
                            </a>
                        @endforeach
                    </td>
                    <td class="cell-faint">
                        {{ \Carbon\Carbon::parse($item['latest_at'])->format('M d, Y h:i A') }}
                    </td>
                    <td>
                        <a href="{{ route('reports.show', $item['reports']->last()->RPT_ID) }}"
                           class="btn btn-sm btn-ghost" title="Open this report to take action">
                            <i class="bi bi-box-arrow-up-right me-1"></i> Act
                        </a>
                    </td>
                </tr>
            @endforeach
            </tbody>
        </table>
    </div>
    <div class="panel-body pt-0">
        <p class="text-muted mb-0">
            <i class="bi bi-info-circle me-1"></i>
            Each report is openable on its own if you want to judge just one. To answer the whole
            wave in a single decision, use the target panel below.
        </p>
    </div>
</div>

{{-- The one decision that answers the whole wave. It is the same enforcement
     step offered on a single report, but chosen here so a moderator who has read
     the reporters does not have to open one report at random to hang it on. The
     step is recorded against the newest open report and closes every open report
     for the target. --}}
<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-shield-exclamation"></i>
            Take Action on This Target
        </h5>
    </div>
    <div class="panel-body">
        @if(count($options))
            <p class="text-muted">
                Acting on <strong>{{ $subject['name'] }}</strong> here applies one decision and
                resolves all <strong>{{ $reports->count() }}</strong> open
                report{{ $reports->count() == 1 ? '' : 's' }} on this target — you do not have to
                open each one. A report is a lead, not a verdict; decide for yourself first.
            </p>

            @foreach($options as $option)
                <form method="POST"
                      action="{{ route('reports.flaggedTarget.action', [$type, $id, $option['action']]) }}"
                      data-confirm-title="{{ $option['button'] }}?"
                      data-confirm-text="This acts on the target and resolves all {{ $reports->count() }} open report(s) behind it. It is recorded in the audit trail."
                      data-confirm-tone="danger"
                      class="mb-3">
                    @csrf
                    <div class="row g-3 align-items-end">
                        <div class="col-md-6">
                            <label class="form-label" for="target-note-{{ $option['action'] }}">
                                {{ $option['button'] }}
                                <span class="text-muted fw-normal">— affects {{ $option['subject'] }}</span>
                            </label>
                            <input type="text" class="form-control" id="target-note-{{ $option['action'] }}"
                                   name="note" maxlength="500"
                                   placeholder="{{ $option['requires_reason'] ? 'Reason shown to the owner (required)' : 'Note for the audit trail (optional)' }}"
                                   {{ $option['requires_reason'] ? 'required' : '' }}>
                            @if($option['requires_reason'])
                                <div class="form-text">
                                    Shown to the owner as the reason for this action, and resolves every
                                    open report on this target.
                                </div>
                            @endif
                        </div>
                        <div class="col-auto">
                            <button type="submit" class="btn btn-farm">
                                <i class="bi bi-shield-fill-exclamation me-1"></i> {{ $option['button'] }}
                            </button>
                        </div>
                    </div>
                </form>
            @endforeach
        @else
            {{-- No button, but say why. Hiding the panel entirely would read as
                 "this target cannot be actioned from here". --}}
            <p class="text-muted mb-0">
                <i class="bi bi-check-circle me-1"></i>Everything this target could act on has been
                acted on. Open a report to undo or change it.
            </p>
        @endif
    </div>
</div>

@endsection
