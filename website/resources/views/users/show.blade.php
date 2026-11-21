@extends('layouts.app')

@section('title', 'User Details')

@push('styles')
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap">
    <link rel="stylesheet" href="{{ asset('css/user-details.css') }}?v={{ filemtime(public_path('css/user-details.css')) }}">
@endpush

@push('scripts')
    <script src="{{ asset('js/user-details.js') }}?v={{ filemtime(public_path('js/user-details.js')) }}" defer></script>
@endpush

@section('content')
@php
    $nameParts = preg_split('/\s+/u', trim($user->USR_NAME), -1, PREG_SPLIT_NO_EMPTY);
    $initials = $nameParts ? mb_strtoupper(mb_substr($nameParts[0], 0, 1) . mb_substr($nameParts[1] ?? '', 0, 1)) : '?';
    $isFarmer = $user->isFarmer();
    $role = $user->USR_ROLE === 'ADMIN' ? 'Admin' : ($isFarmer ? 'Farmer' : 'Buyer');
    [$status, $statusTone] = match ($user->USR_STATUS) {
        'ACTIVE' => ['Active', 'green'],
        'PENDING_VERIFICATION' => ['Pending Verification', 'amber'],
        default => ['Deactivated', 'gray'],
    };
    $formatDate = fn ($value) => \Carbon\Carbon::parse($value)
        ->timezone(config('farmspot.display_timezone'))->format('M j, Y · g:i A');
@endphp

<div class="user-details">
    <nav class="user-details-breadcrumb" aria-label="Breadcrumb">
        <a href="{{ route('users') }}">Users</a>
        <span aria-hidden="true">/</span>
        <span aria-current="page">{{ $user->USR_NAME }}</span>
    </nav>

    <header class="user-details-header">
        <h1>User Details</h1>
        <div class="user-details-actions">
            <a href="{{ route('users') }}" class="user-details-button user-details-back">
                <i class="bi bi-arrow-left" aria-hidden="true"></i> Back to Users
            </a>
            <a href="{{ route('users.edit', $user->USR_ID) }}" class="user-details-button user-details-edit">
                <i class="bi bi-pencil" aria-hidden="true"></i> Edit User
            </a>
        </div>
    </header>

    <div class="user-details-layout">
        <section class="user-details-card user-details-profile" aria-labelledby="user-profile-name">
            <div class="user-details-avatar" aria-hidden="true">
                {{ $initials }}
                @if(filled($user->USR_PHOTO_PATH))
                    <img src="{{ $user->USR_PHOTO_PATH }}" alt="" data-profile-photo hidden>
                @endif
            </div>
            <h2 id="user-profile-name">{{ $user->USR_NAME }} @include('users.partials.premium-indicator')</h2>
            <p class="user-details-email">
                @if(filled($user->USR_EMAIL))
                    {{ $user->USR_EMAIL }}
                @else
                    <em class="user-details-missing">Not provided</em>
                @endif
            </p>
            <div class="user-details-badges">
                <span class="user-details-pill user-details-blue">{{ $role }}</span>
                <span class="user-details-pill user-details-{{ $statusTone }} user-details-status">{{ $status }}</span>
            </div>
            <div class="user-details-id">
                <span class="user-details-label">User ID</span>
                <span class="user-details-chip">
                    <code>{{ $user->USR_ID }}</code>
                    <button type="button" class="user-details-copy" data-copy-value="{{ $user->USR_ID }}" data-copy-label="User ID" aria-label="Copy user ID" title="Copy user ID">
                        <i class="bi bi-copy" aria-hidden="true"></i>
                    </button>
                </span>
            </div>
        </section>

        <div class="user-details-sections">
            <section class="user-details-card" aria-labelledby="user-contact-heading">
                <h2 id="user-contact-heading">Contact Information</h2>
                <dl class="user-details-fields">
                    <div>
                        <dt>Email</dt>
                        <dd class="user-details-copy-row">
                            @if(filled($user->USR_EMAIL))
                                <span>{{ $user->USR_EMAIL }}</span>
                                <button type="button" class="user-details-copy" data-copy-value="{{ $user->USR_EMAIL }}" data-copy-label="Email" aria-label="Copy email address" title="Copy email address">
                                    <i class="bi bi-copy" aria-hidden="true"></i>
                                </button>
                            @else
                                <em class="user-details-missing">Not provided</em>
                            @endif
                        </dd>
                    </div>
                    <div>
                        <dt>Mobile</dt>
                        <dd>
                            @if(filled($user->USR_MOBILE_NUMBER))
                                {{ $user->USR_MOBILE_NUMBER }}
                            @else
                                <em class="user-details-missing">Not provided</em>
                            @endif
                        </dd>
                    </div>
                    <div>
                        <dt>Address</dt>
                        <dd>
                            @if(filled($user->USR_ADDRESS))
                                {{ $user->USR_ADDRESS }}
                            @else
                                <em class="user-details-missing">Not provided</em>
                            @endif
                        </dd>
                    </div>
                </dl>
            </section>

            <section class="user-details-card" aria-labelledby="user-account-heading">
                <h2 id="user-account-heading">Account Details</h2>
                <dl class="user-details-fields">
                    <div><dt>Role</dt><dd><span class="user-details-pill user-details-blue">{{ $role }}</span></dd></div>
                    <div><dt>Status</dt><dd><span class="user-details-pill user-details-{{ $statusTone }} user-details-status">{{ $status }}</span></dd></div>
                    <div><dt>Seller Mode</dt><dd><span class="user-details-pill {{ $isFarmer ? 'user-details-green' : 'user-details-gray' }}">{{ $isFarmer ? 'Yes' : 'No' }}</span></dd></div>
                    <div>
                        <dt>Registered</dt>
                        <dd>
                            @if($user->USR_CREATED_AT)
                                {{ $formatDate($user->USR_CREATED_AT) }}
                            @else
                                <em class="user-details-missing">Not provided</em>
                            @endif
                        </dd>
                    </div>
                    @if($user->USR_TAKEDOWN_REASON)
                        <div class="user-details-wide">
                            <dt>Deactivation Reason</dt>
                            <dd>{{ $user->USR_TAKEDOWN_REASON }}
                                <div class="user-details-note">Shown to the user at sign-in; they can request a re-evaluation.</div>
                            </dd>
                        </div>
                    @endif
                    @if($user->USR_TAKEDOWN_AT)
                        <div><dt>Deactivated At</dt><dd>{{ $formatDate($user->USR_TAKEDOWN_AT) }}</dd></div>
                    @endif
                </dl>
            </section>
        </div>
    </div>

    <div class="user-details-copy-feedback" role="status" data-copy-feedback></div>

