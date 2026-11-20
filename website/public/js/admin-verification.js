const codeField = document.querySelector('[data-verification-code]');

if (codeField) {
    const input = codeField.querySelector('input');
    const boxes = [...codeField.querySelectorAll('.verification-digits span')];
    const form = input.form;
    const verifyButton = form.querySelector('button[type="submit"]');
    const verifyLabel = verifyButton.querySelector('[data-verify-label]');
    const verifyLoading = verifyButton.querySelector('[data-verify-loading]');
    const verifyStatus = form.querySelector('[data-verify-status]');
    const initiallyDisabled = verifyButton.disabled;
    let submitting = false;

    const setSubmitting = (pending) => {
        submitting = pending;
        verifyButton.disabled = pending || initiallyDisabled;
        input.readOnly = pending;
        verifyLabel.hidden = pending;
        verifyLoading.hidden = !pending;
        verifyStatus.textContent = pending ? 'Verifying your code…' : '';
    };

    const render = () => {
        const caret = input.selectionStart ?? input.value.length;
        const digits = input.value.replace(/[^0-9]/g, '').slice(0, boxes.length);
        if (input.value !== digits) {
            const position = input.value.slice(0, caret).replace(/[^0-9]/g, '').length;
            input.value = digits;
            input.setSelectionRange(position, position);
        }

        const current = Math.min(boxes.length - 1, input.selectionStart ?? digits.length);
        boxes.forEach((box, index) => {
            box.textContent = digits[index] ?? '';
            box.classList.toggle('is-current', index === current);
        });
    };

    const verifyWhenComplete = () => {
        render();
        if (input.value.length === boxes.length && !verifyButton.disabled && !submitting) {
            form.requestSubmit(verifyButton);
        }
    };

    form.addEventListener('submit', (event) => {
        if (submitting || verifyButton.disabled) {
            event.preventDefault();
            return;
        }
        setSubmitting(true);
    });

    input.addEventListener('input', verifyWhenComplete);
    input.addEventListener('change', verifyWhenComplete);
    input.addEventListener('focus', render);
    input.addEventListener('keyup', render);
    input.addEventListener('click', (event) => {
        const clickedBox = boxes.findIndex((box) => box.getBoundingClientRect().right >= event.clientX);
        const position = clickedBox < 0 ? input.value.length : Math.min(clickedBox, input.value.length);
        input.setSelectionRange(position, position);
        render();
    });
    input.addEventListener('paste', (event) => {
        const pasted = event.clipboardData?.getData('text') ?? '';
        const digits = pasted.replace(/[^0-9]/g, '');
        if (digits.length === boxes.length) {
            event.preventDefault();
            input.value = digits;
            verifyWhenComplete();
        }
    });
    window.addEventListener('pageshow', () => {
        setSubmitting(false);
        render();
    });

    codeField.classList.add('is-enhanced');
    render();
}
