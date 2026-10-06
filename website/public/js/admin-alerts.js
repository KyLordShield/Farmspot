/* FarmSpot Admin — SweetAlert2 helpers.
   - Flash messages (success/error alerts rendered by Blade) become toasts.
   - Generic confirm dialogs driven by data-confirm-title / data-confirm-text on
     forms and buttons.
   - Auto-submitting status dropdowns (data-confirm-select) confirm the change
     and revert when cancelled.
   - Normal create/edit forms (data-auto-spinner) disable their submit buttons
     and show a spinner while the request is in flight.
   - A "check the highlighted fields" toast fires when validation marked inputs
     on load and no error alert was already promoted to a toast.

   Every feature degrades to the platform fallback: if SweetAlert2 is not
   cached/loaded (offline CDN, blocked network), native confirm() is used and
   the Bootstrap alert blocks stay visible instead of being converted. */
(function () {
    'use strict';

    var hasSwal = function () {
        return typeof window.Swal !== 'undefined' && window.Swal !== null;
    };

    var BRAND = '#1b6b2c';
    var RED = '#b23a33';

    function escapeHtml(value) {
        return String(value).replace(/[&<>"']/g, function (ch) {
            return '&#' + ch.charCodeAt(0) + ';';
        });
    }

    function toastDefaults() {
        return {
            toast: true,
            position: 'top-end',
            showConfirmButton: false,
            timer: 3400,
            timerProgressBar: true,
            customClass: {
                popup: 'swal-toast-farmspot'
            }
        };
    }

    function extractAlertText(alertEl) {
        var clone = alertEl.cloneNode(true);
        var close = clone.querySelector('.btn-close');
        if (close) {
            close.remove();
        }
        var lines = [];
        clone.querySelectorAll('li').forEach(function (li) {
            lines.push(li.textContent.trim());
        });
        if (lines.length === 0) {
            lines = clone.textContent
                .replace(/\s+/g, ' ')
                .trim()
                .split('\n')
                .map(function (s) { return s.trim(); })
                .filter(Boolean);
        }
        return lines;
    }

    function textToHtml(lines) {
        return escapeHtml(lines.join('\n')).replace(/\n/g, '<br>');
    }

    /* --- Flash messages -> toasts -------------------------------------------- */

    function promoteFlashAlerts() {
        if (!hasSwal()) {
            return { total: 0, errors: 0 };
        }
        var promoted = { total: 0, errors: 0 };
        var alerts = document.querySelectorAll('.content > .alert.alert-success, .content > .alert.alert-danger');
        alerts.forEach(function (alertEl) {
            var lines = extractAlertText(alertEl);
            if (lines.length === 0) {
                return;
            }
            var isError = alertEl.classList.contains('alert-danger');
            var options = toastDefaults();
            options.icon = isError ? 'error' : 'success';
            options.html = textToHtml(lines);
            if (!isError) {
                options.title = 'Done';
            }
            Swal.fire(options);
            // The Blade block stays in the DOM as the no-JS fallback; with JS
            // on we hide it so the page does not show the same message twice.
            alertEl.style.display = 'none';
            promoted.total++;
            if (isError) {
                promoted.errors++;
            }
        });
        return promoted;
    }

    /* --- Generic confirms ---------------------------------------------------- */

    // Proxies a SubmitEvent on to the form after the user confirmed; the flag
    // stops the re-dispatched submit from asking again, then is cleared so the
    // next deliberate click still confirms.
    function proceedWithForm(form) {
        form.setAttribute('data-confirm-handled', '1');
        form.requestSubmit();
        setTimeout(function () {
            form.removeAttribute('data-confirm-handled');
        }, 0);
    }

    function confirmToneColors(tone) {
        return tone === 'danger' ? RED : BRAND;
    }

    function ask(title, text, tone) {
        if (hasSwal()) {
            return new Promise(function (resolve) {
                Swal.fire({
                    title: title,
                    text: text || '',
                    icon: tone === 'danger' ? 'warning' : 'question',
                    showCancelButton: true,
                    confirmButtonText: 'Continue',
                    confirmButtonColor: confirmToneColors(tone),
                    cancelButtonText: 'Cancel',
                    focusConfirm: false
                }).then(function (result) {
                    resolve(result.isConfirmed === true);
                });
            });
        }
        return Promise.resolve(window.confirm(text || title));
    }

    function wireFormConfirms() {
        document.addEventListener('submit', function (event) {
            var form = event.target;
            if (!(form instanceof HTMLFormElement)) {
                return;
            }
            if (form.getAttribute('data-confirm-handled') === '1') {
                return;
            }
            var title = form.getAttribute('data-confirm-title');
            var text = form.getAttribute('data-confirm-text');
            if (!title && !text) {
                return;
            }
            event.preventDefault();
            event.stopPropagation();

            var tone = form.getAttribute('data-confirm-tone') || 'primary';
            ask(title || 'Are you sure?', text, tone).then(function (confirmed) {
                if (confirmed) {
                    proceedWithForm(form);
                }
            });
        }, true);
    }

    function wireButtonConfirms() {
        document.addEventListener('click', function (event) {
            var button = event.target.closest('[data-confirm-title], [data-confirm-text]');
            if (!button) {
                return;
            }
            var form = button.closest('form');
            if (!form) {
                return;
            }
            if (form.getAttribute('data-confirm-handled') === '1') {
                return;
            }
            var title = button.getAttribute('data-confirm-title');
            var text = button.getAttribute('data-confirm-text');
            if (!title && !text) {
                return;
            }
            event.preventDefault();
            event.stopPropagation();

            var tone = (button.getAttribute('data-confirm-tone') || form.getAttribute('data-confirm-tone') || 'primary');
            ask(title || 'Are you sure?', text, tone).then(function (confirmed) {
                if (confirmed) {
                    proceedWithForm(form);
                }
            });
        }, true);
    }

    /* --- Auto-submit status dropdowns with confirm + revert ------------------ */

    function wireConfirmSelects() {
        document.addEventListener('focusin', function (event) {
            var select = event.target;
            if (!(select instanceof HTMLSelectElement) || !select.hasAttribute('data-confirm-select')) {
                return;
            }
            select.setAttribute('data-confirm-prev', select.value);
        });

        document.addEventListener('change', function (event) {
            var select = event.target;
            if (!(select instanceof HTMLSelectElement) || !select.hasAttribute('data-confirm-select')) {
                return;
            }
            var form = select.closest('form');
            if (!form) {
                return;
            }
            var previous = select.getAttribute('data-confirm-prev');
            if (select.value === previous) {
                return;
            }

            function revert() {
                select.value = previous;
            }

            var label = (form.getAttribute('data-confirm-select-label') || 'status');
            var text = 'Change ' + label + ' to "' + select.options[select.selectedIndex].text + '"?';

            if (hasSwal()) {
                Swal.fire({
                    title: 'Confirm change',
                    text: text,
                    icon: 'question',
                    showCancelButton: true,
                    confirmButtonText: 'Change',
                    confirmButtonColor: BRAND,
                    cancelButtonText: 'Cancel',
                    focusConfirm: false
                }).then(function (result) {
                    if (result.isConfirmed) {
                        form.submit();
                    } else {
                        revert();
                    }
                });
            } else if (window.confirm(text)) {
                form.submit();
            } else {
                revert();
            }
        });
    }

    /* --- Submit-button spinner ------------------------------------------------ */

    function wireAutoSpinners() {
        document.addEventListener('submit', function (event) {
            var form = event.target;
            if (!(form instanceof HTMLFormElement)) {
                return;
            }
            if (!form.hasAttribute('data-auto-spinner')) {
                return;
            }
            form.querySelectorAll('button[type="submit"]').forEach(function (button) {
                if (button.disabled) {
                    return;
                }
                button.disabled = true;
                var spinner = document.createElement('span');
                spinner.className = 'spinner-border spinner-border-sm me-1';
                spinner.setAttribute('aria-hidden', 'true');
                button.prepend(spinner);
            });
        }, true);
    }

    /* --- Validation summary toast --------------------------------------------- */

    function isInsideCategoryPanel(element) {
        var node = element;
        while (node && node !== document) {
            if (node.id === 'categoryPanel') {
                return true;
            }
            node = node.parentElement;
        }
        return false;
    }

    function validationSummaryToast(promotedErrors) {
        if (!hasSwal() || promotedErrors > 0) {
            return;
        }
        var invalid = document.querySelector('.is-invalid');
        if (!invalid || isInsideCategoryPanel(invalid)) {
            return;
        }
        var options = toastDefaults();
        options.icon = 'warning';
        options.title = 'Form not submitted';
        options.text = 'Please fix the highlighted fields and try again.';
        Swal.fire(options);
    }

    /* --- Boot ----------------------------------------------------------------- */

    // The count of promoted error alerts is passed along so the generic
    // validation toast never double-ups on a page whose error list already
    // appeared as an error toast.
    var flash = promoteFlashAlerts();
    validationSummaryToast(flash.errors);

    wireFormConfirms();
    wireButtonConfirms();
    wireConfirmSelects();
    wireAutoSpinners();
})();