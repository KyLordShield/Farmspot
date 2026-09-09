@extends('layouts.app')

@section('title', 'Edit Listing')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Edit Listing</h1>
        <div class="page-desc">Update details for {{ $listing->LST_ID }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('listings') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Listings
        </a>
    </div>
</div>

@if($errors->any())
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        <ul class="mb-0">
            @foreach($errors->all() as $error)
                <li>{{ $error }}</li>
            @endforeach
        </ul>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="panel form-card">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-pencil"></i>
            {{ $listing->LST_ID }}
        </h5>
    </div>
    <div class="panel-body">
        <form method="POST" action="{{ route('listings.update', $listing->LST_ID) }}">
            @csrf
            @method('PUT')

            <div class="mb-3">
                <label for="LST_CROP_ICON" class="form-label">Crop Icon</label>
                <input type="text" class="form-control @error('LST_CROP_ICON') is-invalid @enderror"
                       id="LST_CROP_ICON" name="LST_CROP_ICON"
                       value="{{ old('LST_CROP_ICON', $listing->LST_CROP_ICON) }}">
                @error('LST_CROP_ICON')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="LST_HARVEST_DATE" class="form-label">Harvest Date</label>
                <input type="date" class="form-control @error('LST_HARVEST_DATE') is-invalid @enderror"
                       id="LST_HARVEST_DATE" name="LST_HARVEST_DATE"
                       value="{{ old('LST_HARVEST_DATE', $listing->LST_HARVEST_DATE) }}">
                @error('LST_HARVEST_DATE')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="LST_STATUS" class="form-label">Status</label>
                <select class="form-select @error('LST_STATUS') is-invalid @enderror"
                        id="LST_STATUS" name="LST_STATUS" required>
                    <option value="AVAILABLE_NOW"
                        {{ old('LST_STATUS', $listing->LST_STATUS) == 'AVAILABLE_NOW' ? 'selected' : '' }}>
                        Available Now
                    </option>
                    <option value="SOON_TO_HARVEST"
                        {{ old('LST_STATUS', $listing->LST_STATUS) == 'SOON_TO_HARVEST' ? 'selected' : '' }}>
                        Soon to Harvest
                    </option>
                    <option value="NOT_AVAILABLE"
                        {{ old('LST_STATUS', $listing->LST_STATUS) == 'NOT_AVAILABLE' ? 'selected' : '' }}>
                        Not Available
                    </option>
                </select>
                @error('LST_STATUS')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="LST_AVAILABILITY" class="form-label">Availability</label>
                <select class="form-select @error('LST_AVAILABILITY') is-invalid @enderror"
                        id="LST_AVAILABILITY" name="LST_AVAILABILITY" required>
                    <option value="ACTIVE"
                        {{ old('LST_AVAILABILITY', $listing->LST_AVAILABILITY) == 'ACTIVE' ? 'selected' : '' }}>
                        Active
                    </option>
                    <option value="NOT_AVAILABLE"
                        {{ old('LST_AVAILABILITY', $listing->LST_AVAILABILITY) == 'NOT_AVAILABLE' ? 'selected' : '' }}>
                        Not Available
                    </option>
                    <option value="REMOVED"
                        {{ old('LST_AVAILABILITY', $listing->LST_AVAILABILITY) == 'REMOVED' ? 'selected' : '' }}>
                        Removed
                    </option>
                </select>
                @error('LST_AVAILABILITY')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="mb-3">
                <label for="CAT_ID" class="form-label">Category</label>
                <select class="form-select @error('CAT_ID') is-invalid @enderror"
                        id="CAT_ID" name="CAT_ID" required>
                    @foreach($categories as $category)
                        <option value="{{ $category->CAT_ID }}"
                            {{ old('CAT_ID', $listing->CAT_ID) == $category->CAT_ID ? 'selected' : '' }}>
                            {{ $category->CAT_NAME }}
                        </option>
                    @endforeach
                </select>
                @error('CAT_ID')
                    <div class="text-danger small mt-1">{{ $message }}</div>
                @enderror
            </div>

            <div class="alert alert-secondary d-flex align-items-center" role="alert">
                <i class="bi bi-lock me-2"></i>
                <div>Farmer and Farm ownership cannot be changed here.</div>
            </div>

            <div class="d-flex gap-2">
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-lg me-1"></i> Update Listing
                </button>
                <a href="{{ route('listings') }}" class="btn btn-ghost">Cancel</a>
            </div>
        </form>
    </div>
</div>

@endsection