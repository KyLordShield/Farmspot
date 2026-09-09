@extends('layouts.app')

@section('title', 'Whitelist Details')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Whitelist Details</h1>
        <div class="page-desc">{{ $whitelist->WLST_ID }} · {{ $whitelist->WLST_MOBILE_NUMBER }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('whitelist') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Whitelist
        </a>
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-check-circle"></i>
            {{ $whitelist->WLST_ID }}
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">

            <tr>
                <th>Mobile Number</th>
                <td>{{ $whitelist->WLST_MOBILE_NUMBER }}</td>
            </tr>

            <tr>
                <th>Status</th>
                <td>
                    @if($whitelist->WLST_IS_ACTIVE)
                        <span class="badge badge-soft-success">Active</span>
                    @else
                        <span class="badge badge-soft-neutral">Inactive</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Added At</th>
                <td class="cell-secondary">{{ $whitelist->WLST_ADDED_AT }}</td>
            </tr>

            <tr>
                <th>Added By</th>
                <td>{{ $whitelist->addedBy?->USR_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Deactivated By</th>
                <td>{{ $whitelist->deactivatedBy?->USR_NAME ?? '—' }}</td>
            </tr>

        </table>
    </div>
    <div class="panel-body">
        <div class="detail-actions">
            @if($whitelist->WLST_IS_ACTIVE)
                <form method="POST" action="{{ route('whitelist.toggle', $whitelist->WLST_ID) }}"
                      class="d-inline"
                      onsubmit="return confirm('Are you sure you want to deactivate this number?');">
                    @csrf
                    @method('PATCH')
                    <button type="submit" class="btn btn-danger">
                        <i class="bi bi-slash-circle me-1"></i> Deactivate
                    </button>
                </form>
            @else
                <form method="POST" action="{{ route('whitelist.toggle', $whitelist->WLST_ID) }}"
                      class="d-inline">
                    @csrf
                    @method('PATCH')
                    <button type="submit" class="btn btn-farm">
                        <i class="bi bi-check-circle me-1"></i> Reactivate
                    </button>
                </form>
            @endif
        </div>
    </div>
</div>

@endsection