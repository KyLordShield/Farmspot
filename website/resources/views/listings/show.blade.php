@extends('layouts.app')

@section('title', 'Listing Details')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Listing Details</h1>
        <div class="page-desc">{{ $listing->LST_ID }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('listings') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Listings
        </a>
        <a href="{{ route('listings.edit', $listing->LST_ID) }}" class="btn btn-farm">
            <i class="bi bi-pencil me-1"></i> Edit Listing
        </a>
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-basket"></i>
            {{ $listing->LST_ID }}
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">

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
                        <span class="badge badge-soft-success">Available Now</span>
                    @elseif($listing->LST_STATUS == 'SOON_TO_HARVEST')
                        <span class="badge badge-soft-warning">Soon to Harvest</span>
                    @else
                        <span class="badge badge-soft-neutral">Not Available</span>
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
                <td class="cell-faint">{{ $listing->LST_IMAGE ?: '-' }}</td>
            </tr>

            <tr>
                <th>Created</th>
                <td class="cell-secondary">{{ $listing->LST_CREATED_AT ?: '-' }}</td>
            </tr>

            <tr>
                <th>Last Updated</th>
                <td class="cell-secondary">{{ $listing->LST_UPDATED_AT ?: '-' }}</td>
            </tr>

        </table>
    </div>
</div>

@endsection