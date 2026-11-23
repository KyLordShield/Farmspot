@extends('layouts.app')
@section('title', 'Audit Log')
@push('styles')
<style>
    .audit-change-value { white-space: pre-wrap; overflow-wrap: anywhere; min-width: 0; max-height: 16rem; overflow-y: auto; margin: 0; }
    .audit-change-card { min-width: 0; overflow-wrap: anywhere; }
    .audit-change-modal .modal-body { overscroll-behavior: contain; }
    .audit-change-modal .modal-title { overflow-wrap: anywhere; }
</style>
@endpush
@section('content')
<div class="container-fluid py-4">
    <div class="mb-4">
        <h1 class="h3 fw-bold">Audit Log</h1>
        <p class="text-muted">Recorded administrator changes, newest first. Select View changes to see the details.</p>
    </div>
    <form method="GET" action="{{ route('audit-log') }}" class="card card-body mb-4">
        <div class="row g-3 align-items-end">
            <div class="col-lg-4"><label class="form-label" for="audit-search">Search</label><input id="audit-search" name="search" class="form-control" maxlength="150" value="{{ $filters['search'] ?? '' }}" placeholder="Action, admin, or record ID"></div>
            <div class="col-lg-2"><label class="form-label" for="audit-admin">Administrator</label><select id="audit-admin" name="admin" class="form-select"><option value="">All administrators</option>@foreach($admins as $admin)<option value="{{ $admin->USR_ID }}" @selected(($filters['admin'] ?? '') === $admin->USR_ID)>{{ $admin->USR_NAME ?: $admin->USR_ID }}</option>@endforeach</select></div>
            <div class="col-lg-2"><label class="form-label" for="audit-from">From</label><input type="date" id="audit-from" name="from" class="form-control" value="{{ $filters['from'] ?? '' }}"></div>
            <div class="col-lg-2"><label class="form-label" for="audit-to">To</label><input type="date" id="audit-to" name="to" class="form-control" value="{{ $filters['to'] ?? '' }}"></div>
            <div class="col-lg-2 d-flex gap-2"><button class="btn btn-success" type="submit">Filter</button><a class="btn btn-outline-secondary" href="{{ route('audit-log') }}">Reset</a></div>
        </div>
    </form>
    <p class="small text-muted">{{ number_format($logs->total()) }} recorded {{ Str::plural('entry', $logs->total()) }}. Passwords, private planner text, and file locations are redacted.</p>
    <div class="card">
        <div class="table-responsive">
            <table class="table align-middle mb-0">
                <thead class="table-light"><tr><th scope="col" class="ps-3">When</th><th scope="col">Administrator</th><th scope="col">Action</th><th scope="col">Record</th><th scope="col">Changes</th></tr></thead>
                <tbody>
                @forelse($logs as $log)
                    <tr>
                        <td class="ps-3 text-nowrap"><time datetime="{{ $log->AUD_CREATED_AT->toIso8601String() }}">{{ $log->AUD_CREATED_AT->format('M j, Y g:i:s A') }}</time><div class="small text-muted">{{ config('app.timezone') }}</div></td>
                        <td>{{ $log->AUD_ACTOR_NAME ?: $log->current_actor_name ?: 'Former administrator' }}<div class="small text-muted">{{ $log->USR_ID }}</div></td>
                        <td><span class="badge text-bg-light">{{ Str::ucfirst(strtolower(str_replace('_', ' ', $log->AUD_ACTION))) }}</span><div class="small mt-1">{{ $log->AUD_DETAILS }}</div></td>
                        <td>{{ Str::ucfirst(strtolower(str_replace('_', ' ', $log->AUD_TARGET_TYPE ?? ''))) }}<div class="small text-muted">{{ $log->AUD_TARGET_ID ?: '—' }}</div></td>
                        <td>
                            @if($log->AUD_CHANGES)
                                <button type="button" class="btn btn-sm btn-outline-success text-nowrap" data-bs-toggle="modal" data-bs-target="#audit-changes-{{ $log->AUD_ID }}" aria-label="View changes for audit entry {{ $log->AUD_ID }}">View changes</button>
                                <div class="small text-muted mt-1">{{ count($log->AUD_CHANGES) }} {{ Str::plural('field', count($log->AUD_CHANGES)) }}</div>
                            @else
                                <span class="small text-muted">Historical entry</span>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="5" class="text-center text-muted py-5">No recorded changes match these filters.</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
    </div>
    <div class="mt-4">{{ $logs->links() }}</div>
