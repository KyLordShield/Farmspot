@extends('layouts.app')

@php
    $editing = $listing->exists;
    $showHarvest = old('LST_STATUS', $listing->LST_STATUS) === 'SOON_TO_HARVEST';
    $title = $editing ? 'Edit Listing' : 'Add Listing';
    $photos = $editing ? $listing->photos->filter(fn ($photo) => filled($photo->LPHOTO_FILE_PATH))
        ->map(fn ($photo) => ['id' => $photo->LPHOTO_ID, 'url' => $photo->LPHOTO_FILE_PATH, 'primary' => (bool) $photo->LPHOTO_IS_PRIMARY]) : collect();
    if ($editing && $photos->isEmpty() && filled($listing->LST_IMAGE)) {
        $photos = collect([['id' => null, 'url' => $listing->LST_IMAGE, 'primary' => true]]);
    }
    $photoSlots = max(0, \App\Support\PhotoLimits::LISTING - $photos->count());
    $markedPhotos = (array) old('remove_photos', []);
    $markedLegacy = (bool) old('remove_legacy_photo', false);
    $photoSlots += $photos->filter(fn ($photo) => $photo['id'] ? in_array($photo['id'], $markedPhotos, true) : $markedLegacy)->count();
    $statuses = ['AVAILABLE_NOW' => 'Available Now', 'SOON_TO_HARVEST' => 'Soon to Harvest', 'NOT_AVAILABLE' => 'Not Available'];
    $availability = ['ACTIVE' => 'Active', 'NOT_AVAILABLE' => 'Not Available', 'REMOVED' => 'Removed'];
@endphp

@section('title', $title)

@push('styles')
    <link rel="stylesheet" href="{{ asset('css/listing-details.css') }}?v={{ filemtime(public_path('css/listing-details.css')) }}">
@endpush

@push('scripts')
    <script src="{{ asset('js/listing-form.js') }}?v={{ filemtime(public_path('js/listing-form.js')) }}" defer></script>
@endpush

