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