@if($farmer)
    <section class="user-details-card user-details-seller" aria-labelledby="user-seller-heading">
        <h2 id="user-seller-heading">Seller Profile</h2>
        <dl class="user-details-fields">
            <div><dt>Farmer ID</dt><dd><code>{{ $farmer->FMR_ID }}</code></dd></div>
            <div>
                <dt>Seller Mode</dt>
                <dd><span class="user-details-pill {{ $farmer->FMR_SELLER_MODE_ACTIVE ? 'user-details-green' : 'user-details-gray' }}">{{ $farmer->FMR_SELLER_MODE_ACTIVE ? 'Active' : 'Off' }}</span></dd>
            </div>
            @if($farmer->FMR_VERIFIED_AT)
                <div><dt>Verified At</dt><dd>{{ $formatDate($farmer->FMR_VERIFIED_AT) }}</dd></div>
            @endif
        </dl>

        @if($farmer->farms->isEmpty())
            <div class="panel-body pt-0 pb-3">
                <div class="empty-state">
                    <i class="bi bi-geo-alt empty-icon"></i>
                    <p>This seller has not submitted a farm yet.</p>
                </div>
            </div>
        @else
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Farm</th>
                            <th>Barangay</th>
                            <th>Status</th>
                            <th>Submitted At</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($farmer->farms as $farm)
                            <tr>
                                <td>{{ $farm->FRM_NAME }}</td>
                                <td class="cell-secondary">{{ $farm->FRM_BARANGAY }}</td>
                                <td>
                                    @if($farm->FRM_STATUS == 'APPROVED')
                                        <span class="badge badge-soft-success">Approved</span>
                                    @elseif($farm->FRM_STATUS == 'REJECTED')
                                        <span class="badge badge-soft-danger">Rejected</span>
                                    @elseif($farm->FRM_STATUS == 'ARCHIVED')
                                        <span class="badge badge-soft-neutral">Archived</span>
                                    @else
                                        <span class="badge badge-soft-warning">Pending Review</span>
                                    @endif
                                </td>
                                <td class="cell-faint">
                                    {{ \Carbon\Carbon::parse($farm->FRM_CREATED_AT)->timezone(config('farmspot.display_timezone'))->format('M j, Y · g:i A') }}
                                </td>
                                <td>
                                    <div class="actions">
                                        <a href="{{ route('users.farms.show', ['id' => $user->USR_ID, 'farmId' => $farm->FRM_ID]) }}"
                                           class="btn-icon" title="View farm" aria-label="View farm">
                                            <i class="bi bi-eye"></i>
                                        </a>
                                    </div>
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </section>
@endif

</div>
@endsection
