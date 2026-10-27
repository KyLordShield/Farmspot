# Simple crop categories and automatic suggestions

The starter catalog is now Vegetables (`LEAFVG`), Fruits (`FRUITS`), Rice, Corn &
Grains (`GRAINS`), Root Crops (`ROOTCP`), Herbs & Spices (`HRBSPC`), and Other Crops
(`OTHERS`). Category IDs are internal; users see names and examples.

The seller enters a crop first. Common English and local aliases suggest a
category immediately on the device, including tomato/tomatoes/kamatis,
banana/saging, corn/mais, ginger/luya and sweet potato/kamote. The seller can
override the choice. Unknown names select Other Crops and can be classified
manually. Matching uses whole crop words or phrases inside the title: "Apple fresh 50kg"
and "Cabbage Cheap For Sale" are recognized. A title naming crops from multiple
categories requires a manual choice. Substrings such as apple inside applewood
do not match.

`website/config/crop_categories.php` is the shared dictionary. The public category
API includes each category's aliases as `crop_names`, including singular/plural
forms. This avoids per-keystroke network calls and duplicate dictionaries in
Flutter. Add aliases there as new crops become common. Custom admin-created
categories without dictionary entries remain available for manual selection.

API clients can omit `category_id` when sending a crop name; create/edit then
assigns the recognized category or Other Crops. An explicit valid category is
preserved. If the suggested category has been deleted, the API asks the seller
to choose an available category instead of producing a database error.

## Existing records

`2026_10_27_000002_simplify_crop_categories.php` takes a database snapshot of old
category rows and original links in `crop_category_change_backup`, then updates
category assignments in one transaction. It does not recreate listings.

- Existing crop names determine their new group. Unrecognized/test crop names
  go to Other Crops.
- Fruit Vegetables, Leafy Vegetables and Legumes report links merge into
  Vegetables. Herbs & Spices and Root Crops report links keep their categories.
- Listing IDs, farm ownership, dates, descriptions, photos and reviews remain
  unchanged. Historical report text/data is retained; its category link changes.
- Migration rollback restores original category rows and original links. It
  retains newly added categories if newer records already reference them.

Apply the migration on each environment; the local database and hosting database
are separate. Refresh the admin page and restart/reopen the app form afterward
to discard previously loaded category lists.

## Input limits

Both Add and Edit forms enforce 40 characters for crop names, 100 for farm names,
1,000 for crop/farm descriptions, 100 for barangay names, and 255 for addresses.
The API independently validates these limits and returns readable field errors.
Registration and profile addresses use the same 255-character limit already
enforced by the server. Existing stored text is not silently shortened.
