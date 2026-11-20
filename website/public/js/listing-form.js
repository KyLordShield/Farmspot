const cropStatus = document.querySelector('#LST_STATUS');
const harvestField = document.querySelector('#listing-harvest-field');
const harvestDate = document.querySelector('#LST_HARVEST_DATE');

function syncHarvestDate() {
    const showHarvest = cropStatus.value === 'SOON_TO_HARVEST';
    harvestField.hidden = !showHarvest;
    harvestDate.disabled = !showHarvest;
    harvestDate.required = showHarvest;
}

cropStatus.addEventListener('change', syncHarvestDate);
syncHarvestDate();
