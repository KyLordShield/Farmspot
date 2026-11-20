@extends('layouts.app')

@section('title', 'Listing Details')

@push('styles')
    <link rel="stylesheet" href="{{ asset('css/listing-details.css') }}?v={{ filemtime(public_path('css/listing-details.css')) }}">
@endpush

@push('scripts')
    <script src="{{ asset('js/listing-details.js') }}?v={{ filemtime(public_path('js/listing-details.js')) }}" defer></script>
@endpush

@php
    $crop = trim((string) $listing->LST_CROP_ICON);
    $title = $crop ?: 'Listing Details';
    $now = now()->startOfSecond();
    $relative = function ($value) use ($now) {
        $duration = $value->diffForHumans($now, \Carbon\CarbonInterface::DIFF_ABSOLUTE);

        return $value->greaterThan($now) ? "in {$duration}" : "{$duration} ago";
    };
    $date = fn ($value) => blank($value) ? null : \Illuminate\Support\Carbon::parse($value);
    $harvest = $date($listing->LST_HARVEST_DATE);
    $expiry = $date($listing->LST_EXPIRY_DATE);
    $renewed = $date($listing->LST_LAST_RENEWED_AT);
    $renewals = (int) $listing->LST_RENEWAL_COUNT;

    [$status, $statusTone] = match ($listing->LST_STATUS) {
        'AVAILABLE_NOW' => ['Available Now', 'green'],
        'SOON_TO_HARVEST' => ['Soon to Harvest', 'amber'],
        'EXPIRED' => ['Expired', 'red'],
        default => [filled($listing->LST_STATUS) ? 'Not Available' : 'Not provided', 'gray'],
    };
    [$availability, $availabilityTone] = match ($listing->LST_AVAILABILITY) {
        'ACTIVE' => ['Active', 'green'],
        'EXPIRED' => ['Expired', 'red'],
        default => [filled($listing->LST_AVAILABILITY)
            ? \Illuminate\Support\Str::headline(strtolower($listing->LST_AVAILABILITY)) : 'Not provided', 'gray'],
    };

    $expired = $expiry?->lessThanOrEqualTo($now);
    $expiryTone = $expired ? 'red' : ($expiry?->lessThan($now->copy()->addDays(3)) ? 'amber' : 'gray');
    $countdown = $expiry ? ($expired ? 'Expired' : 'Expires '.$relative($expiry)) : null;

    $photos = $listing->photos->sortByDesc('LPHOTO_IS_PRIMARY')->pluck('LPHOTO_FILE_PATH')->filter()->values();
    if ($photos->isEmpty() && filled($listing->LST_IMAGE)) {
        $photos = collect([$listing->LST_IMAGE]);
    }

    $details = [
        'Product' => [
            'Category' => $listing->category?->CAT_NAME,
            'Crop Name' => $crop,
            'Description' => $listing->LST_DESCRIPTION,
        ],
        'Farm & Farmer' => [
            'Farmer' => $listing->farmer?->buyer?->user?->USR_NAME,
            'Farm' => $listing->farm?->FRM_NAME,
            'Barangay' => $listing->farm?->FRM_BARANGAY,
        ],
    ];
    $dates = [
        'Harvest Date' => [$harvest, false],
        'Expiry Date' => [$expiry, false],
        'Created' => [$date($listing->LST_CREATED_AT), true],
        'Last Updated' => [$date($listing->LST_UPDATED_AT), true],
        'Last Renewed' => [$renewed, true],
    ];
@endphp

