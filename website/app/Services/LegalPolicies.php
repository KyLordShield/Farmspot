<?php

namespace App\Services;

use App\Models\LegalAcceptance;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class LegalPolicies
{
    private ?array $loaded = null;

    public function catalog(): array
    {
        if ($this->loaded !== null) {
            return $this->loaded;
        }
        $data = config('legal.catalog') ?? json_decode(file_get_contents(resource_path('legal/policies.json')), true, 512, JSON_THROW_ON_ERROR);
        $ready = (filter_var($data['contact_email'] ?? '', FILTER_VALIDATE_EMAIL) || filled($data['contact_text'] ?? null))
            && filled($data['operator_name'] ?? null) && filled($data['retention_policy'] ?? null) && filled($data['refund_policy'] ?? null);
        $data['published'] = ($data['published'] ?? false) === true && (bool) $ready;

        return $this->loaded = $data;
    }

    public function validateRegistration(Request $request): bool
    {
        if (! $request->hasAny(['legal_version', 'terms_accepted', 'privacy_acknowledged'])) {
            return false;
        }
        $this->requirePublished();
        $request->validate([
            'legal_version' => ['required', Rule::in([$this->catalog()['version']])],
            'terms_accepted' => ['required', 'accepted'],
            'privacy_acknowledged' => ['required', 'accepted'],
        ], ['legal_version.in' => 'These policies have changed. Update the app and review the current version before accepting.']);

        return true;
    }

    public function requirePublished(): void
    {
        if (! $this->catalog()['published']) {
            throw ValidationException::withMessages(['legal_version' => 'These policies are drafts. No acceptance is required or recorded yet.']);
        }
    }

    public function record(string $userId, array $ids): void
    {
        $catalog = $this->catalog();
        $documents = collect($catalog['documents'])->keyBy('id');
        foreach ($ids as $id) {
            LegalAcceptance::firstOrCreate(['USR_ID' => $userId, 'DOCUMENT' => $id, 'VERSION' => $catalog['version']], [
                'ID' => (string) Str::uuid(),
                'CONTENT' => json_encode($documents[$id], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'CONTENT_HASH' => hash('sha256', json_encode($documents[$id], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)),
                'ACTION' => $id === 'privacy' ? 'ACKNOWLEDGED' : ($id === 'verification' ? 'CONSENTED' : 'AGREED'),
                'ACCEPTED_AT' => now(),
            ]);
        }
    }
}
