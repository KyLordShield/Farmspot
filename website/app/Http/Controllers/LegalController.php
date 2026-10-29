<?php

namespace App\Http\Controllers;

use App\Models\LegalAcceptance;
use App\Services\LegalPolicies;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class LegalController extends Controller
{
    public function index(LegalPolicies $policies)
    {
        return response()->json($policies->catalog());
    }

    public function show(string $document, LegalPolicies $policies)
    {
        $catalog = $policies->catalog();
        $page = collect($catalog['documents'])->firstWhere('id', $document);
        abort_unless($page, 404);

        return view('legal', ['catalog' => $catalog, 'document' => $page]);
    }

    public function acceptances(Request $request)
    {
        return response()->json(['acceptances' => LegalAcceptance::where('USR_ID', $request->user()->USR_ID)->get(['DOCUMENT', 'VERSION', 'ACTION', 'ACCEPTED_AT'])]);
    }

    public function accept(Request $request, LegalPolicies $policies)
    {
        $policies->requirePublished();
        $catalog = $policies->catalog();
        $data = $request->validate([
            'legal_version' => ['required', Rule::in([$catalog['version']])],
            'documents' => ['required', 'array', 'min:1', 'max:4'],
            'documents.*' => ['required', 'string', 'distinct', Rule::in(array_column($catalog['documents'], 'id'))],
            'accepted' => ['required', 'accepted'],
        ]);
        DB::transaction(fn () => $policies->record($request->user()->USR_ID, $data['documents']));

        return response()->json(['message' => 'Your choice was recorded.']);
    }
}
