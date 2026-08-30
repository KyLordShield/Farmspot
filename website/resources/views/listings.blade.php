@extends('layouts.app')

@section('title', 'Listings')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">

    <div>
        <h2 class="fw-bold mb-0">Listings</h2>
        <small class="text-muted">
            Manage all crop listings
        </small>
    </div>

</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="card shadow-sm border-0 rounded-4">

    <div class="card-body">

        <!-- Filters -->

        <form method="GET" action="{{ route('listings') }}" class="row mb-3">

            <div class="col-md-4">

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

                    <button class="btn btn-success" type="submit">
                        Search
                    </button>

                </div>

            </div>

            <div class="col-md-4">

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

            <div class="col-md-4">

                <select name="status" class="form-select" onchange="this.form.submit()">

                    <option value="">All Status</option>

                    <option value="ACTIVE" {{ request('status') == 'ACTIVE' ? 'selected' : '' }}>
                        Active
                    </option>

                    <option value="NOT_AVAILABLE" {{ request('status') == 'NOT_AVAILABLE' ? 'selected' : '' }}>
                        Not Available
                    </option>

                    <option value="REMOVED" {{ request('status') == 'REMOVED' ? 'selected' : '' }}>
                        Removed
                    </option>

                </select>

            </div>

        </form>

        <!-- Summary Cards -->

        <div class="row mb-4">

            <div class="col-md-4">

                <div class="dashboard-card">

                    <div class="icon listings">
                        <i class="bi bi-basket-fill"></i>
                    </div>

                    <h2>{{ $listings->total() }}</h2>

                    <p>Total Listings</p>

                </div>

            </div>

            <div class="col-md-4">

                <div class="dashboard-card">

                    <div class="icon farmers">
                        <i class="bi bi-check-circle-fill"></i>
                    </div>

                    <h2>{{ $listings->where('LST_AVAILABILITY','ACTIVE')->count() }}</h2>

                    <p>Active</p>

                </div>

            </div>

            <div class="col-md-4">

                <div class="dashboard-card">

                    <div class="icon reports">
                        <i class="bi bi-x-circle-fill"></i>
                    </div>

                    <h2>{{ $listings->where('LST_AVAILABILITY','NOT_AVAILABLE')->count() }}</h2>

                    <p>Not Available</p>

                </div>

            </div>

        </div>

        <!-- Table -->

        <table class="table table-hover align-middle">

            <thead class="table-light">

                <tr>

                    <th>ID</th>
                    <th>Crop</th>
                    <th>Farmer</th>
                    <th>Status</th>
                    <th width="170">Actions</th>

                </tr>

            </thead>

            <tbody>

            @forelse($listings as $listing)

                <tr>

                    <td>{{ $listing->LST_ID }}</td>

                    <td>{{ $listing->category?->CAT_NAME ?? '-' }}</td>

                    <td>{{ $listing->farmer?->buyer?->user?->USR_NAME ?? '-' }}</td>

                    <td>

                        @if($listing->LST_STATUS == 'AVAILABLE_NOW')

                            <span class="badge bg-success">
                                Available Now
                            </span>

                        @elseif($listing->LST_STATUS == 'SOON_TO_HARVEST')

                            <span class="badge bg-warning text-dark">
                                Soon to Harvest
                            </span>

                        @else

                            <span class="badge bg-secondary">
                                Not Available
                            </span>

                        @endif

                    </td>

                    <td>

                        <a href="{{ route('listings.show', $listing->LST_ID) }}"
                           class="btn btn-sm btn-primary">
                            <i class="bi bi-eye-fill"></i>
                        </a>

                        <a href="{{ route('listings.edit', $listing->LST_ID) }}"
                           class="btn btn-sm btn-warning">
                            <i class="bi bi-pencil-fill"></i>
                        </a>

                        <form method="POST" action="{{ route('listings.destroy', $listing->LST_ID) }}"
                              class="d-inline"
                              onsubmit="return confirm('Are you sure you want to remove this listing?');">
                            @csrf
                            @method('DELETE')
                            <button type="submit" class="btn btn-sm btn-danger" title="Remove">
                                <i class="bi bi-trash-fill"></i>
                            </button>
                        </form>

                    </td>

                </tr>

            @empty

                <tr>

                    <td colspan="5" class="text-center text-muted">
                        No listings found.
                    </td>

                </tr>

            @endforelse

            </tbody>

        </table>

        <div class="mt-3">

            {{ $listings->links() }}

        </div>

    </div>

</div>

@endsection