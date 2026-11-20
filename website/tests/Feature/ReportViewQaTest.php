<?php

namespace Tests\Feature;

use App\Models\Report;
use App\Models\User;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\ViewErrorBag;
use Tests\TestCase;

class ReportViewQaTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        view()->share('errors', new ViewErrorBag);
        $this->actingAs(new User(['USR_NAME' => 'QA Admin']));
    }

    public function test_empty_queue_renders_summary_cards_and_empty_state(): void
    {
        $html = view('reports', [
            'reports' => new LengthAwarePaginator([], 0, 10),
            'totalReports' => 0,
            'flaggedTargetCount' => 0,
            'counts' => collect(),
        ])->render();

        foreach (['Total reports', 'Mass reported', 'Resolved', 'New', 'There are no reports to review yet.'] as $text) {
            $this->assertStringContainsString($text, $html);
        }
    }

    public function test_report_details_render_without_related_accounts(): void
    {
        $report = new Report([
            'RPT_ID' => '594167',
            'RPT_TARGET_ID' => 'QA0001',
            'RPT_TARGET_TYPE' => 'USER',
            'RPT_STATUS' => 'Reviewing',
            'RPT_REASON' => 'Review requested',
            'RPT_CREATED_AT' => '2026-10-16 10:30:00',
            'RPT_DETAILS' => 'Pagsusi sa report 🌱 · تمت المراجعة',
        ]);
        $report->setRelation('user', null);
        $report->setRelation('reportedUser', null);
        $report->setRelation('actions', collect());

        $html = view('reports.show', [
            'report' => $report,
            'reporterCount' => 0,
            'actionLabels' => Report::ACTION_LABELS,
            'options' => [],
            'blocked' => ['The reported account is unavailable.'],
        ])->render();

        foreach (['Report #594167', 'Reviewing', 'Oct 16, 2026', $report->RPT_DETAILS, 'Activity', 'The reported account is unavailable.'] as $text) {
            $this->assertStringContainsString($text, $html);
        }
    }
}
