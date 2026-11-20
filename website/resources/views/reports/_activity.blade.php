@php
    $events = collect();
    if ($report->RPT_CREATED_AT) {
        $events->push(['Report submitted', $report->RPT_CREATED_AT, $report->user?->USR_NAME, null, null]);
    }
    if ($report->RPT_UPDATED_AT && $report->RPT_STATUS !== 'New') {
        $events->push(['Latest recorded status: '.$report->RPT_STATUS, $report->RPT_UPDATED_AT, null, null, null]);
    }
    foreach ($report->actions as $action) {
        $label = $actionLabels[$action->RAC_ACTION] ?? $action->RAC_ACTION;
        $events->push([$label, $action->RAC_APPLIED_AT, $action->moderator?->USR_NAME ?? 'an admin', $action->RAC_NOTE, $action->isLive() ? 'In force' : null]);
        if (!$action->isLive()) {
            $events->push(['Undone: '.$label, $action->RAC_REVERTED_AT, $action->revertedBy?->USR_NAME ?? 'an admin', null, null]);
        }
    }
@endphp
@if($events->isNotEmpty())
    <section class="ld-card">
        <h2>Activity</h2>
        <ol class="mod-timeline">
            @foreach($events->sortBy(fn ($event) => \Carbon\Carbon::parse($event[1])->format('U.u')) as [$event, $at, $actor, $note, $state])
                <li>
                    <strong>{{ $event }}</strong>
                    @if($state)<span class="mod-type">{{ $state }}</span>@endif
                    <div class="ld-muted">@include('reports._date', ['value' => $at]) @if($actor) · by {{ $actor }} @endif</div>
                    @if($note)<p class="mod-quote mt-2">{{ $note }}</p>@endif
                </li>
            @endforeach
        </ol>
    </section>
@endif
