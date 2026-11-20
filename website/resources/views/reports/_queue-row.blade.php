@php
    $date = $report->RPT_CREATED_AT ? \Carbon\Carbon::parse($report->RPT_CREATED_AT) : null;
    $subject = $report->targetLabel() ?: 'Not provided';
    $reporterName = $report->user?->USR_NAME ?? 'Not provided';
    $type = ['LISTING' => 'Crop listing', 'MESSAGE' => 'Message', 'FARMER' => 'Farmer', 'USER' => 'User'][$report->RPT_TARGET_TYPE] ?? $report->RPT_TARGET_TYPE;
@endphp
<tr data-mod-row>
    <td>
        @include('reports._id', ['id' => $report->RPT_ID])
        @if($report->RPT_FLAGGED_AT)
            <i class="bi bi-exclamation-triangle-fill mod-flag" title="Flagged by mass reporting" role="img" aria-label="Flagged by mass reporting"></i>
        @endif
    </td>
    <td><span class="mod-truncate" title="{{ $subject }}">{{ $subject }}</span><span class="mod-type">{{ $type }}</span></td>
    <td><span class="mod-truncate" title="{{ $report->reasonLabel() }}">{{ $report->reasonLabel() }}</span></td>
    <td><span class="mod-truncate" title="{{ $reporterName }}">{{ $reporterName }}</span></td>
    <td>
        @include('reports._status', ['status' => $report->RPT_STATUS])
        @if($report->live_actions_count)
            <small class="ld-muted d-block">{{ $report->live_actions_count }} {{ Str::plural('action', $report->live_actions_count) }} in force</small>
        @endif
    </td>
    <td>
        @if($date)
            <time class="ld-muted" datetime="{{ $date->toAtomString() }}" title="{{ $date->format('g:i A') }} · {{ $date->diffForHumans() }}">{{ $date->format('M j, Y') }} <span class="visually-hidden">at {{ $date->format('g:i A') }}, {{ $date->diffForHumans() }}</span></time>
        @else
            <em class="ld-muted">Not provided</em>
        @endif
    </td>
    <td>
        <div class="mod-row-actions">
            <a href="{{ route('reports.show', $report->RPT_ID) }}" class="ld-button" data-mod-view>View<span class="visually-hidden"> report {{ $report->RPT_ID }}</span></a>
            <button type="button" class="ld-button" aria-label="More actions for report {{ $report->RPT_ID }}"
                    aria-haspopup="dialog" data-mod-dialog="status-{{ $report->RPT_ID }}"><i class="bi bi-three-dots" aria-hidden="true"></i></button>
        </div>
        <dialog id="status-{{ $report->RPT_ID }}" class="mod-dialog" aria-labelledby="status-title-{{ $report->RPT_ID }}">
            <h2 id="status-title-{{ $report->RPT_ID }}">Update status for #{{ $report->RPT_ID }}</h2>
            @include('reports._status-form', ['inDialog' => true])
        </dialog>
    </td>
</tr>
