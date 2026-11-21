const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('photo slots account for removals and never silently discard selected uploads', () => {
    function checkbox() {
        return { checked: false, listeners: {}, addEventListener(type, handler) { this.listeners[type] = handler; } };
    }
    const removals = Array.from({ length: 5 }, checkbox);
    const section = { dataset: { photoLimit: '5', existingCount: '5' }, querySelectorAll: () => removals };
    const upload = { files: [], listeners: {},
        addEventListener(type, handler) { this.listeners[type] = handler; },
        setCustomValidity(message) { this.error = message; },
    };
    const hint = {};
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../public/js/listing-form.js'), 'utf8'), {
        document: {
            querySelector: selector => selector === '[data-listing-photos]' ? section : null,
            getElementById: id => id === 'photos' ? upload : hint,
        },
    });
    assert.equal(upload.disabled, true);
    removals[0].checked = true;
    removals[0].listeners.change();
    assert.equal(upload.disabled, false);
    assert.match(hint.textContent, /1 more photo/);
    upload.files = [{}, {}];
    upload.listeners.change();
    assert.match(upload.error, /Select fewer files/);
    upload.files = [{}];
    upload.listeners.change();
    assert.equal(upload.error, '');
    removals[0].checked = false;
    removals[0].listeners.change();
    assert.equal(upload.disabled, false);
    assert.equal(upload.files.length, 1);
    assert.match(upload.error, /0 more photos/);
});
