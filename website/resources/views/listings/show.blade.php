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
                <th>Categories</th>
                <td>{{ $listing->category?->CAT_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Crop Name</th>
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

@php
    // LST_IMAGE is only a cached copy of the primary photo, so the gallery is
    // built from the listing_photo rows. Older listings predate that table and
    // carry nothing but LST_IMAGE, which is still worth showing.
    $photoUrls = $listing->photos->pluck('LPHOTO_FILE_PATH');

    if ($photoUrls->isEmpty() && $listing->LST_IMAGE) {
        $photoUrls = collect([$listing->LST_IMAGE]);
    }
@endphp

@if($photoUrls->isNotEmpty())
<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-images"></i>
            Photos
            <span class="badge badge-soft-neutral ms-1">{{ $photoUrls->count() }}</span>
        </h5>
    </div>
    <div class="panel-body">
        <div class="row g-3 photo-grid">
            @foreach($photoUrls as $photoUrl)
                @php
                    $photoExtension = strtolower(pathinfo((string) parse_url($photoUrl, PHP_URL_PATH), PATHINFO_EXTENSION));
                @endphp
                <div class="col-6 col-md-3">
                    <button type="button"
                            class="btn-photo"
                            data-bs-toggle="modal"
                            data-bs-target="#documentModal"
                            data-document-url="{{ $photoUrl }}"
                            data-document-title="{{ $listing->LST_CROP_ICON ?: 'Listing photo' }} — photo {{ $loop->iteration }}"
                            data-document-kind="{{ in_array($photoExtension, ['jpg', 'jpeg', 'png', 'gif', 'webp'], true) ? 'image' : 'file' }}">
                        <img src="{{ $photoUrl }}"
                             alt="Listing photo {{ $loop->iteration }}"
                             class="photo-thumb"
                             loading="lazy">
                    </button>
                </div>
            @endforeach
        </div>
    </div>
</div>
@endif

@include('partials._media-modal')

@endsection