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
<script src="{{ asset('js/media-modal.js') }}?v={{ filemtime(public_path('js/media-modal.js')) }}"></script>
@endpush
