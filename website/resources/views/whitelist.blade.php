@extends('layouts.app')

@section('title','Whitelist')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Whitelist</h1>
        <div class="page-desc">Manage approved mobile numbers</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('whitelist.create') }}" class="btn btn-farm">
            <i class="bi bi-plus-circle me-1"></i> Add Number
        </a>
    </div>
</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="stat-grid">

    <div class="stat-card">
        <div class="stat-icon tint-green">
            <i class="bi bi-check-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $whitelists->total() }}</div>
            <div class="stat-label">Total numbers</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-amber">
            <i class="bi bi-check-lg"></i>
        </div>
        <div>
            <div class="stat-value">{{ $whitelists->where('WLST_IS_ACTIVE', 1)->count() }}</div>
            <div class="stat-label">Active</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-slate">
            <i class="bi bi-slash-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $whitelists->where('WLST_IS_ACTIVE', 0)->count() }}</div>
            <div class="stat-label">Inactive</div>
        </div>
    </div>

</div>

<div class="panel">

    <form method="GET" action="{{ route('whitelist') }}" class="filter-bar">

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
                    placeholder="Search mobile number">
                <button class="btn btn-farm" type="submit">
                    Search
                </button>
            </div>
        </div>

        <div class="filter-auto">
            <select name="status" class="form-select" onchange="this.form.submit()">
                <option value="">All Status</option>
                <option value="Active" {{ request('status') == 'Active' ? 'selected' : '' }}>Active</option>
                <option value="Inactive" {{ request('status') == 'Inactive' ? 'selected' : '' }}>Inactive</option>
            </select>
        </div>

    </form>

    <div class="table-responsive">
        <table class="data-table">

            <thead>
                <tr>
                    <th>ID</th>
                    <th>Mobile Number</th>
                    <th>Status</th>
                    <th>Added At</th>
                    <th>Added By</th>
                    <th>Deactivated By</th>
                    <th>Actions</th>
                </tr>
            </thead>

            <tbody>

            @forelse($whitelists as $whitelist)

                <tr>
                    <td><span class="id-cell">{{ $whitelist->WLST_ID }}</span></td>
                    <td>{{ $whitelist->WLST_MOBILE_NUMBER }}</td>
                    <td>
                        @if($whitelist->WLST_IS_ACTIVE)
                            <span class="badge badge-soft-success">Active</span>
                        @else
                            <span class="badge badge-soft-neutral">Inactive</span>
                        @endif
                    </td>
                    <td class="cell-secondary">{{ $whitelist->WLST_ADDED_AT }}</td>
                    <td class="cell-secondary">{{ $whitelist->addedBy?->USR_NAME ?? '-' }}</td>
                    <td class="cell-secondary">{{ $whitelist->deactivatedBy?->USR_NAME ?? '—' }}</td>
                    <td>
                        <div class="actions">
                            <a href="{{ route('whitelist.show', $whitelist->WLST_ID) }}"
                               class="btn-icon" title="View">
                                <i class="bi bi-eye"></i>
                            </a>

                            @if($whitelist->WLST_IS_ACTIVE)
                                <form method="POST" action="{{ route('whitelist.toggle', $whitelist->WLST_ID) }}"
                                      class="d-inline"
                                      onsubmit="return confirm('Are you sure you want to deactivate this number?');">
                                    @csrf
                                    @method('PATCH')
                                    <button type="submit" class="btn-icon danger" title="Deactivate">
                                        <i class="bi bi-slash-circle"></i>
                                    </button>
                                </form>
                            @else
                                <form method="POST" action="{{ route('whitelist.toggle', $whitelist->WLST_ID) }}"
                                      class="d-inline">
                                    @csrf
                                    @method('PATCH')
                                    <button type="submit" class="btn-icon confirm" title="Reactivate">
                                        <i class="bi bi-check-circle"></i>
                                    </button>
                                </form>
                            @endif
                        </div>
                    </td>
                </tr>

            @empty

                <tr>
                    <td colspan="7">
                        <div class="empty-state">
                            <i class="bi bi-check-circle empty-icon"></i>
                            <p>No whitelist records found.</p>
                        </div>
                    </td>
                </tr>

            @endforelse

            </tbody>

        </table>
    </div>

    <div class="panel-body pt-0 pb-3">
        {{ $whitelists->links() }}
    </div>

</div>

@endsection