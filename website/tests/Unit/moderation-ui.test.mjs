import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { runInNewContext } from 'node:vm'

const source = readFileSync(new URL('../../public/js/moderation.js', import.meta.url), 'utf8')

test('enforcement previews the reason and sends one request only after confirmation', () => {
    const reason = {
        required: true,
        value: '',
        setCustomValidity(message) { this.error = message },
        addEventListener(type, listener) { this[type] = listener },
    }
    const review = {}
    const preview = {}
    const previewText = {}
    const confirm = { addEventListener(type, listener) { this[type] = listener } }
    const dialog = {
        open: false,
        showModal() { this.open = true },
        querySelector(selector) {
            return {
                '[data-mod-note-preview]': preview,
                '[data-mod-note-text]': previewText,
                '[data-mod-confirm]': confirm,
            }[selector]
        },
    }
    let requests = 0
    const form = {
        elements: { note: reason },
        querySelector: selector => selector === 'dialog' ? dialog : review,
        reportValidity: () => !reason.error,
        addEventListener(type, listener) { this[type] = listener },
        requestSubmit() {
            let prevented = false
            this.submit({ preventDefault() { prevented = true } })
            if (!prevented) requests++
        },
    }
    const page = {
        querySelector: () => ({}),
        querySelectorAll: selector => selector === '[data-mod-enforce]' ? [form] : [],
        addEventListener() {},
    }
    runInNewContext(source, { document: { querySelector: () => page } })

    assert.equal(review.disabled, true)
    reason.value = '   '
    reason.input()
    assert.equal(review.disabled, true)
    reason.value = '  Gi-review ang report 🌱 · تمت المراجعة  '
    reason.input()
    assert.equal(review.disabled, false)
    form.requestSubmit()
    assert.equal(dialog.open, true)
    assert.equal(previewText.textContent, reason.value.trim())
    assert.equal(requests, 0)

    dialog.open = false
    assert.equal(requests, 0)
    form.requestSubmit()
    confirm.click()
    confirm.click()
    assert.equal(requests, 1)
})
