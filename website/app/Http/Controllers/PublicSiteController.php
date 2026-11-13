<?php

namespace App\Http\Controllers;

use App\Services\LegalPolicies;

class PublicSiteController extends Controller
{
    public function __invoke(LegalPolicies $policies)
    {
        $business = config('public_site');
        // Publish the business page once the operator's public details are configured.
        abort_unless(
            filled($business['business_name'])
            && filter_var($business['support_email'], FILTER_VALIDATE_EMAIL)
            && filled($business['support_phone']),
            404,
        );

        return view('public.farmspot', [
            'business' => $business,
            'price' => number_format(config('paymongo.amount') / 100, 2),
            'catalog' => $policies->catalog(),
        ]);
    }
}
