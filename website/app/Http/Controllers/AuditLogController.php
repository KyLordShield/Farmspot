<?php

namespace App\Http\Controllers;

use App\Models\AuditLog;
use Illuminate\Http\Request;

class AuditLogController extends Controller
{
    public function index(Request $request)
    {
        $filters = $request->validate([
            'search' => ['nullable', 'string', 'max:150'],
            'admin' => ['nullable', 'string', 'max:6'],
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d'],
        ]);
        $logs = AuditLog::query()
            ->leftJoin('user as actor', 'actor.USR_ID', '=', 'audit_log.USR_ID')
            ->select('audit_log.*', 'actor.USR_NAME as current_actor_name')
            ->when($filters['search'] ?? null, function ($query, $search) {
                $query->where(function ($query) use ($search) {
                    foreach (['AUD_ACTION', 'AUD_DETAILS', 'AUD_TARGET_ID', 'AUD_ACTOR_NAME', 'actor.USR_NAME'] as $field) {
                        $query->orWhere($field, 'like', '%'.$search.'%');
                    }
                });
            })
            ->when($filters['admin'] ?? null, fn ($query, $admin) => $query->where('audit_log.USR_ID', $admin))
            ->when($filters['from'] ?? null, fn ($query, $date) => $query->where('AUD_CREATED_AT', '>=', $date.' 00:00:00'))
            ->when($filters['to'] ?? null, fn ($query, $date) => $query->where('AUD_CREATED_AT', '<=', $date.' 23:59:59'))
            ->orderByDesc('AUD_CREATED_AT')->orderByDesc('AUD_ID')
            ->paginate(25)->withQueryString();

        $admins = AuditLog::query()->whereNotNull('audit_log.USR_ID')
            ->leftJoin('user as actor', 'actor.USR_ID', '=', 'audit_log.USR_ID')
            ->select('audit_log.USR_ID', 'actor.USR_NAME')->distinct()->orderBy('actor.USR_NAME')->get();

        return view('audit.index', compact('logs', 'admins', 'filters'));
    }
}
