<?php

namespace App\Http\Controllers;

use App\Models\Report;

class ReportController extends Controller
{
    public function index()
    {
        $reports = Report::orderBy('RPT_CREATED_AT', 'desc')
                         ->paginate(10);

        return view('reports', compact('reports'));
    }
}