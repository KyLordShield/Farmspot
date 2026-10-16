<?php

namespace App\Services;

use App\Models\Report;

/**
 * Flags a target when enough different people have reported it.
 *
 * The one rule that matters: this only sets a timestamp that the admin queue
 * shows. It never takes anything down and never suspends anyone. A counter
 * that acted on its own would let any group of buyers bury a competitor by
 * filing reports against them, so the threshold is a "a human should look at
 * this now" signal rather than an enforcement step.
 *
 * What counts is deliberately narrow and easy to reason about:
 *
 *   - One target, by its exact (type, id) pair. Listing reports are counted per
 *     listing and person reports per reported account, and the two are never
 *     added together. A listing with ten reports is one thing; the farm behind
 *     it having one report is another.
 *   - Distinct reporters only. Ten reports from one angry buyer is one voice,
 *     not ten, so a single person refiling cannot trip the threshold on their
 *     own.
 *   - Open reports only. Resolved and Dismissed rows are finished business and
 *     should not keep a target flagged after the queue dealt with it.
 *   - No time window. A window needs a scheduler and would quietly un-flag a
 *     target between runs; for a pilot, all open reports counting is both
 *     simpler and more honest. See config/farmspot.php.
 *
 * It sets RPT_FLAGGED_AT at most once per target. Once any open report for the
 * target carries the timestamp, later reports leave it alone, so a moderator is
 * not re-alerted on every new complaint about something they have already been
 * told about. When the queue resolves those reports the column goes back to
 * null with the status change, so a genuinely new wave can flag it again.
 */
class MassReportService
{
    /**
     * The default threshold, referenced by view composers that need a fallback
     * while config is loading, or just to keep a single number.
     */
    public const THRESHOLD = 10;

    /**
     * Run the check for the target of $report. Returns true if this call was the
     * one that flagged the target.
     */
    public function flagIfThresholdReached(Report $report): bool
    {
        $threshold = $this->threshold();

        // Nothing to do when the feature is switched off (a zero or negative
        // threshold would otherwise flag every single report).
        if ($threshold < 1) {
            return false;
        }

        $openReports = Report::query()
            ->forSameTarget($report)
            ->open();

        // Already flagged by an earlier report. This is the "set once" guard:
        // the admin has been told, and being told again adds noise, not signal.
        if ((clone $openReports)->whereNotNull('RPT_FLAGGED_AT')->exists()) {
            return false;
        }

        // DISTINCT USR_ID, not a row count: the same person filing five times is
        // still one reporter.
        $distinctReporters = (clone $openReports)->distinct()->count('USR_ID');

        if ($distinctReporters < $threshold) {
            return false;
        }

        // Stamp every open report for the target, not just the newest one, so
        // whichever row a moderator opens first shows the flag. whereNull keeps
        // the "set once" property even if two requests race here.
        $openReports->whereNull('RPT_FLAGGED_AT')->update(['RPT_FLAGGED_AT' => now()]);

        return true;
    }

    /**
     * The configured threshold, read defensively.
     *
     * A typo in the environment value must not make the check throw on every
     * report a buyer files; falling back to the default keeps reporting working
     * and the queue simply flags at the documented number.
     */
    public function threshold(): int
    {
        $configured = config('farmspot.report_threshold', 10);

        return is_numeric($configured) ? (int) $configured : 10;
    }

    /**
     * How many targets currently sit in the mass-report alert list.
     *
     * The alerts page groups open flagged reports down to one row per
     * (subject, id) pair, so this is the same number a moderator reads as
     * "alerts" there — how many separate piles-on there are, not how many
     * reports sit behind them. Ten reports about one account is one mass
     * report, which is why this is a distinct-target count rather than
     * reusing the open flagged report count.
     *
     * Open rows only: an alert the queue has already dealt with clears
     * RPT_FLAGGED_AT and stops being reported, same as everywhere else.
     */
    public function openFlaggedTargetCount(): int
    {
        $row = Report::query()
            ->open()
            ->whereNotNull('RPT_FLAGGED_AT')
            ->selectRaw("COUNT(DISTINCT CONCAT(RPT_TARGET_TYPE, ':', RPT_TARGET_ID)) as total")
            ->first();

        return (int) ($row->total ?? 0);
    }
}
