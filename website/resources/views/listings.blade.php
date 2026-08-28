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

<div class="card shadow-sm border-0 rounded-4">

    <div class="card-body">

        <!-- Filters -->

        <div class="row mb-3">

            <div class="col-md-4">

                <div class="input-group">

                    <span class="input-group-text">
                        <i class="bi bi-search"></i>
                    </span>

                    <input
                        type="text"
                        class="form-control"
                        placeholder="Search listing">

                </div>

            </div>

            <div class="col-md-4">

                <select class="form-select">

                    <option>All Categories</option>

                </select>

            </div>

            <div class="col-md-4">

                <select class="form-select">

                    <option>All Status</option>
                    <option>Available</option>
                    <option>Sold</option>

                </select>

            </div>

        </div>

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

                    <h2>0</h2>

                    <p>Available</p>

                </div>

            </div>

            <div class="col-md-4">

                <div class="dashboard-card">

                    <div class="icon reports">
                        <i class="bi bi-x-circle-fill"></i>
                    </div>

                    <h2>0</h2>

                    <p>Sold</p>

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
                    <th>Price</th>
                    <th>Quantity</th>
                    <th>Status</th>
                    <th width="170">Actions</th>

                </tr>

            </thead>

            <tbody>

            @forelse($listings as $listing)

                <tr>

                    <td>{{ $listing->LST_ID }}</td>

                    <td>-</td>

                    <td>-</td>

                    <td>-</td>

                    <td>-</td>

                    <td>

                        <span class="badge bg-success">
                            Available
                        </span>

                    </td>

                    <td>

                        <button class="btn btn-sm btn-primary">
                            <i class="bi bi-eye-fill"></i>
                        </button>

                        <button class="btn btn-sm btn-warning">
                            <i class="bi bi-pencil-fill"></i>
                        </button>

                        <button class="btn btn-sm btn-danger">
                            <i class="bi bi-trash-fill"></i>
                        </button>

                    </td>

                </tr>

            @empty

                <tr>

                    <td colspan="7" class="text-center text-muted">
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