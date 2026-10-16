<?php

namespace App\Http\Controllers;

use App\Models\AdminPlanner;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Schema;

/**
 * The admin's personal planner, driven from the dashboard.
 *
 * Notes (to-dos/reminders) and calendar events share one model; this controller
 * is the only thing that writes them. Every method resolves the row through the
 * signed-in admin's own id, so an id pulled from another tab or a crafted
 * request cannot read or change somebody else's note.
 *
 * Writes are real POST/PATCH/PUT/DELETE with CSRF like the rest of the panel,
 * and each one redirects back to the dashboard rather than returning JSON: the
 * planner is a small form, and a plain redirect keeps the page working with JS
 * off, which matters for the notes list in particular.
 */
class AdminPlannerController extends Controller
{
    /**
     * Create a note or an event.
     */
    public function store(Request $request)
    {
        $this->ensureReady();

        $type = $request->input('APL_TYPE') === AdminPlanner::TYPE_EVENT
            ? AdminPlanner::TYPE_EVENT
            : AdminPlanner::TYPE_NOTE;

        $rules = [
            'APL_TYPE' => ['required', 'in:NOTE,EVENT'],
            'APL_TITLE' => ['required', 'string', 'max:150'],
            'APL_BODY' => ['nullable', 'string', 'max:2000'],
            // An event without a date cannot be placed on the calendar, so it
            // is required there; a note without one is just an undated reminder.
            'APL_DATETIME' => [$type === AdminPlanner::TYPE_EVENT ? 'required' : 'nullable', 'date'],
        ];

        $validated = $request->validate($rules, [
            'APL_TITLE.required' => 'Give it a title first.',
            'APL_DATETIME.required' => 'Pick a date for the event.',
        ]);

        AdminPlanner::create([
            'APL_ID' => AdminPlanner::newId(),
            'USR_ID' => Auth::user()->USR_ID,
            'APL_TYPE' => $type,
            'APL_TITLE' => $validated['APL_TITLE'],
            'APL_BODY' => $validated['APL_BODY'] ?? null,
            'APL_DATETIME' => isset($validated['APL_DATETIME'])
                ? Carbon::parse($validated['APL_DATETIME'])
                : null,
            'APL_IS_DONE' => 0,
            'APL_CREATED_AT' => now(),
            'APL_UPDATED_AT' => null,
        ]);

        return redirect()->route('dashboard')
            ->with('success', $type === AdminPlanner::TYPE_EVENT ? 'Event added to your calendar.' : 'Note added.');
    }

    /**
     * Edit a note or event.
     */
    public function update(Request $request, string $id)
    {
        $this->ensureReady();

        $item = $this->ownedOrFail($id);

        $validated = $request->validate([
            'APL_TITLE' => ['required', 'string', 'max:150'],
            'APL_BODY' => ['nullable', 'string', 'max:2000'],
            'APL_DATETIME' => ['nullable', 'date'],
        ], [
            'APL_TITLE.required' => 'Give it a title first.',
        ]);

        $item->update([
            'APL_TITLE' => $validated['APL_TITLE'],
            'APL_BODY' => $validated['APL_BODY'] ?? null,
            'APL_DATETIME' => isset($validated['APL_DATETIME'])
                ? Carbon::parse($validated['APL_DATETIME'])
                : null,
            'APL_UPDATED_AT' => now(),
        ]);

        return redirect()->route('dashboard')
            ->with('success', $item->APL_TYPE === AdminPlanner::TYPE_EVENT ? 'Event updated.' : 'Note updated.');
    }

    /**
     * Tick a note off, or put it back.
     */
    public function toggle(string $id)
    {
        $this->ensureReady();

        $item = $this->ownedOrFail($id);

        $item->APL_IS_DONE = ! $item->APL_IS_DONE;
        $item->APL_UPDATED_AT = now();
        $item->save();

        return redirect()->route('dashboard')
            ->with('success', $item->APL_IS_DONE ? 'Marked as done.' : 'Note reopened.');
    }

    /**
     * Remove a note or event.
     */
    public function destroy(string $id)
    {
        $this->ensureReady();

        $item = $this->ownedOrFail($id);
        $wasEvent = $item->APL_TYPE === AdminPlanner::TYPE_EVENT;

        $item->delete();

        return redirect()->route('dashboard')
            ->with('success', $wasEvent ? 'Event removed.' : 'Note deleted.');
    }

    /**
     * The row, only if it belongs to the signed-in admin.
     *
     * Scoping on USR_ID rather than a bare findOrFail is what makes an id from
     * another admin (or one that does not exist) a 404 instead of an edit.
     */
    private function ownedOrFail(string $id): AdminPlanner
    {
        return AdminPlanner::forUser(Auth::user()->USR_ID)
            ->where('APL_ID', $id)
            ->firstOrFail();
    }

    /**
     * The planner table comes from a migration. If a deployment has not run it,
     * these endpoints do not exist rather than throwing a 500, matching the
     * dashboard's fallback.
     */
    private function ensureReady(): void
    {
        abort_unless(Schema::hasTable('admin_planner'), 404);
    }
}
