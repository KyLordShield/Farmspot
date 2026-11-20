<form method="POST" action="{{ route('reports.updateStatus', $report->RPT_ID) }}" class="mod-form" data-auto-spinner>
    @csrf
    @method('PATCH')
    <label for="select-status-{{ $report->RPT_ID }}" class="mod-label">Report status</label>
    <select class="form-select" name="status" id="select-status-{{ $report->RPT_ID }}" required>
        @foreach(['New', 'Reviewing', 'Resolved', 'Dismissed'] as $choice)
            <option @selected(old('status', $report->RPT_STATUS) === $choice)>{{ $choice }}</option>
        @endforeach
    </select>
    <div class="mod-row-actions">
        @if($inDialog ?? false)
            <button type="button" class="ld-button" data-mod-close autofocus>Cancel</button>
        @endif
        <button type="submit" class="ld-button ld-primary">Update status</button>
    </div>
</form>
