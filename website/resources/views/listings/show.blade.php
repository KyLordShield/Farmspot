@extends('layouts.app')

@section('title', 'Listing Details')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">
    <div>
        <h2 class="fw-bold mb-0">Listing Details</h2>
        <small class="text-muted">{{ $listing->LST_ID }}</small>
    </div>
    <a href="{{ route('listings') }}" class="btn btn-outline-secondary">
        <i class="bi bi-arrow-left"></i> Back to Listings
    </a>
</div>

<div class="card shadow-sm border-0 rounded-4">
    <div class="card-header bg-success text-white">
        <h4 class="mb-0"><i class="bi bi-basket-fill"></i> {{ $listing->LST_ID }}</h4>
    </div>
    <div class="card-body">
        <table class="table">

            <tr>
                <th>Crop</th>
                <td>{{ $listing->category?->CAT_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Crop Icon</th>
                <td>{{ $listing->LST_CROP_ICON ?: '-' }}</td>
            </tr>

            <tr>
                <th>Farmer</th>
                <td>{{ $listing->farmer?->buyer?->user?->USR_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Farm</th>
                <td>{{ $listing->farm?->FRM_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Farm Barangay</th>
                <td>{{ $listing->farm?->FRM_BARANGAY ?? '-' }}</td>
            </tr>

            <tr>
                <th>Status</th>
                <td>
                    @if($listing->LST_STATUS == 'AVAILABLE_NOW')
                        <span class="badge bg-success">Available Now</span>
                    @elseif($listing->LST_STATUS == 'SOON_TO_HARVEST')
                        <span class="badge bg-warning text-dark">Soon to Harvest</span>
                    @else
                        <span class="badge bg-secondary">Not Available</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Availability</th>
                <td>{{ $listing->LST_AVAILABILITY }}</td>
            </tr>

            <tr>
                <th>Harvest Date</th>
                <td>{{ $listing->LST_HARVEST_DATE ?: '-' }}</td>
            </tr>

            <tr>
                <th>Expiry Date</th>
                <td>{{ $listing->LST_EXPIRY_DATE ?: '-' }}</td>
            </tr>

            <tr>
                <th>Image</th>
                <td>{{ $listing->LST_IMAGE ?: '-' }}</td>
            </tr>

            <tr>
                <th>Created</th>
                <td>{{ $listing->LST_CREATED_AT ?: '-' }}</td>
            </tr>

            <tr>
                <th>Last Updated</th>
                <td>{{ $listing->LST_UPDATED_AT ?: '-' }}</td>
            </tr>

        </table>

        <a href="{{ route('listings.edit', $listing->LST_ID) }}" class="btn btn-warning">
            <i class="bi bi-pencil-fill"></i> Edit Listing
        </a>
    </div>
</div>

@endsection