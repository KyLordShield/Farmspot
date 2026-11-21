(function () {
    var toggle = document.getElementById('togglePassword');
    var field = document.getElementById('password');
    var icon = document.getElementById('togglePasswordIcon');
    if (!toggle || !field || !icon) return;
    toggle.addEventListener('click', function () {
        var showing = field.type === 'text';
        field.type = showing ? 'password' : 'text';
        icon.classList.toggle('bi-eye', showing);
        icon.classList.toggle('bi-eye-slash', !showing);
        toggle.setAttribute('aria-label', showing ? 'Show password' : 'Hide password');
    });
})();

(function () {
    var form = document.getElementById('adminLoginForm');
    var button = document.getElementById('adminLoginSubmit');
    var label = document.getElementById('adminLoginLabel');
    var spinner = document.getElementById('adminLoginSpinner');
    if (!form || !button || !label || !spinner) return;
    var submitting = false;
    form.addEventListener('submit', function (event) {
        if (submitting) {
            event.preventDefault();
            return;
        }
        if (event.defaultPrevented || !form.checkValidity()) return;
        submitting = true;
        button.disabled = true;
        form.setAttribute('aria-busy', 'true');
        label.textContent = 'Signing in…';
        spinner.classList.remove('d-none');
    });
    // Back/forward navigation may restore this page with its disabled button.
    window.addEventListener('pageshow', function () {
        submitting = false;
        button.disabled = false;
        form.removeAttribute('aria-busy');
        label.textContent = 'Sign In';
        spinner.classList.add('d-none');
    });
})();
