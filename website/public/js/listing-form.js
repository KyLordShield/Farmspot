const cropStatus = document.querySelector('#LST_STATUS');
const harvestField = document.querySelector('#listing-harvest-field');
const harvestDate = document.querySelector('#LST_HARVEST_DATE');

function syncHarvestDate() {
    const showHarvest = cropStatus.value === 'SOON_TO_HARVEST';
    harvestField.hidden = !showHarvest;
    harvestDate.disabled = !showHarvest;
    harvestDate.required = showHarvest;
}

if (cropStatus && harvestField && harvestDate) {
    cropStatus.addEventListener('change', syncHarvestDate);
    syncHarvestDate();
}

(function () {
    const section = document.querySelector('[data-listing-photos]');
    if (!section) return;
    const upload = document.getElementById('photos');
    const hint = document.getElementById('photos-hint');
    const removals = Array.from(section.querySelectorAll('[data-remove-photo]'));
    const limit = Number(section.dataset.photoLimit);
    const existing = Number(section.dataset.existingCount);
    function syncPhotos() {
        const removed = removals.filter(input => input.checked).length;
        const slots = Math.max(0, limit - existing + removed);
        const incoming = upload.files ? upload.files.length : 0;
        // Never silently discard files if a removal is unchecked after upload.
        upload.disabled = slots === 0 && incoming === 0;
        upload.setCustomValidity(incoming > slots
            ? `You can add ${slots} more photo${slots === 1 ? '' : 's'}. Select fewer files or remove another existing photo.` : '');
        hint.textContent = slots > 0
            ? `You can add up to ${slots} more photo${slots === 1 ? '' : 's'}, 5 MB each. Changes apply when you save.`
            : 'Photo limit reached. Select a photo to remove before adding another.';
    }
    removals.forEach(input => input.addEventListener('change', syncPhotos));
    upload.addEventListener('change', syncPhotos);
    syncPhotos();
})();
