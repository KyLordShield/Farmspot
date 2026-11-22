const moderationPage = document.querySelector('.mod-page');
const copyFeedback = moderationPage.querySelector('[data-mod-copy-feedback]');
let feedbackTimer;

moderationPage.querySelectorAll('[data-mod-profile-photo]').forEach((photo) => {
    const update = () => { photo.hidden = photo.naturalWidth === 0; };
    photo.addEventListener('load', update);
    photo.addEventListener('error', () => { photo.hidden = true; });
    update();
});

moderationPage.querySelectorAll('[data-mod-filter]').forEach((control) => {
    control.addEventListener('change', () => control.form.requestSubmit());
});

moderationPage.addEventListener('click', async (event) => {
    const target = event.target;
    const copy = target.closest('[data-mod-copy]');
    if (copy) {
        try {
            await navigator.clipboard.writeText(copy.dataset.modCopy);
            copyFeedback.textContent = 'ID copied.';
        } catch {
            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(copy.querySelector('span'));
            selection.removeAllRanges();
            selection.addRange(range);
            copyFeedback.textContent = 'ID selected for copying.';
        }
        clearTimeout(feedbackTimer);
        feedbackTimer = setTimeout(() => { copyFeedback.textContent = ''; }, 3500);
        return;
    }

    const group = target.closest('[data-mod-group]');
    if (group) {
        const rows = document.getElementById(group.dataset.modGroup);
        rows.hidden = !rows.hidden;
        group.setAttribute('aria-expanded', String(!rows.hidden));
        return;
    }

    const opener = target.closest('[data-mod-dialog]');
    if (opener) {
        document.getElementById(opener.dataset.modDialog).showModal();
        return;
    }

    const close = target.closest('[data-mod-close]');
    if (close) {
        close.closest('dialog').close();
        return;
    }

    const dismiss = target.closest('[data-mod-dismiss]');
    if (dismiss) {
        dismiss.closest('.mod-toast').remove();
        return;
    }

    const row = target.closest('[data-mod-row]');
    if (row && !target.closest('a, button, input, select, label, dialog') && !window.getSelection()?.toString()) {
        row.querySelector('[data-mod-view]').click();
    }
});

moderationPage.querySelectorAll('[data-mod-enforce]').forEach((form) => {
    const note = form.elements.note;
    const review = form.querySelector('[data-mod-review]');
    const dialog = form.querySelector('dialog');
    const preview = dialog.querySelector('[data-mod-note-preview]');
    const previewText = dialog.querySelector('[data-mod-note-text]');
    const confirm = dialog.querySelector('[data-mod-confirm]');
    let confirmed = false;

    function syncReason() {
        const missing = note.required && !note.value.trim();
        review.disabled = missing;
        note.setCustomValidity(missing ? 'Enter a reason for this action.' : '');
    }

    note.addEventListener('input', syncReason);
    syncReason();

    form.addEventListener('submit', (event) => {
        if (confirmed) return;
        event.preventDefault();
        syncReason();
        if (!form.reportValidity() || dialog.open) return;
        previewText.textContent = note.value.trim();
        preview.hidden = !previewText.textContent;
        dialog.showModal();
    });

    confirm.addEventListener('click', () => {
        if (confirmed || !form.reportValidity()) return;
        confirmed = true;
        confirm.disabled = true;
        review.disabled = true;
        form.requestSubmit();
    });
});