</div>
@endsection

{{-- Render dialogs outside the scrolling table and the main layout wrapper. --}}
@push('scripts')
@foreach($logs as $log)
    @if($log->AUD_CHANGES)
        <div class="modal fade audit-change-modal" id="audit-changes-{{ $log->AUD_ID }}" tabindex="-1" aria-labelledby="audit-changes-title-{{ $log->AUD_ID }}" aria-hidden="true">
            <div class="modal-dialog modal-lg modal-dialog-centered modal-dialog-scrollable modal-fullscreen-sm-down">
                <div class="modal-content">
                    <div class="modal-header">
                        <h2 class="modal-title fs-5" id="audit-changes-title-{{ $log->AUD_ID }}">{{ Str::ucfirst(strtolower(str_replace('_', ' ', $log->AUD_ACTION))) }}</h2>
                        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close changes"></button>
                    </div>
                    <div class="modal-body">
                        <div class="bg-light rounded p-3 mb-3 audit-change-card">
                            <p class="fw-semibold mb-1">{{ $log->AUD_ACTOR_NAME ?: $log->current_actor_name ?: 'Former administrator' }}</p>
                            <p class="small text-muted mb-1">{{ $log->AUD_CREATED_AT->format('M j, Y g:i:s A') }} · {{ config('app.timezone') }}</p>
                            <p class="small mb-1">{{ $log->AUD_DETAILS }}</p>
                            <p class="small mb-0">{{ Str::ucfirst(strtolower(str_replace('_', ' ', $log->AUD_TARGET_TYPE ?? ''))) }} · {{ $log->AUD_TARGET_ID ?: '—' }} · {{ count($log->AUD_CHANGES) }} {{ Str::plural('field', count($log->AUD_CHANGES)) }}</p>
                        </div>
                        @foreach($log->AUD_CHANGES as $field => $change)
                            <section class="border rounded p-3 mb-3 audit-change-card" aria-labelledby="audit-field-{{ $log->AUD_ID }}-{{ $loop->index }}">
                                <h3 class="fs-6 fw-semibold mb-3" id="audit-field-{{ $log->AUD_ID }}-{{ $loop->index }}">{{ Str::ucfirst(strtolower(str_replace('_', ' ', Str::after($field, '_')))) }}</h3>
                                <div class="row g-3">
                                    @foreach(['before' => 'Before', 'after' => 'After'] as $key => $label)
                                        @php
                                            $value = $change[$key] ?? null;
                                            $display = is_bool($value) ? ($value ? 'Yes' : 'No') : (is_array($value) ? json_encode($value, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) : $value);
                                        @endphp
                                        <div class="col-12 col-md-6">
                                            <h4 class="small text-muted fw-semibold">{{ $label }}</h4>
                                            <div class="bg-light border rounded p-2 audit-change-value" tabindex="0" role="region" aria-label="{{ $label }} {{ Str::ucfirst(strtolower(str_replace('_', ' ', Str::after($field, '_')))) }}">{{ $display === null ? '—' : ($display === '' ? '(empty)' : $display) }}</div>
                                        </div>
                                    @endforeach
                                </div>
                            </section>
                        @endforeach
                        <p class="small text-muted mb-0">Passwords, private planner text, and file locations are redacted.</p>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                    </div>
                </div>
            </div>
        </div>
    @endif
@endforeach
@endpush
