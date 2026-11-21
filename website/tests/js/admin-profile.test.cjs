const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('verification boxes accept digits, support paste and backspace, and preserve leading zeros', () => {
    let focused = null;
    function input(index) {
        return { value: '', listeners: {},
            addEventListener(type, callback) { this.listeners[type] = callback; },
            focus() { focused = index; }, select() {},
        };
    }
    const boxes = Array.from({ length: 6 }, (_, index) => input(index));
    const code = input();
    const phone = input();
    const container = { hidden: true, querySelectorAll: () => boxes };
    const elements = { 'profile-code': code, 'profile-code-boxes': container, 'profile-phone': phone };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../public/js/admin-profile.js'), 'utf8'), {
        document: { getElementById: id => elements[id] },
    });
    assert.equal(container.hidden, false);
    assert.equal(code.type, 'hidden');
    assert.ok(boxes.every(box => box.required));
    let blocked = false;
    boxes[0].listeners.beforeinput({ inputType: 'insertText', data: 'a', preventDefault() { blocked = true; } });
    assert.equal(blocked, true);
    boxes[0].value = '1';
    boxes[0].listeners.input();
    assert.equal(code.value, '1');
    assert.equal(focused, 1);
    boxes[2].listeners.paste({ preventDefault() {}, clipboardData: { getData: () => '00 12ab34' } });
    assert.equal(code.value, '001234');
    assert.equal(focused, 5);
    boxes[5].value = '';
    boxes[5].listeners.keydown({ key: 'Backspace', preventDefault() {} });
    assert.equal(code.value, '0012');
    assert.equal(focused, 4);
    boxes[4].listeners.keydown({ key: 'ArrowLeft', preventDefault() {} });
    assert.equal(focused, 3);
    phone.value = '09ab12345678999';
    phone.listeners.input();
    assert.equal(phone.value, '09123456789');
});

test('profile script works when verification fields are not displayed', () => {
    const phone = { listeners: {}, addEventListener(type, handler) { this.listeners[type] = handler; } };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../public/js/admin-profile.js'), 'utf8'), {
        document: { getElementById: id => id === 'profile-phone' ? phone : null },
    });
    assert.equal(typeof phone.listeners.input, 'function');
});
