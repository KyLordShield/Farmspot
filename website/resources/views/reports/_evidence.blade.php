@if($report->RPT_TARGET_TYPE == 'LISTING')
    <section class="ld-card">
        <h2>Reported Crop Listing</h2>
        <dl class="ld-fields">
                <div>
                    <dt>Listing ID</dt>
                    <dd>@if($report->listing) @include('reports._id', ['id' => $report->listing->LST_ID]) @else Deleted since @endif</dd>
                </div>
                <div>
                    <dt>Categories</dt>
                    <dd>{{ $report->listing?->category?->CAT_NAME ?? '-' }}</dd>
                </div>
                <div>
                    <dt>Crop Name</dt>
                    <dd>{{ $report->listing?->LST_CROP_ICON ?: '-' }}</dd>
                </div>
                <div>
                    <dt>Status</dt>
                    <dd>
                        @php
                            $reportedListingStatus = $report->listing?->LST_STATUS ?? null;
                        @endphp
                        @if($reportedListingStatus === 'AVAILABLE_NOW')
                            <span class="badge badge-soft-success">Available Now</span>
                        @elseif($reportedListingStatus === 'SOON_TO_HARVEST')
                            <span class="badge badge-soft-warning">Soon to Harvest</span>
                        @elseif($reportedListingStatus)
                            <span class="badge badge-soft-neutral">Not Available</span>
                        @else
                            -
                        @endif
                    </dd>
                </div>
                <div>
                    <dt>Farm</dt>
                    <dd>{{ $report->listing?->farm?->FRM_NAME ?? '-' }}</dd>
                </div>
                <div>
                    <dt>Seller</dt>
                    <dd>{{ $report->listing?->farmer?->buyer?->user?->USR_NAME ?? '-' }}</dd>
                </div>
                <div>
                    <dt>Renewals</dt>
                    <dd>
                        @if((int) ($report->listing?->LST_RENEWAL_COUNT ?? 0) > 0)
                            <span class="badge badge-soft-warning">
                                {{ (int) $report->listing->LST_RENEWAL_COUNT }} time(s)
                            </span>
                            <span class="cell-secondary ms-2">
                                Last {{ $report->listing->LST_LAST_RENEWED_AT ?: 'unknown' }}
                            </span>
                        @else
                            <span class="badge badge-soft-neutral">Never renewed</span>
                        @endif
                    </dd>
                </div>
        </dl>
    </section>
@elseif($report->RPT_TARGET_TYPE == 'MESSAGE')
    <section class="ld-card">
        <h2>Reported Message</h2>
        <dl class="ld-fields">
                <div>
                    <dt>Message ID</dt>
                    <dd>@include('reports._id', ['id' => $report->RPT_TARGET_ID])</dd>
                </div>
                <div>
                    <dt>Sent by</dt>
                    <dd>
                        {{ $report->message?->sender?->USR_NAME ?? 'Unknown' }}
                        @include('reports._id', ['id' => $report->message?->USR_ID ?? ''])
                    </dd>
                </div>
                <div>
                    <dt>Sent</dt>
                    <dd class="cell-secondary">{{ $report->message ? \Carbon\Carbon::parse($report->message->MSG_CREATED_AT)->format('M d, Y h:i A') : '-' }}</dd>
                </div>
                <div>
                    <dt>Message</dt>
                    {{-- Escaped by {{ }}. A reported message is attacker-chosen
                         text, so it must never be rendered as markup. --}}
                    <dd style="white-space: pre-wrap;">{{ $report->message?->MSG_CONTENT ?? 'Message deleted' }}</dd>
                </div>
                {{-- Kept as context: was this a live sale or an approach about
                     something the buyer had already dismissed? --}}
                <div>
                    <dt>About listing</dt>
                    <dd>
                        @if($report->listing)
                            @include('reports._id', ['id' => $report->listing->LST_ID])
                            {{ $report->listing->farm?->FRM_NAME ?? '' }}
                        @else
                            -
                        @endif
                    </dd>
                </div>
        </dl>
    </section>
@else
    {{-- FARMER and USER both name a person. --}}
    @php
        $accused = $report->RPT_TARGET_TYPE == 'FARMER'
            ? $report->farmer?->buyer?->user
            : $report->reportedUser;
    @endphp
    <section class="ld-card">
        <h2>Reported {{ $report->RPT_TARGET_TYPE == 'FARMER' ? 'Farmer' : 'User' }}</h2>
        @if($accused)
            <div class="mod-person">
                <span class="mod-avatar" aria-hidden="true">
                    {{ Str::of($accused->USR_NAME ?? '?')->trim()->explode(' ')->filter()->take(2)->map(fn ($part) => Str::substr($part, 0, 1))->implode('') }}
                    @if(filled($accused->USR_PHOTO_PATH))
                        <img src="{{ $accused->USR_PHOTO_PATH }}" alt="" data-mod-profile-photo hidden>
                    @endif
                </span>
                <a class="mod-link" href="{{ route('users.show', $accused->USR_ID) }}">View user profile</a>
            </div>
        @endif
        <dl class="ld-fields">
                <div>
                    <dt>Name</dt>
                    <dd>{{ $accused?->USR_NAME ?? 'Unknown' }}</dd>
                </div>
                <div>
                    <dt>Email</dt>
                    <dd>{{ $accused?->USR_EMAIL ?? '-' }}</dd>
                </div>
                <div>
                    <dt>Mobile</dt>
                    <dd>{{ $accused?->USR_MOBILE_NUMBER ?? '-' }}</dd>
                </div>
                <div>
                    <dt>User ID</dt>
                    <dd>@include('reports._id', ['id' => $accused?->USR_ID])</dd>
                </div>
                @if($report->RPT_TARGET_TYPE == 'FARMER')
                    <div>
                        <dt>Farmer ID</dt>
                        <dd>@include('reports._id', ['id' => $report->RPT_TARGET_ID])</dd>
                    </div>
                    <div>
                        <dt>Account status</dt>
                        <dd>
                            @php
                                $accusedStatus = $accused?->USR_STATUS ?? null;
                            @endphp
                            @if($accusedStatus === 'ACTIVE')
                                <span class="badge badge-soft-success">Active</span>
                            @elseif($accusedStatus === 'PENDING_VERIFICATION')
                                <span class="badge badge-soft-warning">Pending Verification</span>
                            @elseif($accusedStatus)
                                <span class="badge badge-soft-neutral">Deactivated</span>
                            @else
                                -
                            @endif
                        </dd>
                    </div>
                    <div>
                        <dt>Selling mode</dt>
                        <dd>{{ (int) ($report->farmer?->FMR_SELLER_MODE_ACTIVE ?? 0) === 1 ? 'Active' : 'Inactive' }}</dd>
                    </div>
                @endif
        </dl>
    </section>
@endif
