<?php

namespace App\Services;

use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * A small, no-key weather forecast for the admin dashboard.
 *
 * Source is Open-Meteo, which needs neither an API key nor an account. That
 * matters here: the widget is decoration on a personal dashboard, and a
 * missing/expired key would mean an admin staring at a broken panel. A
 * keyless source can only fail by being offline or throttled, both handled
 * below.
 *
 * Everything is best-effort. current() returns null on any problem — disabled
 * in config, network failure, a slow response, a shape we did not expect — and
 * the caller renders a quiet fallback. A weather widget must never be the
 * reason an admin cannot open their dashboard.
 *
 * Open-Meteo throttles the free endpoint by IP, and a cloud host (Render)
 * shares its egress IP with every other app on the box, so the API can hand us
 * a 429 through no fault of our own. The fetch is therefore cached, collapsed
 * to one call at a time, and backed off after a failure, and the last good
 * forecast is kept as a fallback so a throttle shows slightly old numbers
 * rather than an empty panel.
 */
class WeatherService
{
    /**
     * The forecast, or null when it could not be fetched.
     *
     * @return array{label:string, current:array, daily:array}|null
     */
    public function current(): ?array
    {
        $config = config('farmspot.weather', []);

        if (! ($config['enabled'] ?? false)) {
            return null;
        }

        $latitude = (float) ($config['latitude'] ?? 0);
        $longitude = (float) ($config['longitude'] ?? 0);
        $days = max(1, min((int) ($config['days'] ?? 4), 7));
        $cacheMinutes = max(5, (int) ($config['cache_minutes'] ?? 60));
        $backoffMinutes = max(1, (int) ($config['backoff_minutes'] ?? 10));
        $staleDays = max(1, (int) ($config['stale_days'] ?? 7));

        // The keys carry the location so pointing the widget at a different
        // area does not serve the previous area's cached forecast.
        $suffix = sprintf('%s:%s:%d', $latitude, $longitude, $days);
        $key = 'weather:'.$suffix;
        $lastGoodKey = 'weather:lastgood:'.$suffix;
        $backoffKey = 'weather:backoff:'.$suffix;

        // A fresh forecast, if we already have one.
        $cached = cache()->get($key);
        if (is_array($cached)) {
            $fresh = $this->format($cached, $config);
            if ($fresh !== null) {
                return $fresh;
            }
        }

        // We failed recently: an API that just told us to slow down does not
        // want another call yet. Show the last good forecast, or nothing.
        if (cache()->has($backoffKey)) {
            return $this->stale($lastGoodKey, $config);
        }

        // One fetch at a time. A burst of dashboard loads would otherwise all
        // miss the cache together and multiply an already-throttled call.
        $lock = cache()->lock('weather:fetch:'.$key, 15);
        if (! $lock->get()) {
            return $this->stale($lastGoodKey, $config);
        }

        try {
            $response = Http::withUserAgent($config['user_agent'] ?? 'FarmSpot/1.0')
                ->timeout(8)
                ->acceptJson()
                ->get($config['endpoint'], [
                    'latitude' => $latitude,
                    'longitude' => $longitude,
                    'timezone' => $config['timezone'] ?? 'auto',
                    // Current conditions plus a short daily outlook. Rain
                    // probability is the figure a farmer actually reads.
                    'current' => 'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,is_day',
                    'daily' => 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
                    'forecast_days' => $days,
                    'wind_speed_unit' => 'kmh',
                ]);

            $response->throw();

            $data = $response->json();
        } catch (\Throwable $e) {
            // Logged at warning rather than error: an unreachable or throttled
            // API is a cosmetic failure here, not something an admin acts on.
            // Setting the backoff also keeps this from logging on every reload.
            Log::warning('[weather] forecast fetch failed', ['message' => $e->getMessage()]);

            cache()->put($backoffKey, true, now()->addMinutes($backoffMinutes));

            return $this->stale($lastGoodKey, $config);
        } finally {
            $lock->release();
        }

        if (! is_array($data) || empty($data['current']) || empty($data['daily'])) {
            cache()->put($backoffKey, true, now()->addMinutes($backoffMinutes));

            return $this->stale($lastGoodKey, $config);
        }

        cache()->put($key, $data, now()->addMinutes($cacheMinutes));
        // Kept far longer than the fresh window: its only job is to be there
        // when Open-Meteo is not.
        cache()->put($lastGoodKey, $data, now()->addDays($staleDays));

        return $this->format($data, $config);
    }

