const userStatus = document.getElementById('USR_STATUS');
const reasonField = document.querySelector('[data-deactivation-reason]');

if (userStatus && reasonField) {
    const reasonInput = reasonField.querySelector('textarea');
    const syncReason = () => {
        const deactivating = userStatus.value === 'DEACTIVATED';
        reasonField.hidden = !deactivating;
        reasonInput.disabled = !deactivating;
        reasonInput.required = deactivating;
    };

    userStatus.addEventListener('change', syncReason);
    window.addEventListener('pageshow', syncReason);
    syncReason();
}
