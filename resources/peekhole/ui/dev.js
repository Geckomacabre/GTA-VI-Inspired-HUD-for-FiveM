/**
 * dev.js — mirrors the lb-phone-app-template pattern exactly.
 *
 * In FiveM (native):   body is made visible; lb-phone's own UI confines the
 *                      iframe to the phone screen — no wrapper needed.
 * In a browser (dev):  a phone-frame mockup is built around #content so you
 *                      can preview the app without a real server.
 */
(function () {
    function init() {
        var content = document.getElementById('content');

        if (typeof invokeNative !== 'undefined') {
            /* ── Running inside FiveM ───────────────────────────────────── */
            // Remove #phone-wrapper and hoist .app#content directly into body
            // so the height:100% chain is: html → body → .app → #app-shell
            // Without this, height:100% on .app has no defined parent height
            // and the content area collapses to nothing (shows as black).
            var wrapper = document.getElementById('phone-wrapper');
            if (wrapper && content) {
                document.body.replaceChild(content, wrapper);
            }
            document.body.style.visibility = 'visible';
            return;
        }

        /* ── Browser / development mode ────────────────────────────────── */
        // Build a simulated phone shell so the UI is easy to work on.

        // Scale the mockup to fit the current window
        function getScale() {
            return Math.min(window.innerWidth, window.innerHeight) / 1920 * 3.5;
        }

        // Dev wrapper (full-page centering container)
        var devWrapper = document.createElement('div');
        devWrapper.style.cssText = [
            'display:flex',
            'align-items:center',
            'justify-content:center',
            'width:100%',
            'height:100%',
            'position:fixed',
            'inset:0',
            'background:#111',
        ].join(';');

        // Outer phone frame
        var phoneFrame = document.createElement('div');
        phoneFrame.className = 'phone-frame';

        // Notch
        var notch = document.createElement('div');
        notch.className = 'phone-notch';
        phoneFrame.appendChild(notch);

        // Content area (holds the app)
        var phoneContent = document.createElement('div');
        phoneContent.className = 'phone-content';

        // Move #content inside the phone
        if (content && content.parentNode) {
            content.parentNode.removeChild(content);
        }
        phoneContent.appendChild(content);
        phoneFrame.appendChild(phoneContent);

        // Home-bar indicator
        var indicator = document.createElement('div');
        indicator.className = 'phone-indicator';
        phoneFrame.appendChild(indicator);

        devWrapper.appendChild(phoneFrame);
        document.body.appendChild(devWrapper);

        // Scale on load + resize
        function applyScale() {
            var s = getScale();
            phoneFrame.style.transform = 'scale(' + s + ')';
        }

        applyScale();
        window.addEventListener('resize', applyScale);

        document.body.style.visibility = 'visible';
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
}());