    /**
     * The last successful forecast, if any, for when Open-Meteo is unreachable.
     * Returns null when there has never been a success, and the caller then
     * draws its quiet fallback.
     */
    private function stale(string $lastGoodKey, array $config): ?array
    {
        $data = cache()->get($lastGoodKey);

        return is_array($data) ? $this->format($data, $config) : null;
    }

    /**
     * Reshape the Open-Meteo payload into what the panel draws.
     */
    private function format(array $data, array $config): array
    {
        $current = $data['current'];
        $daily = $data['daily'];
        $code = (int) ($current['weather_code'] ?? 0);
        // Open-Meteo reports day/night, which lets the icon show a sun or a
        // moon for the same clear/partly-cloudy code.
        $isDay = (int) ($current['is_day'] ?? 1) === 1;

        $days = [];

        foreach (($daily['time'] ?? []) as $index => $date) {
            $dayCode = (int) ($daily['weather_code'][$index] ?? 0);

            $days[] = [
                'date' => $date,
                'label' => CarbonImmutable::parse($date)->format('D'),
                'code' => $dayCode,
                'condition' => $this->condition($dayCode),
                'icon' => $this->icon($dayCode),
                'max' => $this->round($daily['temperature_2m_max'][$index] ?? null),
                'min' => $this->round($daily['temperature_2m_min'][$index] ?? null),
                'rain' => isset($daily['precipitation_probability_max'][$index])
                    ? (int) $daily['precipitation_probability_max'][$index]
                    : null,
            ];
        }

        return [
            'label' => $config['label'] ?? 'Current location',
            'current' => [
                'code' => $code,
                'condition' => $this->condition($code),
                'icon' => $this->icon($code, $isDay),
                'temperature' => $this->round($current['temperature_2m'] ?? null),
                'apparent' => $this->round($current['apparent_temperature'] ?? null),
                'humidity' => isset($current['relative_humidity_2m']) ? (int) $current['relative_humidity_2m'] : null,
                'wind' => $this->round($current['wind_speed_10m'] ?? null),
                'precipitation' => $this->round($current['precipitation'] ?? null),
            ],
            'daily' => $days,
        ];
    }

    private function round($value): ?int
    {
        return is_numeric($value) ? (int) round((float) $value) : null;
    }

    /**
     * A Meteocons icon slug for a WMO weather code.
     *
     * The slugs name real files in public/images/weather (basmilius'
     * weather-icons, MIT). Clear-ish and showery codes have separate day and
     * night art, hence the $isDay flag; the codes are the standard
     * Open-Meteo/WMO set and anything unexpected falls back to a neutral
     * cloud rather than a broken image.
     */
    private function icon(int $code, bool $isDay = true): string
    {
        $d = $isDay ? 'day' : 'night';

        return match (true) {
            in_array($code, [0, 1], true) => "clear-$d",
            in_array($code, [2], true) => "partly-cloudy-$d",
            in_array($code, [3], true) => "overcast-$d",
            in_array($code, [45, 48], true) => "fog-$d",
            in_array($code, [51, 53, 55], true) => 'drizzle',
            in_array($code, [56, 57, 66, 67], true) => 'sleet',
            in_array($code, [61, 63, 65], true) => 'rain',
            in_array($code, [71, 73, 75, 77], true) => 'snow',
            in_array($code, [80, 81, 82], true) => "partly-cloudy-$d-rain",
            in_array($code, [85, 86], true) => 'snow',
            in_array($code, [95], true) => "thunderstorms-$d",
            in_array($code, [96, 99], true) => "thunderstorms-$d-rain",
            default => 'cloudy',
        };
    }

    /**
     * A short human label for a WMO weather code.
     */
    private function condition(int $code): string
    {
        return match (true) {
            $code === 0 => 'Clear sky',
            $code === 1 => 'Mainly clear',
            $code === 2 => 'Partly cloudy',
            $code === 3 => 'Overcast',
            in_array($code, [45, 48], true) => 'Fog',
            in_array($code, [51, 53, 55], true) => 'Drizzle',
            in_array($code, [56, 57, 66, 67], true) => 'Freezing rain',
            in_array($code, [61, 63, 65], true) => 'Rain',
            in_array($code, [71, 73, 75, 77], true) => 'Snow',
            in_array($code, [80, 81, 82], true) => 'Rain showers',
            in_array($code, [85, 86], true) => 'Snow showers',
            in_array($code, [95, 96, 99], true) => 'Thunderstorm',
            default => 'Unknown',
        };
    }
}
