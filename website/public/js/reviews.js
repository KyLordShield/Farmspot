/* Review moderation page.
   The table only renders a short preview of each comment. "Read full" opens
   the complete text — paragraphs and all — in a dialog, so a long review can
   be read without letting it widen the table. The comment is escaped before
   it reaches SweetAlert, so review text can never inject markup here. */
(function () {
    'use strict';

    function escapeHtml(value) {
        return String(value).replace(/[&<>"']/g, function (ch) {
            return '&#' + ch.charCodeAt(0) + ';';
        });
    }

    document.addEventListener('click', function (event) {
        var target = event.target instanceof Element ? event.target : event.target.parentElement;
        var trigger = target ? target.closest('[data-comment-full]') : null;
        if (!trigger) {
            return;
        }

        var comment = trigger.getAttribute('data-comment-full') || '';
        var meta = trigger.getAttribute('data-comment-meta') || '';

        if (typeof window.Swal === 'undefined' || window.Swal === null) {
            window.alert(comment);
            return;
        }

        window.Swal.fire({
            title: 'Review comment',
            html: '<div class="review-comment-full">' + escapeHtml(comment) + '</div>'
                + (meta ? '<div class="review-comment-meta">' + escapeHtml(meta) + '</div>' : ''),
            confirmButtonText: 'Close',
            confirmButtonColor: '#1b6b2c',
            customClass: {
                popup: 'review-comment-popup'
            }
        });
    });
})();
