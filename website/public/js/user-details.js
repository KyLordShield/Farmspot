const copyFeedback = document.querySelector('[data-copy-feedback]');
const profilePhoto = document.querySelector('[data-profile-photo]');
let feedbackTimeout;

if (profilePhoto) {
    const showPhoto = () => {
        profilePhoto.hidden = profilePhoto.naturalWidth === 0;
    };

    profilePhoto.addEventListener('load', showPhoto);
    showPhoto();
}

document.querySelectorAll('.user-details [data-copy-value]').forEach((button) => {
    button.addEventListener('click', async () => {
        try {
            await navigator.clipboard.writeText(button.dataset.copyValue);
            copyFeedback.textContent = button.dataset.copyLabel + ' copied.';
        } catch {
            copyFeedback.textContent = 'Could not copy. Select and copy the text manually.';
        }

        clearTimeout(feedbackTimeout);
        feedbackTimeout = setTimeout(() => {
            copyFeedback.textContent = '';
        }, 3500);
    });
});
