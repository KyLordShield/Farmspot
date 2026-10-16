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

    // Resolves with `false` when the user cancels, `true` for a plain confirm,
    // or the trimmed string the user typed when [inputLabel] asks for a reason.
    // The reason variant is required by deactivation: the value is echoed back
    // into the form as a hidden field before it submits, so the same modal that
    // used to be a bare yes/no can carry the takedown reason the API insists on.
    function ask(title, text, tone, inputLabel) {
        if (hasSwal()) {
            return new Promise(function (resolve) {
                var options = {
                    title: title,
                    text: text || '',
                    icon: tone === 'danger' ? 'warning' : 'question',
                    showCancelButton: true,
                    confirmButtonText: inputLabel ? 'Deactivate' : 'Continue',
                    confirmButtonColor: confirmToneColors(tone),
                    cancelButtonText: 'Cancel',
                    focusConfirm: false
                };
                if (inputLabel) {
                    options.input = 'textarea';
                    options.inputLabel = inputLabel;
                    options.inputPlaceholder = 'Shown to the person, and lets them request a re-evaluation.';
                    options.inputValidator = function (value) {
                        return (value && value.trim().length > 0) ? undefined : 'A reason is required.';
                    };
                }
                Swal.fire(options).then(function (result) {
                    if (result.isConfirmed !== true) {
                        resolve(false);
                        return;
                    }
                    resolve(inputLabel ? String(result.value || '').trim() : true);
                });
            });
        }
        if (inputLabel) {
            var answer = window.prompt(inputLabel, '');
            return Promise.resolve(answer && answer.trim() ? answer.trim() : false);
        }
        return Promise.resolve(window.confirm(text || title));
    }

    // Puts the confirmed value into the form under the field name the server
    // validates, creating the hidden input on first use.
    function applyConfirmInput(form, name, value) {
        var field = form.querySelector('input[type="hidden"][name="' + name + '"]');
        if (!field) {
            field = document.createElement('input');
            field.type = 'hidden';
            field.name = name;
            form.appendChild(field);
        }
        field.value = value;
    }

    function confirmInputName(activator, form) {
        return (activator && activator.getAttribute('data-confirm-input'))
            || form.getAttribute('data-confirm-input');
    }

    function confirmInputLabel(activator, form) {
        return (activator && activator.getAttribute('data-confirm-input-label'))
            || form.getAttribute('data-confirm-input-label')
            || 'Reason';
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
            var inputName = confirmInputName(null, form);
            ask(title || 'Are you sure?', text, tone, inputName ? confirmInputLabel(null, form) : null).then(function (result) {
                if (result === false) {
                    return;
                }
                if (inputName) {
                    applyConfirmInput(form, inputName, String(result));
                }
                proceedWithForm(form);
            });
        }, true);
    }

    function wireButtonConfirms() {
        document.addEventListener('click', function (event) {
            // Only a click on the control that actually submits the request may
            // raise the confirm dialog. The attributes live on the enclosing
            // form (seller-request decision forms, report action forms, logout),
            // so a plain closest() search would treat a click inside the reject
            // reason textarea or the report note field as a confirmation click
            // and pop the dialog instead of letting the admin type. Resolving
            // the submit control first means a field click finds no button and
            // falls through to normal focus behaviour.
            var activator = event.target.closest(
                'button[type="submit"], button:not([type]), input[type="submit"], input[type="image"]'
            );
            if (!activator) {
                return;
            }

            var form = activator.closest('form');
            if (!form) {
                return;
            }
            if (form.getAttribute('data-confirm-handled') === '1') {
                return;
            }
            // The attributes may sit on the button or on the form; in both
            // layouts the click came from the submit control, so the button's
            // own wording wins and the form's is the fallback.
            var title = activator.getAttribute('data-confirm-title')
                || form.getAttribute('data-confirm-title');
            var text = activator.getAttribute('data-confirm-text')
                || form.getAttribute('data-confirm-text');
            if (!title && !text) {
                return;
            }
            event.preventDefault();
            event.stopPropagation();

            var tone = (activator.getAttribute('data-confirm-tone')
                || form.getAttribute('data-confirm-tone')
                || 'primary');
            var inputName = confirmInputName(activator, form);
            ask(title || 'Are you sure?', text, tone, inputName ? confirmInputLabel(activator, form) : null).then(function (result) {
                if (result === false) {
                    return;
                }
                if (inputName) {
                    applyConfirmInput(form, inputName, String(result));
                }
                proceedWithForm(form);
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