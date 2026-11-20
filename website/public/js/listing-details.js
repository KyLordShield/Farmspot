const listingDetails = document.querySelector('#listing-details');
const copyId = listingDetails.querySelector('[data-copy-id]');
const copyFeedback = listingDetails.querySelector('[data-copy-feedback]');

copyId.addEventListener('click', async () => {
    try {
        await navigator.clipboard.writeText(copyId.dataset.copyId);
        copyFeedback.textContent = 'Listing ID copied.';
    } catch {
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(copyId.querySelector('[data-id-value]'));
        selection.removeAllRanges();
        selection.addRange(range);
        copyFeedback.textContent = 'Listing ID selected for copying.';
    }
});

const lightbox = listingDetails.querySelector('[data-lightbox]');

if (lightbox?.showModal) {
    const links = [...listingDetails.querySelectorAll('[data-photo-index]')];
    const image = lightbox.querySelector('[data-lightbox-image]');
    const caption = lightbox.querySelector('[data-photo-caption]');
    const original = lightbox.querySelector('[data-original-photo]');
    let currentIndex = 0;
    let opener;

    function showPhoto(index) {
        currentIndex = (index + links.length) % links.length;
        const link = links[currentIndex];
        image.src = link.href;
        original.href = link.href;
        image.alt = link.querySelector('img').alt;
        caption.textContent = `Photo ${currentIndex + 1} of ${links.length}`;
    }

    links.forEach((link, index) => {
        link.addEventListener('click', (event) => {
            if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
            event.preventDefault();
            opener = link;
            showPhoto(index);
            lightbox.showModal();
        });
    });

    lightbox.querySelector('[data-close-photo]').addEventListener('click', () => lightbox.close());
    lightbox.addEventListener('close', () => opener?.focus());
    lightbox.querySelectorAll('[data-photo-step]').forEach((button) => {
        button.addEventListener('click', () => showPhoto(currentIndex + Number(button.dataset.photoStep)));
    });

    lightbox.addEventListener('keydown', (event) => {
        if (links.length < 2 || !['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
        event.preventDefault();
        showPhoto(currentIndex + (event.key === 'ArrowLeft' ? -1 : 1));
    });
}
