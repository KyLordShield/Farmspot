<?php

namespace App\Http\Controllers;

use App\Models\CropCategory;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Admin CRUD for crop categories, from the panel on the Listings page.
 *
 * A category is not cosmetic. Its CAT_ID is a foreign key into three tables —
 * listing, insight and trend — and the app builds its filter chips, its add-crop
 * form and its ranking affinity straight off this table, so the five rows that
 * ship today are really the vocabulary of the whole marketplace.
 *
 * Two rules follow from that, and they are the reason this controller is not just
 * four generated methods:
 *
 * 1. CAT_ID is generated, never typed. It is char(6) with no default and it is an
 *    ON UPDATE CASCADE foreign key target, so letting a moderator invent one by
 *    hand risks a six-character string that looks fine and collides with an
 *    existing id. The id is also not editable afterwards: renaming a category is
 *    a name change, and a changing id would rewrite rows in three tables.
 *
 * 2. A category in use cannot be deleted, and the refusal says how many rows
 *    block it. Left to the database this is a 500 with an SQLSTATE on screen; the
 *    panel greys the button out beforehand, and this is the backstop behind it.
 */
class CropCategoryController extends Controller
{
    public function store(Request $request)
    {
        $validated = $request->validate($this->rules());

        CropCategory::create([
            'CAT_ID' => $this->generateId(),
            'CAT_NAME' => $validated['CAT_NAME'],
            'CAT_ICON' => $validated['CAT_ICON'] ?? null,
            'CAT_DESCRIPTION' => $validated['CAT_DESCRIPTION'] ?? null,
        ]);

        return $this->backToListings($request, 'Category created.');
    }

    public function update(Request $request, $id)
    {
        $category = CropCategory::where('CAT_ID', $id)->firstOrFail();

        $validated = $request->validate($this->rules($category));

        // CAT_ID is intentionally absent from this array. The categories the app
        // caches and the filter chips it builds are keyed by it, and the feed's
        // category affinity reads it out of search_log filters, so an editable
        // id would quietly change what history points at.
        $category->update([
            'CAT_NAME' => $validated['CAT_NAME'],
            'CAT_ICON' => $validated['CAT_ICON'] ?? null,
            'CAT_DESCRIPTION' => $validated['CAT_DESCRIPTION'] ?? null,
        ]);

        return $this->backToListings($request, 'Category updated.');
    }

    public function destroy(Request $request, $id)
    {
        $category = CropCategory::where('CAT_ID', $id)->firstOrFail();

        $usage = $category->usageCounts();
        $total = array_sum($usage);

        if ($total > 0) {
            // The listing count is named first because it is the one a moderator
            // can act on. The other two are analytics rows that nobody would think
            // to go looking for, which is exactly why saying "12 rows" without
            // naming them would read as a bug.
            $parts = [];

            if ($usage['listings'] > 0) {
                $parts[] = $usage['listings'].' listing'.($usage['listings'] === 1 ? '' : 's');
            }

            if ($usage['insights'] > 0) {
                $parts[] = $usage['insights'].' analytics row'.($usage['insights'] === 1 ? '' : 's');
            }

            if ($usage['trends'] > 0) {
                $parts[] = $usage['trends'].' trend row'.($usage['trends'] === 1 ? '' : 's');
            }

            return $this->backToListings(
                $request,
                '"'.$category->CAT_NAME.'" cannot be deleted while it is still used by '
                    .implode(' and ', $parts).'. Move or remove those first.',
                'error'
            );
        }

        $category->delete();

        return $this->backToListings($request, 'Category deleted.');
    }

    /**
     * Validation shared by create and update.
     *
     * CAT_NAME is unique at the database level (UX_CATEGORY_NAME) so the rule has
     * to be here too — without it a duplicate is a raw 1062 constraint violation,
     * and the category list is exactly where a moderator will retype an existing
     * name by accident.
     *
     * ignore() on update is what makes saving an unchanged name work. Every other
     * field of the form is being rewritten on save, and the category being saved
     * is of course still holding that name. The column has to be named alongside
     * the value: this table's primary key is CAT_ID, and Laravel's ignore() assumes
     * an `id` column unless told otherwise — which fails on the first update with
     * "Unknown column 'id' in 'where clause'".
     *
     * The icon is a closed set on purpose, and the list is CropCategory::ICONS.
     * See there for why a free-text field was the wrong call.
     */
    private function rules(?CropCategory $category = null): array
    {
        return [
            'CAT_NAME' => [
                'required',
                'string',
                'max:100',
                Rule::unique('crop_category', 'CAT_NAME')
                    ->ignore($category?->CAT_ID, 'CAT_ID'),
            ],
            // Rule::in against the eight names the app can actually draw, rather
            // than a loose token regex. The app falls back to guessing from the
            // category name for an icon it does not recognise, so a free-text
            // value that is merely well-formed still renders as the wrong thing.
            // Rejecting it here is what turns a silent mistake into a message.
            'CAT_ICON' => ['nullable', 'string', Rule::in(array_keys(CropCategory::ICONS))],
            'CAT_DESCRIPTION' => ['nullable', 'string', 'max:300'],
        ];
    }

    /**
     * A six-character id in the same shape as the ones already in the table.
     *
     * The existing ids are all short uppercase mnemonics (LEAFVG, ROOTCP), which is
     * deliberate: they show up in query strings, logs and admin screenshots.
     * Str::random(6) is mixed-case hex, so it is uppercased for consistency, and
     * the collision loop is not optional because the id is the primary key and a
     * duplicate throws rather than overwriting.
     */
    private function generateId(): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (CropCategory::where('CAT_ID', $id)->exists());

        return $id;
    }

    /**
     * Come back to the Listings page, keeping the filters that were on screen.
     *
     * The panel lives inside the Listings page rather than on a page of its own, so
     * a category edit that redirected to a bare /listings would also throw away the
     * search box and status filter the moderator had set up, and their next action
     * would be on a different list than the one they were looking at.
     *
     * Only the four known filter keys are carried back, and only when they are
     * actually set, so a crafted link cannot use this to append arbitrary query
     * parameters to the redirect.
     */
    private function backToListings(Request $request, string $message, string $key = 'success')
    {
        return redirect()
            ->route('listings', array_filter($request->only(['search', 'category', 'status', 'page'])))
            ->with($key, $message);
    }
}