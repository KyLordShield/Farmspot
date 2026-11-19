(() => {
    const container = document.getElementById('not-found-animation');
    if (!container || !window.lottie) return;

    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const fallback = container.innerHTML;
    container.replaceChildren();
    const animation = window.lottie.loadAnimation({
        container,
        renderer: 'svg',
        loop: true,
        autoplay: !reducedMotion.matches,
        path: container.dataset.animationUrl,
    });
    animation.addEventListener('data_failed', () => {
        animation.destroy();
        container.innerHTML = fallback;
    });
    document.addEventListener('visibilitychange', () => {
        if (document.hidden || reducedMotion.matches) animation.pause();
        else animation.play();
    });
    reducedMotion.addEventListener('change', () => {
        if (reducedMotion.matches || document.hidden) animation.pause();
        else animation.play();
    });
})();
