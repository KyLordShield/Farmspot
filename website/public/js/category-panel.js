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
    // chosen tile. Centralised because three callers need it ΓÇö picking, loading
    // an edit, and clearing the form ΓÇö and letting them each half-do it is how
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
    // "none" over it ΓÇö losing the seller's icon on an unrelated name edit ΓÇö
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
        // redirect ΓÇö the moderator otherwise has to find the button again.
        var failed = modalEl.dataset.hasErrors === 'true';

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
