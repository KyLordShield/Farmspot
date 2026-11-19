<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

class ProfileListings
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! config('farmspot.profile_listings')) {
            return $next($request);
        }

        $connection = DB::connection();
        $queryLogWasEnabled = $connection->logging();
        $previousQueryCount = count($connection->getQueryLog());
        $connection->enableQueryLog();

        try {
            $startedAt = hrtime(true);
            $connection->getReadPdo();
            $connectedAt = hrtime(true);
            $response = $next($request);
            $finishedAt = hrtime(true);

            $queries = array_slice($connection->getQueryLog(), $previousQueryCount);
            $sqlMs = array_sum(array_column($queries, 'time'));
            $requestMs = ($finishedAt - $connectedAt) / 1e6;

            Log::info('listings.performance', [
                'status' => $response->getStatusCode(),
                'personalized' => $request->query('personalized') === '1',
                'db_connection_ms' => round(($connectedAt - $startedAt) / 1e6, 1),
                'sql_ms' => round($sqlMs, 1),
                'sql_queries' => count($queries),
                'other_laravel_ms' => round(max(0, $requestMs - $sqlMs), 1),
                'total_ms' => round(($finishedAt - $startedAt) / 1e6, 1),
            ]);

            return $response;
        } finally {
            if (! $queryLogWasEnabled) {
                $connection->disableQueryLog();
                $connection->flushQueryLog();
            }
        }
    }
}
