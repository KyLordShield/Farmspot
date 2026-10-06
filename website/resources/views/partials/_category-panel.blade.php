{{--
    Crop category CRUD, opened from the Listings page.

    A modal rather than its own page: a category is only ever looked at next to the
    listings it classifies, and the app builds its filter chips and its add-crop form
    from these same rows. Adding a nav item for what is normally five rows would put
    it one click further from the thing it changes.

    One form does both create and update. Two would mean two copies of the same
    fields, and the update copy is the one that rots: fields get added to create and
    silently stop being editable. The form's action and method are rewritten by the
    script below instead.

    The delete button is disabled for a category that anything still points at,
    which is the honest thing to show — see CropCategory::usageCounts(). The server
    refuses the same delete again regardless, because a disabled button is a UI
    promise and not a guarantee.
--}}
{{-- Blade includes a compiled file rather than extending the controller, so a
     `use` from the caller does not reach here and an unqualified CropCategory
     would resolve to the global namespace and fail. --}}
@php
    use App\Models\CropCategory;
@endphp

{{--
    Material Icons, so the picker shows the real glyph rather than a lookalike from
    another icon set. A Bootstrap stand-in would be a guess: Bootstrap has `spa` and
    `grass` but not `eco` or `agriculture`, so three of the eight would render as
    whatever happened to be nearest. The names in CropCategory::ICONS are Material
    names because the app renders them with Flutter's Icons.*.

    Font only, no external JS. The admin panel already loads Bootstrap from a CDN,
    so this does not introduce a new kind of dependency.
--}}
@push('styles')
<link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
@endpush

