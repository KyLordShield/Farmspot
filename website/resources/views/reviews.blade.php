@extends('layouts.app')

@section('title', 'Reviews')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Reviews</h1>
        <div class="page-desc">Moderation — buyer reviews of crop listings</div>
    </div>
</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

@if(session('error'))
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        {{ session('error') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="stat-grid">

    <div class="stat-card">
        <div class="stat-icon tint-green">
            <i class="bi bi-star"></i>
        </div>
        <div>
            <div class="stat-value">{{ $visibleCount }}</div>
            <div class="stat-label">Visible to buyers</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-slate">
            <i class="bi bi-eye-slash"></i>
        </div>
        <div>
            <div class="stat-value">{{ $hiddenCount }}</div>
            <div class="stat-label">Hidden</div>
        </div>
    </div>

</div>

{{-- Shown once rather than buried in the report: a moderator reading this page
     needs to know that a hidden review is not just off the list, it is out of
     the listing's star average too, and that hiding is reversible while
     deleting is not offered at all. --}}
<div class="alert alert-info">
    <i class="bi bi-info-circle"></i>
    Hidden reviews are removed from the listing page and no longer count toward
    its star average. Hiding is reversible. Review text cannot be edited or
    deleted from here — that stays with the buyer who wrote it.
</div>

<div class="panel">

    {{-- Filters: free-text search plus two dropdowns. Any combination applies,
         and every one is remembered through withQueryString() so paging and
         hiding a row do not drop the moderator's filters. --}}
    <form method="GET" action="{{ route('reviews') }}" class="filter-bar">
        <div class="filter-grow">
            <div class="input-group">
                <span class="input-group-text">
                    <i class="bi bi-search"></i>
                </span>
                <input
                    type="text"
                    name="search"
                    value="{{ request('search') }}"
                    class="form-control"
                    placeholder="Search reviewer, crop, farm, comment or review id">
                <button class="btn btn-farm" type="submit">
                    Search
                </button>
            </div>
        </div>

        <div class="filter-auto">
            <select name="status" class="form-select" onchange="this.form.submit()">
                <option value="">All Status</option>
                <option value="VISIBLE" {{ request('status') == 'VISIBLE' ? 'selected' : '' }}>Visible</option>
                <option value="HIDDEN" {{ request('status') == 'HIDDEN' ? 'selected' : '' }}>Hidden</option>
            </select>
        </div>

        <div class="filter-auto">
            <select name="rating" class="form-select" onchange="this.form.submit()">
                <option value="">All Ratings</option>
                @for($star = 5; $star >= 1; $star--)
                    <option value="{{ $star }}" {{ (int) request('rating') === $star ? 'selected' : '' }}>
                        {{ $star }} star{{ $star > 1 ? 's' : '' }}
                    </option>
                @endfor
            </select>
        </div>
    </form>

    <div class="table-responsive">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Review</th>
                    <th>Reviewer</th>
                    <th>Listing</th>
                    <th>Rating</th>
                    <th>Comment</th>
                    <th>Status</th>
                    <th>Date</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>

            @forelse($reviews as $review)

                <tr>
                    <td><span class="id-cell">{{ $review->LRV_ID }}</span></td>
                    <td>
                        {{-- First name + last initial only, same as the public
                             API. The full name is not rendered anywhere on this
                             page either, so the admin view cannot become the
                             place that leaks it. --}}
                        <div>{{ $review->reviewerName() }}</div>
                        <div class="cell-faint">Buyer</div>
                    </td>
                    <td>
                        <div>{{ $review->listing?->LST_CROP_ICON ?? '-' }}</div>
                        <div class="cell-faint">
                            {{ $review->listing?->category?->CAT_NAME ?? '-' }}
                            @if($review->listing?->farm?->FRM_NAME)
                                &middot; {{ $review->listing->farm->FRM_NAME }}
                            @endif
                        </div>
                        <div class="cell-faint">
                            <span class="id-cell">{{ $review->LST_ID }}</span>
                        </div>
                    </td>
                    <td>
                        {{-- The raw stars, not a rounded average: a moderator
                             judging a one-star review needs to see that it is
                             one star. --}}
                        <span class="tint-amber badge" title="{{ $review->LRV_RATING }} of 5">
                            @for($star = 1; $star <= 5; $star++)
                                <i class="bi {{ $star <= $review->LRV_RATING ? 'bi-star-fill' : 'bi-star' }}"></i>
                            @endfor
                        </span>
                        <div class="cell-faint">{{ $review->LRV_RATING }} / 5</div>
                    </td>
                    <td class="cell-secondary">
                        @if($review->LRV_COMMENT)
                            {{ \Illuminate\Support\Str::limit($review->LRV_COMMENT, 90) }}
                        @else
                            <span class="cell-faint">No comment</span>
                        @endif
                    </td>
                    <td>
                        @if($review->isHidden())
                            <span class="badge badge-soft-neutral">
                                <i class="bi bi-eye-slash"></i> Hidden
                            </span>
                        @else
                            <span class="badge badge-soft-success">
                                <i class="bi bi-eye"></i> Visible
                            </span>
                        @endif
                    </td>
                    <td class="cell-faint">
                        {{ \Carbon\Carbon::parse($review->LRV_CREATED_AT)->format('M d, Y h:i A') }}
                    </td>
                    <td>
                        <div class="actions">
                            <form method="POST"
                                  action="{{ route('reviews.toggleStatus', $review->LRV_ID) }}"
                                  class="d-inline">
                                @csrf
                                @method('PATCH')
                                {{-- Carry the active filters through the action so
                                     the redirect lands back in the same filtered
                                     view instead of an unfiltered page one. --}}
                                @foreach(['search', 'status', 'rating', 'page'] as $param)
                                    @if(request($param))
                                        <input type="hidden" name="{{ $param }}" value="{{ request($param) }}">
                                    @endif
                                @endforeach
                                <button type="submit"
                                        class="btn-icon {{ $review->isHidden() ? '' : 'danger' }} confirm"
                                        title="{{ $review->isHidden() ? 'Show again' : 'Hide from buyers' }}">
                                    <i class="bi {{ $review->isHidden() ? 'bi-eye' : 'bi-eye-slash' }}"></i>
                                </button>
                            </form>
                        </div>
                    </td>
                </tr>

            @empty

                <tr>
                    <td colspan="8">
                        <div class="empty-state">
                            <i class="bi bi-star empty-icon"></i>
                            <p>No reviews found.</p>
                            @if(request('search') || request('status') || request('rating'))
                                <a href="{{ route('reviews') }}" class="btn btn-farm btn-sm">Clear filters</a>
                            @endif
                        </div>
                    </td>
                </tr>

            @endforelse

            </tbody>
        </table>
    </div>

    <div class="panel-body pt-0 pb-3">
        {{ $reviews->links() }}
    </div>

</div>

@endsection