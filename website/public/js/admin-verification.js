const codeField = document.querySelector('[data-verification-code]');

if (codeField) {
    const input = codeField.querySelector('input');
    const boxes = [...codeField.querySelectorAll('.verification-digits span')];

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

    input.addEventListener('input', render);
    input.addEventListener('change', render);
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
            render();
        }
    });
    window.addEventListener('pageshow', render);

    codeField.classList.add('is-enhanced');
    render();
}
