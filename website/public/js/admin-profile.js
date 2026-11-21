(function () {
    'use strict';
    var phone = document.getElementById('profile-phone');
    if (phone) phone.addEventListener('input', function () {
        phone.value = phone.value.replace(/[^0-9]/g, '').slice(0, 11);
    });
    var code = document.getElementById('profile-code');
    if (!code) return;
    var container = document.getElementById('profile-code-boxes');
    var boxes = container ? Array.from(container.querySelectorAll('[data-code-digit]')) : [];
    function numbers(value) { return value.replace(/[^0-9]/g, '').slice(0, 6); }
    function onlyNumbers(event) {
        if (event.inputType === 'insertText' && event.data && /[^0-9]/.test(event.data)) event.preventDefault();
    }
    code.addEventListener('beforeinput', onlyNumbers);
    code.addEventListener('input', function () { code.value = numbers(code.value); });
    if (boxes.length !== 6) return;
    function sync() { code.value = boxes.map(function (box) { return box.value; }).join(''); }
    function enter(index, value) {
        var digits = numbers(value);
        if (digits.length === 6) index = 0;
        if (!digits) boxes[index].value = '';
        for (var offset = 0; offset < digits.length && index + offset < 6; offset++) {
            boxes[index + offset].value = digits[offset];
        }
        sync();
        if (digits) boxes[Math.min(index + digits.length, 5)].focus();
    }
    boxes.forEach(function (box, index) {
        box.required = true;
        box.addEventListener('focus', function () { box.select(); });
        box.addEventListener('beforeinput', onlyNumbers);
        box.addEventListener('input', function () { enter(index, box.value); });
        box.addEventListener('paste', function (event) {
            event.preventDefault();
            enter(index, event.clipboardData.getData('text'));
        });
        box.addEventListener('keydown', function (event) {
            if (event.key === 'Backspace' && !box.value && index > 0) {
                event.preventDefault();
                boxes[index - 1].value = '';
                boxes[index - 1].focus();
                sync();
            } else if (event.key === 'ArrowLeft' && index > 0) {
                event.preventDefault(); boxes[index - 1].focus();
            } else if (event.key === 'ArrowRight' && index < 5) {
                event.preventDefault(); boxes[index + 1].focus();
            }
        });
    });
    code.type = 'hidden';
    code.required = false;
    container.hidden = false;
})();
