const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('login feedback respects validation, prevents duplicates, and resets on return', () => {
    const listeners = {};
    const classes = new Set(['d-none']);
    const form = {
        valid: false, attrs: {},
        checkValidity() { return this.valid; },
        addEventListener(type, callback) { listeners[type] = callback; },
        setAttribute(key, value) { this.attrs[key] = value; },
        removeAttribute(key) { delete this.attrs[key]; },
    };
    const button = { disabled: false };
    const label = { textContent: 'Sign In' };
    const spinner = { classList: {
        add(value) { classes.add(value); }, remove(value) { classes.delete(value); },
    } };
    const elements = { adminLoginForm: form, adminLoginSubmit: button,
        adminLoginLabel: label, adminLoginSpinner: spinner };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../public/js/admin-login.js'), 'utf8'), {
        document: { getElementById: id => elements[id] },
        window: { addEventListener(type, callback) { listeners[type] = callback; } },
    });
    const event = () => ({ defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } });
    listeners.submit(event());
    assert.equal(button.disabled, false);
    form.valid = true;
    listeners.submit(event());
    assert.equal(button.disabled, true);
    assert.equal(label.textContent, 'Signing in…');
    assert.equal(form.attrs['aria-busy'], 'true');
    assert.equal(classes.has('d-none'), false);
    const repeat = event();
    listeners.submit(repeat);
    assert.equal(repeat.defaultPrevented, true);
    listeners.pageshow();
    assert.equal(button.disabled, false);
    assert.equal(label.textContent, 'Sign In');
    assert.equal(classes.has('d-none'), true);
    assert.equal(form.attrs['aria-busy'], undefined);
});
