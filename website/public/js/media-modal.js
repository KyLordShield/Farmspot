(function () {
    var modal = document.getElementById('documentModal');
    if (!modal) {
        return;
    }

    var titleEl = document.getElementById('documentModalTitle');
    var imageEl = document.getElementById('documentModalImage');
    var frameEl = document.getElementById('documentModalFrame');

    modal.addEventListener('show.bs.modal', function (event) {
        var trigger = event.relatedTarget;
        if (!trigger) {
            return;
        }

        var url = trigger.getAttribute('data-document-url') || '';
        var title = trigger.getAttribute('data-document-title') || 'Document';

        titleEl.textContent = title;

        // Cloudinary serves a plain image for jpg/png and everything else
        // (pdf, doc) needs the embedded viewer rather than an <img>.
        if (trigger.getAttribute('data-document-kind') === 'image') {
            imageEl.setAttribute('src', url);
            imageEl.alt = title;
            imageEl.hidden = false;
            frameEl.setAttribute('src', 'about:blank');
            frameEl.hidden = true;
        } else {
            frameEl.setAttribute('src', url);
            frameEl.hidden = false;
            imageEl.removeAttribute('src');
            imageEl.hidden = true;
        }
    });

    modal.addEventListener('hidden.bs.modal', function () {
        frameEl.setAttribute('src', 'about:blank');
        imageEl.removeAttribute('src');
    });
})();
