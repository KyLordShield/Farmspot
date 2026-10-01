<?php

namespace App\Notifications;

use App\Models\Report;
use App\Models\ReportAction;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * Tells the person who filed a report what a moderator did about it.
 *
 * Reporting was a one-way door: the buyer pressed submit and then heard nothing
 * at all, so a report that was reviewed, actioned and closed looked exactly
 * like one that was ignored. The app's notification bell is still a placeholder
 * (see AiTools), so nothing renders this yet — but the record exists and is
 * readable through GET /api/notifications, which means building the inbox screen
 * is a rendering job rather than a data-modelling one.
 */
class ReportActioned extends Notification
{
    use Queueable;

    public function __construct(
        public Report $report,
        public ReportAction $action,
        public bool $applied
    ) {
    }

    /**
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return ['database'];
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(object $notifiable): array
    {
        return [
            'kind' => $this->applied ? 'report_actioned' : 'report_action_undone',
            'title' => $this->applied
                ? 'We took action on your report'
                : 'A decision on your report was reversed',
            'body' => $this->applied
                ? $this->action->label().'.'
                : 'We undid '.$this->action->label().' after a second look.',
            'report_id' => $this->report->RPT_ID,
            'action' => $this->action->RAC_ACTION,
            'reversed' => ! $this->applied,
        ];
    }
}
