/* Global chrome for the admin panel: the off-canvas sidebar on small
   screens, and the "current page" highlight in the menu. Vanilla JS on
   purpose — nothing here needs a framework or a SweetAlert-style helper. */
(function () {
    'use strict';

    var sidebar = document.getElementById('appSidebar');
    var overlay = document.getElementById('sidebarOverlay');
    var toggle = document.getElementById('sidebarToggle');

    function closeSidebar() {
        if (!sidebar) {
            return;
        }
        sidebar.classList.remove('open');
        if (overlay) {
            overlay.classList.remove('show');
        }
        if (toggle) {
            toggle.setAttribute('aria-expanded', 'false');
        }
    }

    if (sidebar && overlay && toggle) {
        toggle.addEventListener('click', function () {
            var open = sidebar.classList.toggle('open');
            overlay.classList.toggle('show', open);
            toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        });

        overlay.addEventListener('click', closeSidebar);

        // Picking a menu item lands the moderator on the new page rather than
        // leaving the drawer covering it.
        sidebar.querySelectorAll('.menu a').forEach(function (link) {
            link.addEventListener('click', closeSidebar);
        });

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') {
                closeSidebar();
            }
        });
    }

    // Active nav item. Matched against the browser path so the server does not
    // need a per-route active helper: /listings, /listings/12 and
    // /listings/12/edit all highlight "Listings".
    var path = window.location.pathname.replace(/\/+$/, '') || '/';
    var bestLink = null;
    var bestLength = 0;

    if (sidebar) {
        sidebar.querySelectorAll('.menu a').forEach(function (link) {
            var href = link.getAttribute('href');
            if (!href) {
                return;
            }
            var linkPath = href.replace(/\/+$/, '') || '/';

            var matches = path === linkPath ||
                (linkPath !== '/' && path.indexOf(linkPath) === 0);

            if (matches && linkPath.length > bestLength) {
                bestLength = linkPath.length;
                bestLink = link;
            }
        });

        if (bestLink) {
            bestLink.classList.add('active');
            bestLink.setAttribute('aria-current', 'page');
        }
    }
})();