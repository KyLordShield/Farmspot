@extends('layouts.app')

@section('title', 'User Details')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">User Details</h1>
        <div class="page-desc">{{ $user->USR_ID }} · {{ $user->USR_NAME }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('users') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Users
        </a>
        <a href="{{ route('users.edit', $user->USR_ID) }}" class="btn btn-farm">
            <i class="bi bi-pencil me-1"></i> Edit User
        </a>
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-person"></i>
            User Information
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">

            <tr>
                <th>User ID</th>
                <td><span class="id-cell">{{ $user->USR_ID }}</span></td>
            </tr>

            <tr>
                <th>Name</th>
                <td>{{ $user->USR_NAME }}</td>
            </tr>

            <tr>
                <th>Email</th>
                <td>{{ $user->USR_EMAIL }}</td>
            </tr>

            <tr>
                <th>Mobile</th>
                <td>{{ $user->USR_MOBILE_NUMBER }}</td>
            </tr>

            <tr>
                <th>Address</th>
                <td>{{ $user->USR_ADDRESS ?: '—' }}</td>
            </tr>

            <tr>
                <th>Role</th>
                <td>
                    @if($user->USR_ROLE == 'ADMIN')
                        <span class="badge badge-soft-danger">Admin</span>
                    @elseif($user->isFarmer())
                        <span class="badge badge-soft-success">Farmer</span>
                    @else
                        <span class="badge badge-soft-neutral">Buyer</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Status</th>
                <td>
                    @if($user->USR_STATUS == 'ACTIVE')
                        <span class="badge badge-soft-success">Active</span>
                    @elseif($user->USR_STATUS == 'PENDING_VERIFICATION')
                        <span class="badge badge-soft-warning">Pending Verification</span>
                    @else
                        <span class="badge badge-soft-neutral">Deactivated</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Seller Mode</th>
                <td>{{ $user->isFarmer() ? 'Yes' : 'No' }}</td>
            </tr>

            @if($user->USR_TAKEDOWN_REASON)
                <tr>
                    <th>Deactivation Reason</th>
                    <td>
                        {{ $user->USR_TAKEDOWN_REASON }}
                        <div class="cell-secondary small mt-1">
                            Shown to the user at sign-in; they can request a re-evaluation.
                        </div>
                    </td>
                </tr>
            @endif

            @if($user->USR_TAKEDOWN_AT)
                <tr>
                    <th>Deactivated At</th>
                    <td class="cell-secondary">
                        {{ \Carbon\Carbon::parse($user->USR_TAKEDOWN_AT)->timezone(config('farmspot.display_timezone'))->format('M d, Y h:i A') }}
                    </td>
                </tr>
            @endif

            <tr>
                <th>Registered</th>
                <td class="cell-secondary">
                    {{ \Carbon\Carbon::parse($user->USR_CREATED_AT)->timezone(config('farmspot.display_timezone'))->format('M d, Y h:i A') }}
                </td>
            </tr>

        </table>
    </div>
</div>

@if($farmer)
    <div class="panel mt-3">
        <div class="panel-header">
            <h5 class="panel-title">
                <i class="bi bi-shop"></i>
                Seller Profile
            </h5>
        </div>
        <div class="panel-body p-0">
            <table class="detail-table">

                <tr>
                    <th>Farmer ID</th>
                    <td><span class="id-cell">{{ $farmer->FMR_ID }}</span></td>
                </tr>

                <tr>
                    <th>Seller Mode</th>
                    <td>
                        @if($farmer->FMR_SELLER_MODE_ACTIVE)
                            <span class="badge badge-soft-success">Active</span>
                        @else
                            <span class="badge badge-soft-neutral">Off</span>
                        @endif
                    </td>
                </tr>

                @if($farmer->FMR_VERIFIED_AT)
                    <tr>
                        <th>Verified At</th>
                        <td class="cell-secondary">
                            {{ \Carbon\Carbon::parse($farmer->FMR_VERIFIED_AT)->timezone(config('farmspot.display_timezone'))->format('M d, Y h:i A') }}
                        </td>
                    </tr>
                @endif

            </table>
        </div>

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
                                    {{ \Carbon\Carbon::parse($farm->FRM_CREATED_AT)->timezone(config('farmspot.display_timezone'))->format('M d, Y h:i A') }}
                                </td>
                                <td>
                                    <div class="actions">
                                        <a href="{{ route('seller-requests.show', $farm->FRM_ID) }}"
                                           class="btn-icon" title="View farm">
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
    </div>
@endif

@endsection