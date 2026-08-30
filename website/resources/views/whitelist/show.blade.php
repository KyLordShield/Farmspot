@extends('layouts.app')

@section('title', 'Whitelist Details')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">
    <div>
        <h2 class="fw-bold mb-0">Whitelist Details</h2>
        <small class="text-muted">{{ $whitelist->WLST_ID }}</small>
    </div>
    <a href="{{ route('whitelist') }}" class="btn btn-outline-secondary">
        <i class="bi bi-arrow-left"></i> Back to Whitelist
    </a>
</div>

<div class="card shadow-sm border-0 rounded-4">
    <div class="card-header bg-success text-white">
        <h4 class="mb-0"><i class="bi bi-check-circle-fill"></i> {{ $whitelist->WLST_ID }}</h4>
    </div>
    <div class="card-body">
        <table class="table">

            <tr>
                <th>Mobile Number</th>
                <td>{{ $whitelist->WLST_MOBILE_NUMBER }}</td>
            </tr>

            <tr>
                <th>Status</th>
                <td>
                    @if($whitelist->WLST_IS_ACTIVE)
                        <span class="badge bg-success">Active</span>
                    @else
                        <span class="badge bg-danger">Inactive</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Added At</th>
                <td>{{ $whitelist->WLST_ADDED_AT }}</td>
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

        @if($whitelist->WLST_IS_ACTIVE)
            <form method="POST" action="{{ route('whitelist.toggle', $whitelist->WLST_ID) }}"
                  class="d-inline"
                  onsubmit="return confirm('Are you sure you want to deactivate this number?');">
                @csrf
                @method('PATCH')
                <button type="submit" class="btn btn-danger">
                    <i class="bi bi-slash-circle"></i> Deactivate
                </button>
            </form>
        @else
            <form method="POST" action="{{ route('whitelist.toggle', $whitelist->WLST_ID) }}"
                  class="d-inline">
                @csrf
                @method('PATCH')
                <button type="submit" class="btn btn-success">
                    <i class="bi bi-check-circle"></i> Reactivate
                </button>
            </form>
        @endif
    </div>
</div>

@endsection