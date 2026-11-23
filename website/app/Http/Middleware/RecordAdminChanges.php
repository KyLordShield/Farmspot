<?php

namespace App\Http\Middleware;

use App\Services\AdminAudit;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RecordAdminChanges
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->isMethodSafe() || $request->user()?->USR_ROLE !== 'ADMIN') {
            return $next($request);
        }

        $audit = new AdminAudit($request, $request->user());
        $request->attributes->set('admin.audit', $audit);
        $audit->seedTarget();
        try {
            return $next($request);
        } finally {
            $audit->flush();
            $request->attributes->remove('admin.audit');
        }
    }
}