<style>
    /* The picker grid. Wraps rather than scrolls: eight options is a small block,
       and a picker that needs scrolling hides half the choice behind a gesture. */
    .category-icon-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(52px, 1fr));
        gap: 0.375rem;
        padding: 0.375rem;
        border: 1px solid var(--line, #dee2e6);
        border-radius: 0.5rem;
        background: #fff;
    }

    .category-icon-grid.is-invalid {
        border-color: var(--red, #dc3545);
    }

    .category-icon-option {
        display: flex;
        align-items: center;
        justify-content: center;
        aspect-ratio: 1 / 1;
        border: 1px solid transparent;
        border-radius: 0.375rem;
        background: transparent;
        color: #6c757d;
        font-size: 1.5rem;
        line-height: 1;
        cursor: pointer;
        transition: background-color .12s ease, border-color .12s ease, color .12s ease;
    }

    .category-icon-option .material-icons {
        font-size: 1.5rem;
    }

    .category-icon-option:hover {
        background: var(--green-bg, #e8f3ec);
        color: var(--green, #0f4a1c);
    }

    /* The selected state is a border as well as a background, so it survives a
       hover and stays visible for anyone who cannot pick the tint apart. */
    .category-icon-option[data-selected] {
        border-color: var(--green, #0f4a1c);
        background: var(--green-bg, #e8f3ec);
        color: var(--green, #0f4a1c);
    }

    .category-icon-option:focus-visible {
        outline: 2px solid var(--green, #0f4a1c);
        outline-offset: 1px;
    }
</style>

<div class="modal fade"
     id="categoryPanel"
     tabindex="-1"
     aria-labelledby="categoryPanelTitle"
     aria-hidden="true">
    <div class="modal-dialog modal-lg modal-dialog-centered modal-dialog-scrollable">
        <div class="modal-content">

            <div class="modal-header">
                <h5 class="modal-title" id="categoryPanelTitle">
                    <i class="bi bi-tags me-1"></i> Crop Categories
                </h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>

            <div class="modal-body">

                {{-- These are the only two things a failed create or update can come
                     back with. Both reopen the panel, because the whole point of the
                     redirect is that the row is now on the Listings page and the
                     moderator would otherwise have to find the button again. --}}
                @if($errors->any())
                    <div class="alert alert-danger" role="alert">
                        <div class="fw-semibold mb-1">Could not save the category.</div>
                        <ul class="mb-0 ps-3">
                            @foreach($errors->all() as $error)
                                <li>{{ $error }}</li>
                            @endforeach
                        </ul>
                    </div>
                @endif

                {{-- data-* on the form is how the script knows where it is: an empty
                     editing id means create, otherwise it is the CAT_ID being updated.
                     old() is what makes this survive the redirect. --}}
                <form method="POST"
                      action="{{ route('categories.store') }}"
                      id="categoryForm"
                      data-store-action="{{ route('categories.store') }}"
                      data-update-action="{{ route('categories.update', ['id' => '__ID__']) }}">

                    @csrf
                    <input type="hidden" name="_editing" id="categoryEditing" value="{{ old('_editing', '') }}">

                    <div class="d-flex align-items-start justify-content-between gap-2 mb-3">
                        <div>
                            <div class="panel-title mb-0" id="categoryFormTitle">New category</div>
                            <div class="panel-sub" id="categoryFormSub">
                                The app builds its filter chips and add-crop form from these rows.
                            </div>
                        </div>
                        <button type="button" class="btn btn-ghost btn-sm d-none" id="categoryCancelEdit">
                            Cancel edit
                        </button>
                    </div>

                    <div class="row g-3">

                        <div class="col-md-5">
                            <label class="form-label" for="categoryName">
                                Name <span class="text-danger">*</span>
                            </label>
                            <input type="text"
                                   class="form-control @error('CAT_NAME') is-invalid @enderror"
                                   id="categoryName"
                                   name="CAT_NAME"
                                   maxlength="100"
                                   value="{{ old('CAT_NAME') }}"
                                   placeholder="e.g. Leafy Vegetables"
                                   required>
                            @error('CAT_NAME')
                                <div class="invalid-feedback">{{ $message }}</div>
                            @enderror
                            <div class="form-text">Shown on every listing card and chip in the app.</div>
                        </div>

                        {{-- The id is displayed here but never submitted. It is a
                             foreign key into listing, insight and trend with
                             ON UPDATE CASCADE, and the app keys its cached
                             categories off it, so a moderator editing a name does
                             not get to rewrite what the history points at. --}}
                        <div class="col-md-3">
                            <label class="form-label" for="categoryIdDisplay">ID</label>
                            <input type="text"
                                   class="form-control"
                                   id="categoryIdDisplay"
                                   value=""
                                   placeholder="generated on save"
                                   readonly>
                            <div class="form-text">Generated on save. Never changes afterwards.</div>
                        </div>

                        {{-- A grid of pictures rather than a text field, because the
                             value is a Material icon name and nobody memorises those.
                             The admin clicks the leaf; the hidden field below carries
                             the name the app needs. --}}
                        <div class="col-md-4">
                            <label class="form-label">Icon</label>

                            <div class="category-icon-grid @error('CAT_ICON') is-invalid @enderror"
                                 id="categoryIconGrid"
                                 role="radiogroup"
                                 aria-label="Category icon">

                                <button type="button"
                                        class="category-icon-option"
                                        role="radio"
                                        aria-checked="false"
                                        data-icon=""
                                        title="No icon"
                                        @if(old('CAT_ICON') === null) data-selected @endif>
                                    <i class="bi bi-dash-lg"></i>
                                </button>

                                @foreach(CropCategory::ICONS as $iconName => $iconLabel)
                                    <button type="button"
                                            class="category-icon-option"
                                            role="radio"
                                            aria-checked="false"
                                            data-icon="{{ $iconName }}"
                                            title="{{ $iconLabel }} ({{ $iconName }})"
                                            @if(old('CAT_ICON') === $iconName) data-selected @endif>
                                        <span class="material-icons">{{ $iconName }}</span>
                                    </button>
                                @endforeach

                            </div>

                            {{-- The name is submitted, not typed. Kept in the DOM (and
                                 readable) so a moderator can see exactly what was stored
                                 rather than having to trust the picture. --}}
                            <input type="hidden" name="CAT_ICON" id="categoryIcon" value="{{ old('CAT_ICON') }}">

                            <div class="form-text">
                                The icon buyers see in the app. Optional —
                                <span class="font-monospace" id="categoryIconName">{{ old('CAT_ICON') ?: 'none' }}</span>
                            </div>

                            @error('CAT_ICON')
                                <div class="invalid-feedback d-block">{{ $message }}</div>
                            @enderror
                        </div>

                        <div class="col-12">
                            <label class="form-label" for="categoryDescription">Description</label>
                            <textarea class="form-control @error('CAT_DESCRIPTION') is-invalid @enderror"
                                      id="categoryDescription"
                                      name="CAT_DESCRIPTION"
                                      rows="2"
                                      maxlength="300"
                                      placeholder="Which crops belong in this category?">{{ old('CAT_DESCRIPTION') }}</textarea>
                            @error('CAT_DESCRIPTION')
                                <div class="invalid-feedback">{{ $message }}</div>
                            @enderror
                            <div class="form-text">
                                Shown when a seller picks this category. Keep it to examples.
                            </div>
                        </div>

                    </div>

                    <div class="mt-3">
                        <button type="submit" class="btn btn-farm">
                            <i class="bi bi-check-lg me-1"></i>
                            <span id="categorySubmitLabel">Add category</span>
                        </button>
                    </div>

                </form>

                <hr class="my-4">

                <div class="panel-title mb-1">Existing categories</div>
                <div class="panel-sub mb-3">
                    A category in use cannot be deleted — its ID is a foreign key into listings
                    and analytics rows.
                </div>

                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Name</th>
                                <th>Icon</th>
                                <th>In use by</th>
                                <th style="width: 1%;"></th>
                            </tr>
                        </thead>
                        <tbody>
                        @forelse($categories as $category)
                            @php
                                // Summed rather than read off listings_count alone:
                                // insight and trend also carry CAT_ID, and a category
                                // with no listings but recorded trends is still undeletable.
                                $usage = ($category->listings_count ?? 0)
                                    + ($category->insights_count ?? 0)
                                    + ($category->trends_count ?? 0);
                            @endphp
                            <tr>
                                <td>
                                    <span class="id-cell">{{ $category->CAT_ID }}</span>
                                </td>
                                <td>{{ $category->CAT_NAME }}</td>
                                <td class="cell-secondary">
                                    @if($category->CAT_ICON)
                                        <code>{{ $category->CAT_ICON }}</code>
                                    @else
                                        <span class="text-muted">—</span>
                                    @endif
                                </td>
                                <td>
                                    @if($usage > 0)
                                        <span class="badge badge-soft-neutral">{{ $usage }}</span>
                                    @else
                                        <span class="badge badge-soft-success">Unused</span>
                                    @endif
                                </td>
                                <td>
                                    <div class="actions">
                                        <button type="button"
                                                class="btn-icon"
                                                title="Edit"
                                                data-category-edit
                                                data-id="{{ $category->CAT_ID }}"
                                                data-name="{{ $category->CAT_NAME }}"
                                                data-icon="{{ $category->CAT_ICON }}"
                                                data-description="{{ $category->CAT_DESCRIPTION }}">
                                            <i class="bi bi-pencil"></i>
                                        </button>

                                        {{-- A real form rather than a JS-built one: it carries
                                             CSRF and the method override like every other
                                             destructive action in the panel, the filter
                                             fields below are rendered server-side, and it
                                             still deletes if the script never runs.
                                             Disabled, not hidden: "why can't I delete
                                             this" is answered by the button being
                                             visibly there and saying so, rather than by
                                             a delete action that quietly does not
                                             appear. --}}
                                        <form method="POST"
                                              action="{{ route('categories.destroy', $category->CAT_ID) }}"
                                              data-confirm-title="Delete category?"
                                              data-confirm-text="Delete the category &quot;{{ $category->CAT_NAME }}&quot;?"
                                              data-confirm-tone="danger">
                                            @csrf
                                            @method('DELETE')
                                            {{-- The Listings page filters ride along so saving or
                                                 deleting a category does not throw away the
                                                 moderator's search box and status filter. --}}
                                            @foreach(['search', 'category', 'status', 'page'] as $carry)
                                                @if(request($carry))
                                                    <input type="hidden"
                                                           name="{{ $carry }}"
                                                           value="{{ request($carry) }}">
                                                @endif
                                            @endforeach

                                            <button type="submit"
                                                    class="btn-icon danger {{ $usage > 0 ? 'disabled' : '' }}"
                                                    title="{{ $usage > 0
                                                        ? 'Used by '.$usage.' row(s) — move or remove them first'
                                                        : 'Delete category' }}"
                                                    @if($usage > 0) disabled @endif>
                                                <i class="bi bi-trash"></i>
                                            </button>
                                        </form>
                                    </div>
                                </td>
                            </tr>
                        @empty
                            <tr>
                                <td colspan="5">
                                    <div class="empty-state">
                                        <i class="bi bi-tags empty-icon"></i>
                                        <p>No categories yet.</p>
                                    </div>
                                </td>
                            </tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>

            </div>

            <div class="modal-footer">
                <button type="button" class="btn btn-farm" data-bs-dismiss="modal">Done</button>
            </div>

        </div>
    </div>
</div>

@push('scripts')
<script>
    (function () {
        var modalEl = document.getElementById('categoryPanel');
        if (!modalEl) {
            return;
        }

        var form = document.getElementById('categoryForm');
        var editing = document.getElementById('categoryEditing');
        var storeAction = form.getAttribute('data-store-action');
        var updateAction = form.getAttribute('data-update-action');
        var idDisplay = document.getElementById('categoryIdDisplay');
        var title = document.getElementById('categoryFormTitle');
        var sub = document.getElementById('categoryFormSub');
        var submitLabel = document.getElementById('categorySubmitLabel');
        var cancelEdit = document.getElementById('categoryCancelEdit');
        var nameField = document.getElementById('categoryName');
        var iconField = document.getElementById('categoryIcon');
        var iconGrid = document.getElementById('categoryIconGrid');
        var iconName = document.getElementById('categoryIconName');
        var descriptionField = document.getElementById('categoryDescription');
        var iconOptions = Array.prototype.slice.call(
            iconGrid.querySelectorAll('[data-icon]')
        );

        // Reflect a chosen icon into the hidden field the form submits, and mark the
        // chosen tile. Centralised because three callers need it — picking, loading
        // an edit, and clearing the form — and letting them each half-do it is how
        // the grid and the submitted value end up disagreeing.
        function selectIcon(value) {
            iconField.value = value || '';
            iconName.textContent = value || 'none';

            iconOptions.forEach(function (option) {
                var isChosen = option.getAttribute('data-icon') === (value || '');
                if (isChosen) {
                    option.setAttribute('data-selected', '');
                } else {
                    option.removeAttribute('data-selected');
                }
                option.setAttribute('aria-checked', isChosen ? 'true' : 'false');
            });
        }

        // A row written before this panel existed may hold a name the eight no longer
        // include. Rather than showing nothing selected and then quietly saving
        // "none" over it — losing the seller's icon on an unrelated name edit —
// an extra tile is added for that exact value so saving preserves it.
        function selectIconKeepingUnknown(value) {
            var known = iconOptions.some(function (option) {
                return option.getAttribute('data-icon') === (value || '');
            });

            if (value && !known) {
                iconOptions.push(addLegacyTile(value));
            }

            selectIcon(value);
        }

        function addLegacyTile(value) {
            var tile = document.createElement('button');
            tile.type = 'button';
            tile.className = 'category-icon-option';
            tile.setAttribute('role', 'radio');
            tile.setAttribute('aria-checked', 'false');
            tile.setAttribute('data-icon', value);
            tile.title = value + ' (saved earlier, not one of the offered icons)';

            var glyph = document.createElement('span');
            glyph.className = 'material-icons';
            glyph.textContent = value;
            tile.appendChild(glyph);

            iconGrid.appendChild(tile);
            return tile;
        }

        // methodOverride is what turns this POST into a PUT. It exists as a real
        // input so the browser has nothing extra to do and the form still submits
        // without JavaScript having to reach into FormData.
        function methodField() {
            var el = form.querySelector('input[name="_method"]');
            if (!el) {
                el = document.createElement('input');
                el.type = 'hidden';
                el.name = '_method';
                form.appendChild(el);
            }
            return el;
        }

        function resetToCreate() {
            editing.value = '';
            form.action = storeAction;
            form.querySelector('input[name="_method"]')?.remove();
            form.reset();
            idDisplay.value = '';
            // form.reset() does not clear a hidden field's value set from a prior
            // edit, so the grid is reset explicitly rather than inheriting it.
            selectIcon('');
            title.textContent = 'New category';
            sub.textContent = 'The app builds its filter chips and add-crop form from these rows.';
            submitLabel.textContent = 'Add category';
            cancelEdit.classList.add('d-none');
            nameField.removeAttribute('readonly');
        }

        function editCategory(button) {
            var id = button.getAttribute('data-id');

            editing.value = id;
            form.action = updateAction.replace('__ID__', id);
            methodField().value = 'PUT';

            idDisplay.value = id;
            title.textContent = 'Edit category ' + id;
            sub.textContent = 'Changing the name updates every card that uses it.';
            submitLabel.textContent = 'Save changes';
            cancelEdit.classList.remove('d-none');

            nameField.value = button.getAttribute('data-name') || '';
            selectIconKeepingUnknown(button.getAttribute('data-icon'));
            descriptionField.value = button.getAttribute('data-description') || '';

            nameField.focus();
        }

        modalEl.addEventListener('show.bs.modal', function () {
            // A failed save re-renders this page with the modal closed and the
            // fields repopulated from old(). Reopening is the whole point of the
            // redirect — the moderator otherwise has to find the button again.
            var failed = {{ $errors->any() ? 'true' : 'false' }};

            if (failed) {
                var failedId = editing.value;
                if (failedId) {
                    form.action = updateAction.replace('__ID__', failedId);
                    methodField().value = 'PUT';
                    idDisplay.value = failedId;
                    title.textContent = 'Edit category ' + failedId;
                    submitLabel.textContent = 'Save changes';
                    cancelEdit.classList.remove('d-none');
                } else {
                    resetToCreate();
                }
            }
        });

        modalEl.addEventListener('click', function (event) {
            var editButton = event.target.closest('[data-category-edit]');
            if (editButton) {
                editCategory(editButton);
                return;
            }

            var iconButton = event.target.closest('[data-icon]');
            if (iconButton) {
                selectIcon(iconButton.getAttribute('data-icon'));
            }
        });

        if (cancelEdit) {
            cancelEdit.addEventListener('click', resetToCreate);
        }

        // Applied once on load so the tile matching the current value is marked
        // before anything is clicked, and so an errored save comes back with the
        // choice the moderator made still showing.
        selectIconKeepingUnknown(iconField.value);

        // Populated once so an errored edit shows the row it was editing, then
        // cleared so the next open of the panel starts clean.
        if (editing.value) {
            form.action = updateAction.replace('__ID__', editing.value);
            methodField().value = 'PUT';
            idDisplay.value = editing.value;
            title.textContent = 'Edit category ' + editing.value;
            submitLabel.textContent = 'Save changes';
            cancelEdit.classList.remove('d-none');
        }
    })();
</script>
@endpush