@section('content')
<div class="listing-details listing-form">
    <header class="ld-header">
        <div>
            <nav class="ld-breadcrumb" aria-label="Breadcrumb">
                <a href="{{ route('listings') }}">Listings</a>
                <span aria-hidden="true">/</span>
                @if($editing)
                    <a href="{{ route('listings.show', $listing->LST_ID) }}">{{ $listing->LST_CROP_ICON ?: $listing->LST_ID }}</a>
                    <span aria-hidden="true">/</span>
                @endif
                <span aria-current="page">{{ $title }}</span>
            </nav>
            <div class="ld-title"><h1>{{ $title }}</h1></div>
            @if($editing)
                <span class="font-monospace ld-muted">{{ $listing->LST_ID }}</span>
            @endif
        </div>
        <a href="{{ route('listings') }}" class="ld-button">
            <i class="bi bi-arrow-left" aria-hidden="true"></i> Back to Listings
        </a>
    </header>

    @if($errors->any())
        <div class="alert alert-danger" role="alert">
            <strong>Check the following before saving.</strong>
            <ul class="mb-0">
                @foreach($errors->all() as $error)
                    <li>{{ $error }}</li>
                @endforeach
            </ul>
        </div>
    @endif

    <form method="POST" action="{{ $editing ? route('listings.update', $listing->LST_ID) : route('listings.store') }}"
          enctype="multipart/form-data" data-auto-spinner class="lf-layout">
        @csrf
        @if($editing)
            @method('PUT')
        @endif

        <section class="ld-card lf-product">
            <h2>Product</h2>
            <div class="ld-fields">
                <div>
                    <label for="LST_CROP_ICON" class="form-label">Crop Name</label>
                    <input type="text" class="form-control @error('LST_CROP_ICON') is-invalid @enderror" id="LST_CROP_ICON" name="LST_CROP_ICON"
                           value="{{ old('LST_CROP_ICON', $listing->LST_CROP_ICON) }}"
                           maxlength="{{ $editing ? 255 : \App\Support\InputLimits::CROP_NAME }}" @required(!$editing)>
                    @error('LST_CROP_ICON')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div>
                    <label for="CAT_ID" class="form-label">Category</label>
                    @if($categories->isEmpty())
                        <p class="ld-muted">Add a crop category from the Listings page first.</p>
                    @endif
                    <select class="form-select @error('CAT_ID') is-invalid @enderror" id="CAT_ID" name="CAT_ID" required>
                        <option value="">Choose a category</option>
                        @foreach($categories as $category)
                            <option value="{{ $category->CAT_ID }}" @selected(old('CAT_ID', $listing->CAT_ID) == $category->CAT_ID)>
                                {{ $category->CAT_NAME }}
                            </option>
                        @endforeach
                    </select>
                    @error('CAT_ID')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="lf-wide">
                    <label for="LST_DESCRIPTION" class="form-label">Description</label>
                    <textarea class="form-control @error('LST_DESCRIPTION') is-invalid @enderror" id="LST_DESCRIPTION" name="LST_DESCRIPTION" rows="4"
                              maxlength="{{ \App\Support\InputLimits::DESCRIPTION }}">{{ old('LST_DESCRIPTION', $listing->LST_DESCRIPTION) }}</textarea>
                    @error('LST_DESCRIPTION')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
            </div>
        </section>

        <section class="ld-card lf-farm">
            <h2>Farm &amp; Farmer</h2>
            @if($editing)
                <dl class="ld-fields">
                    @foreach(['Farm' => $listing->farm?->FRM_NAME, 'Farmer' => $listing->farmer?->buyer?->user?->USR_NAME, 'Barangay' => $listing->farm?->FRM_BARANGAY] as $label => $value)
                        <div>
                            <dt>{{ $label }}</dt>
                            <dd>@if(filled($value)) {{ $value }} @else <em class="ld-muted">Not provided</em> @endif</dd>
                        </div>
                    @endforeach
                </dl>
            @else
                <div>
                    <label for="FRM_ID" class="form-label">Farm</label>
                    <select class="form-select @error('FRM_ID') is-invalid @enderror" id="FRM_ID" name="FRM_ID" aria-describedby="FRM_ID-hint" required>
                        <option value="">Choose a farm</option>
                        @foreach($farms as $farm)
                            <option value="{{ $farm->FRM_ID }}" @selected(old('FRM_ID') == $farm->FRM_ID)>
                                {{ $farm->FRM_NAME }} · {{ $farm->farmer?->buyer?->user?->USR_NAME ?: 'Unnamed seller' }}
                                @if(filled($farm->FRM_BARANGAY)) · {{ $farm->FRM_BARANGAY }} @endif
                            </option>
                        @endforeach
                    </select>
                    <div class="form-text" id="FRM_ID-hint">{{ $farms->isEmpty() ? 'An active seller with a registered farm is required.' : 'The listing will belong to the selected farm’s seller.' }}</div>
                    @error('FRM_ID')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
            @endif
        </section>

        <section class="ld-card lf-availability">
            <h2>Availability &amp; Dates</h2>
            <div class="ld-fields">
                <div>
                    <label for="LST_STATUS" class="form-label">Crop Status</label>
                    <select class="form-select @error('LST_STATUS') is-invalid @enderror" id="LST_STATUS" name="LST_STATUS" required>
                        @foreach($statuses as $value => $label)
                            <option value="{{ $value }}" @selected(old('LST_STATUS', $listing->LST_STATUS) === $value)>{{ $label }}</option>
                        @endforeach
                    </select>
                    @error('LST_STATUS')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div id="listing-harvest-field" @if(!$showHarvest) hidden @endif>
                    <label for="LST_HARVEST_DATE" class="form-label">Harvest Date</label>
                    <input type="date" class="form-control @error('LST_HARVEST_DATE') is-invalid @enderror" id="LST_HARVEST_DATE" name="LST_HARVEST_DATE"
                           aria-describedby="LST_HARVEST_DATE-hint" @disabled(!$showHarvest) @required($showHarvest)
                           value="{{ old('LST_HARVEST_DATE', substr((string) $listing->LST_HARVEST_DATE, 0, 10)) }}">
                    <div class="form-text" id="LST_HARVEST_DATE-hint">Required for crops that are soon to harvest.</div>
                    @error('LST_HARVEST_DATE')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                @if($editing)
                <div>
                    <label for="LST_AVAILABILITY" class="form-label">Listing Availability</label>
                    <select class="form-select @error('LST_AVAILABILITY') is-invalid @enderror" id="LST_AVAILABILITY" name="LST_AVAILABILITY" aria-describedby="LST_AVAILABILITY-hint" required>
                        @foreach($availability as $value => $label)
                            <option value="{{ $value }}" @selected(old('LST_AVAILABILITY', $listing->LST_AVAILABILITY) === $value)>{{ $label }}</option>
                        @endforeach
                    </select>
                    <div class="form-text" id="LST_AVAILABILITY-hint">Removed listings are taken off the marketplace.</div>
                    @error('LST_AVAILABILITY')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                    <div>
                        <span class="form-label d-block">Expiry Date</span>
                        @if($listing->LST_EXPIRY_DATE)
                            {{ \Illuminate\Support\Carbon::parse($listing->LST_EXPIRY_DATE)->format('M j, Y') }}
                        @else
                            <em class="ld-muted">Not provided</em>
                        @endif
                        <div class="form-text">Renewal controls the expiry date.</div>
                    </div>
                @endif
            </div>
        </section>

        <section class="ld-card lf-photos" data-listing-photos data-photo-limit="{{ \App\Support\PhotoLimits::LISTING }}" data-existing-count="{{ $photos->count() }}">
            <h2>Photos</h2>
            @if($photos->isNotEmpty())
                <div class="ld-thumbnails mb-3">
                    @foreach($photos as $photo)
                        <div class="lf-photo-item">
                            <a href="{{ $photo['url'] }}" class="ld-photo ld-thumbnail" target="_blank" rel="noopener">
                                <img src="{{ $photo['url'] }}" alt="{{ $listing->LST_CROP_ICON ?: 'Listing' }} photo {{ $loop->iteration }}" loading="lazy">
                            </a>
                            <span class="lf-photo-caption">Photo {{ $loop->iteration }}{{ $photo['primary'] ? ' · Cover' : '' }}</span>
                            <label class="lf-remove-photo">
                                <input type="checkbox" data-remove-photo name="{{ $photo['id'] ? 'remove_photos[]' : 'remove_legacy_photo' }}" value="{{ $photo['id'] ?? '1' }}" @checked($photo['id'] ? in_array($photo['id'], $markedPhotos, true) : $markedLegacy)>
                                Remove<span class="visually-hidden"> photo {{ $loop->iteration }}</span>
                            </label>
                        </div>
                    @endforeach
                </div>
            @endif
            @if($photos->isNotEmpty())<p class="form-text">Select Remove, then Save Changes to delete a photo. Uncheck to keep it.</p>@endif
                <label for="photos" class="form-label">Add Photos</label>
                <input type="file" class="form-control" id="photos" name="photos[]" accept="image/*"
                       aria-describedby="photos-hint" multiple @disabled($photoSlots === 0)>
                <div id="photos-hint" class="form-text" role="status">{{ $photoSlots ? "You can add up to {$photoSlots} more photos, 5 MB each." : 'Photo limit reached. Select a photo to remove before adding another.' }}</div>
        </section>

        <div class="ld-card ld-actions lf-actions">
            <button type="submit" class="ld-button ld-primary" @disabled(!$editing && ($farms->isEmpty() || $categories->isEmpty()))>
                <i class="bi bi-check-lg" aria-hidden="true"></i> {{ $editing ? 'Save Changes' : 'Add Listing' }}
            </button>
            <a href="{{ $editing ? route('listings.show', $listing->LST_ID) : route('listings') }}" class="ld-button">Cancel</a>
        </div>
    </form>
</div>
@endsection