@section('content')
<div class="listing-details" id="listing-details">
    <header class="ld-header">
        <div>
            <nav aria-label="Breadcrumb" class="ld-breadcrumb">
                <a href="{{ route('listings') }}">Listings</a>
                <span aria-hidden="true">/</span>
                <span aria-current="page">{{ $title }}</span>
            </nav>
            <div class="ld-title">
                <h1>{{ $title }}</h1>
                @if(filled($listing->LST_STATUS))
                    <span class="ld-pill ld-{{ $statusTone }}">{{ $status }}</span>
                @else
                    <em class="ld-muted">Not provided</em>
                @endif
            </div>
            <button type="button" class="ld-copy" data-copy-id="{{ $listing->LST_ID }}"
                    aria-label="Copy listing ID {{ $listing->LST_ID }}">
                <span data-id-value>{{ $listing->LST_ID }}</span> <i class="bi bi-copy" aria-hidden="true"></i>
            </button>
            <span class="ld-muted" role="status" data-copy-feedback></span>
        </div>
        <div class="ld-actions">
            <a href="{{ route('listings') }}" class="ld-button">
                <i class="bi bi-arrow-left" aria-hidden="true"></i> Back to Listings
            </a>
            <a href="{{ route('listings.edit', $listing->LST_ID) }}" class="ld-button ld-primary">
                <i class="bi bi-pencil" aria-hidden="true"></i> Edit Listing
            </a>
        </div>
    </header>

    @if($photos->isNotEmpty())
        <section class="ld-card ld-gallery" aria-label="Listing photos">
            <a class="ld-photo ld-hero" href="{{ $photos->first() }}" data-photo-index="0">
                <img src="{{ $photos->first() }}" alt="{{ $title }} — photo 1">
                <span class="ld-photo-count"><i class="bi bi-arrows-fullscreen" aria-hidden="true"></i>
                    1 / {{ $photos->count() }}</span>
            </a>
            @if($photos->count() > 1)
                <div class="ld-thumbnails">
                    @foreach($photos->slice(1) as $index => $url)
                        <a class="ld-photo ld-thumbnail" href="{{ $url }}" data-photo-index="{{ $index }}">
                            <img src="{{ $url }}" alt="{{ $title }} — photo {{ $index + 1 }}" loading="lazy">
                        </a>
                    @endforeach
                </div>
            @endif
        </section>

        <dialog class="ld-lightbox" aria-labelledby="ld-lightbox-title" data-lightbox>
            <div class="ld-lightbox-heading">
                <h2 id="ld-lightbox-title">Listing photos</h2>
                <button type="button" class="ld-button" data-close-photo autofocus aria-label="Close photo viewer">
                    <i class="bi bi-x-lg" aria-hidden="true"></i>
                </button>
            </div>
            <img data-lightbox-image alt="">
            <div class="ld-lightbox-nav">
                @if($photos->count() > 1)
                    <button type="button" class="ld-button" data-photo-step="-1" aria-label="Previous photo">
                        <i class="bi bi-chevron-left" aria-hidden="true"></i>
                    </button>
                @endif
                <span role="status" data-photo-caption></span>
                @if($photos->count() > 1)
                    <button type="button" class="ld-button" data-photo-step="1" aria-label="Next photo">
                        <i class="bi bi-chevron-right" aria-hidden="true"></i>
                    </button>
                @endif
            </div>
            <a class="ld-original" data-original-photo target="_blank" rel="noopener">Open original</a>
        </dialog>
    @endif

    @if(session('success'))
        <div class="alert alert-success" role="status">{{ session('success') }}</div>
    @endif

    <div class="ld-columns">
        <aside class="ld-card ld-summary" aria-labelledby="ld-summary-title">
            <h2 id="ld-summary-title">Listing Summary</h2>
            <dl class="ld-fields">
                <div>
                    <dt>Crop Status</dt>
                    <dd>
                        @if(filled($listing->LST_STATUS))
                            <span class="ld-pill ld-{{ $statusTone }}">{{ $status }}</span>
                        @else
                            <em class="ld-muted">Not provided</em>
                        @endif
                    </dd>
                </div>
                <div>
                    <dt>Listing Availability</dt>
                    <dd>
                        @if(filled($listing->LST_AVAILABILITY))
                            <span class="ld-pill ld-{{ $availabilityTone }}">{{ $availability }}</span>
                        @else
                            <em class="ld-muted">Not provided</em>
                        @endif
                    </dd>
                </div>
                <div>
                    <dt>Harvest Date</dt>
                    <dd>@include('listings._detail-date', ['value' => $harvest, 'withTime' => false])</dd>
                </div>
                <div>
                    <dt>Expiry</dt>
                    <dd>
                        @if($countdown)
                            <span class="ld-pill ld-{{ $expiryTone }}">{{ $countdown }}</span>
                        @else
                            <em class="ld-muted">Not provided</em>
                        @endif
                    </dd>
                </div>
            </dl>
        </aside>

        <div class="ld-main">
            @foreach($details as $heading => $fields)
                <section class="ld-card">
                    <h2>{{ $heading }}</h2>
                    <dl class="ld-fields">
                        @foreach($fields as $label => $value)
                            <div @class(['lf-wide' => $label === 'Description'])>
                                <dt>{{ $label }}</dt>
                                <dd>
                                    @if(filled($value))
                                        @if($label === 'Barangay')
                                            <i class="bi bi-geo-alt ld-map-pin" aria-hidden="true"></i>
                                        @endif
                                        @if($label === 'Description')<span class="ld-description">{{ $value }}</span>@else{{ $value }}@endif
                                    @else
                                        <em class="ld-muted">Not provided</em>
                                    @endif
                                </dd>
                            </div>
                        @endforeach
                    </dl>
                </section>
            @endforeach

            <section class="ld-card">
                <h2>Dates</h2>
                <dl class="ld-fields">
                    @foreach($dates as $label => [$value, $withTime])
                        <div>
                            <dt>{{ $label }}</dt>
                            <dd>@include('listings._detail-date', ['missing' => $label === 'Last Renewed' ? 'Never' : null])</dd>
                        </div>
                    @endforeach
                </dl>
            </section>

            <section class="ld-card">
                <h2>Renewals</h2>
                <dl class="ld-fields">
                    <div>
                        <dt>Renewal Count</dt>
                        <dd>{{ $renewals }}</dd>
                    </div>
                    <div>
                        <dt>Renewal History</dt>
                        <dd>
                            @if($renewed)
                                <span class="ld-muted">Most recent renewal</span><br>
                                @include('listings._detail-date', ['value' => $renewed, 'withTime' => true])
                            @elseif($renewals === 0)
                                <span class="ld-muted">Never</span>
                            @else
                                <em class="ld-muted">Not provided</em>
                            @endif
                        </dd>
                    </div>
                </dl>
            </section>
        </div>
    </div>
</div>
@endsection
