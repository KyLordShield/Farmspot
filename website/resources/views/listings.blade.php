@extends('layouts.app')

@section('title', 'Listings')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Listings</h1>
        <div class="page-desc">Manage all crop listings</div>
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
        <div class="stat-icon tint-amber">
            <i class="bi bi-basket"></i>
        </div>
        <div>
            <div class="stat-value">{{ $listings->total() }}</div>
            <div class="stat-label">Total listings</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-green">
            <i class="bi bi-check-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $listings->where('LST_AVAILABILITY','ACTIVE')->count() }}</div>
            <div class="stat-label">Active</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-slate">
            <i class="bi bi-x-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $listings->where('LST_AVAILABILITY','NOT_AVAILABLE')->count() }}</div>
            <div class="stat-label">Not available</div>
        </div>
    </div>

</div>

<div class="panel">

    <!-- Filters -->
    <form method="GET" action="{{ route('listings') }}" class="filter-bar">

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
                    placeholder="Search listing">
                <button class="btn btn-farm" type="submit">
                    Search
                </button>
            </div>
        </div>

        <div class="filter-auto">
            <select name="category" class="form-select" onchange="this.form.submit()">
                <option value="">All Categories</option>
                @foreach($categories as $category)
                    <option value="{{ $category->CAT_ID }}"
                        {{ request('category') == $category->CAT_ID ? 'selected' : '' }}>
                        {{ $category->CAT_NAME }}
                    </option>
                @endforeach
            </select>
        </div>

        <div class="filter-auto">
            <select name="status" class="form-select" onchange="this.form.submit()">
                <option value="">All Status</option>
                <option value="ACTIVE" {{ request('status') == 'ACTIVE' ? 'selected' : '' }}>Active</option>
                <option value="NOT_AVAILABLE" {{ request('status') == 'NOT_AVAILABLE' ? 'selected' : '' }}>Not Available</option>
                <option value="REMOVED" {{ request('status') == 'REMOVED' ? 'selected' : '' }}>Removed</option>
            </select>
        </div>

    </form>

    <div class="table-responsive">
        <table class="data-table">

            <thead>
                <tr>
                    <th>ID</th>
                    <th>Crop</th>
                    <th>Farmer</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
            </thead>

            <tbody>

            @forelse($listings as $listing)

                <tr>
                    <td><span class="id-cell">{{ $listing->LST_ID }}</span></td>
                    <td>{{ $listing->category?->CAT_NAME ?? '-' }}</td>
                    <td class="cell-secondary">{{ $listing->farmer?->buyer?->user?->USR_NAME ?? '-' }}</td>
                    <td>
                        @if($listing->LST_STATUS == 'AVAILABLE_NOW')
                            <span class="badge badge-soft-success">Available Now</span>
                        @elseif($listing->LST_STATUS == 'SOON_TO_HARVEST')
                            <span class="badge badge-soft-warning">Soon to Harvest</span>
                        @else
                            <span class="badge badge-soft-neutral">Not Available</span>
                        @endif
                    </td>
                    <td>
                        <div class="actions">
                            <a href="{{ route('listings.show', $listing->LST_ID) }}"
                               class="btn-icon" title="View">
                                <i class="bi bi-eye"></i>
                            </a>

                            <a href="{{ route('listings.edit', $listing->LST_ID) }}"
                               class="btn-icon" title="Edit">
                                <i class="bi bi-pencil"></i>
                            </a>

                            <form method="POST" action="{{ route('listings.destroy', $listing->LST_ID) }}"
                                  class="d-inline"
                                  onsubmit="return confirm('Are you sure you want to remove this listing?');">
                                @csrf
                                @method('DELETE')
                                <button type="submit" class="btn-icon danger" title="Remove">
                                    <i class="bi bi-trash"></i>
                                </button>
                            </form>
                        </div>
                    </td>
                </tr>

            @empty

                <tr>
                    <td colspan="5">
                        <div class="empty-state">
                            <i class="bi bi-basket empty-icon"></i>
                            <p>No listings found.</p>
                        </div>
                    </td>
                </tr>

            @endforelse

            </tbody>

        </table>
    </div>

    <div class="panel-body pt-0 pb-3">
        {{ $listings->links() }}
    </div>

</div>

@endsection