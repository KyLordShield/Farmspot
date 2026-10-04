<div class="modal fade" id="documentModal" tabindex="-1" aria-labelledby="documentModalTitle" aria-hidden="true">
    <div class="modal-dialog modal-xl modal-dialog-centered modal-dialog-scrollable">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="documentModalTitle">Document</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body document-modal-body">
                <img id="documentModalImage" class="document-modal-image" alt="" hidden>
                <iframe id="documentModalFrame" class="document-modal-frame" title="Document preview" hidden></iframe>
            </div>
            <div class="modal-footer">
                <a id="documentModalOpenLink" href="#" target="_blank" rel="noopener" class="btn btn-ghost">
                    <i class="bi bi-box-arrow-up-right me-1"></i> Open Full Size
                </a>
                <button type="button" class="btn btn-farm" data-bs-dismiss="modal">Close</button>
            </div>
        </div>
    </div>
</div>

@push('scripts')
<script>
    (function () {
        var modal = document.getElementById('documentModal');
        if (!modal) {
            return;
        }

        var titleEl = document.getElementById('documentModalTitle');
        var imageEl = document.getElementById('documentModalImage');
        var frameEl = document.getElementById('documentModalFrame');
        var openLink = document.getElementById('documentModalOpenLink');

        modal.addEventListener('show.bs.modal', function (event) {
            var trigger = event.relatedTarget;
            if (!trigger) {
                return;
            }

            var url = trigger.getAttribute('data-document-url') || '';
            var title = trigger.getAttribute('data-document-title') || 'Document';

            titleEl.textContent = title;
            openLink.setAttribute('href', url);

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
</script>
@endpush
