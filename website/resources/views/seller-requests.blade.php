@extends('layouts.app')

@section('title','Seller Requests')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Seller Requests</h1>
        <div class="page-desc">Review pending farm submissions</div>
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

<div class="stat-grid">

    <div class="stat-card">
        <div class="stat-icon tint-amber">
            <i class="bi bi-hourglass-split"></i>
        </div>
        <div>
            <div class="stat-value">{{ $sellerRequests->total() }}</div>
            <div class="stat-label">Pending requests</div>
        </div>
    </div>

</div>

<div class="panel">

    <form method="GET" action="{{ route('seller-requests') }}" class="filter-bar">

        <div class="filter-grow">
            <div class="input-group">
                <span class="input-group-text">
                    <i class="bi bi-search"></i>
                </span>
                <input
                    type="text"
                    name="search"
                    value="{{ request('search') }}"
                    class="form-control"
                    placeholder="Search farm or owner name">
                <button class="btn btn-farm" type="submit">
                    Search
                </button>
            </div>
        </div>

    </form>

    <div class="table-responsive">
        <table class="data-table">

            <thead>
                <tr>
                    <th>Farm Name</th>
                    <th>Owner Name</th>
                    <th>Mobile Number</th>
                    <th>Barangay</th>
                    <th>Submitted At</th>
                    <th>Actions</th>
                </tr>
            </thead>

            <tbody>

            @forelse($sellerRequests as $farm)

                <tr>
                    <td>{{ $farm->FRM_NAME }}</td>
                    <td class="cell-secondary">{{ $farm->farmer?->buyer?->user?->USR_NAME ?? '-' }}</td>
                    <td>{{ $farm->farmer?->buyer?->user?->USR_MOBILE_NUMBER ?? '-' }}</td>
                    <td class="cell-secondary">{{ $farm->FRM_BARANGAY }}</td>
                    <td class="cell-faint">{{ \Carbon\Carbon::parse($farm->FRM_CREATED_AT)->format('M d, Y h:i A') }}</td>
                    <td>
                        <div class="actions">
                            <a href="{{ route('seller-requests.show', $farm->FRM_ID) }}"
                               class="btn-icon" title="View">
                                <i class="bi bi-eye"></i>
                            </a>
                        </div>
                    </td>
                </tr>

            @empty

                <tr>
                    <td colspan="6">
                        <div class="empty-state">
                            <i class="bi bi-hourglass-split empty-icon"></i>
                            <p>No pending seller requests found.</p>
                        </div>
                    </td>
                </tr>

            @endforelse

            </tbody>

        </table>
    </div>

    <div class="panel-body pt-0 pb-3">
        {{ $sellerRequests->links() }}
    </div>

</div>

@endsection