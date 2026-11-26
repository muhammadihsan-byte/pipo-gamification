/* Performance overlays for the approved V4 rig. No paths, colors, or idle
   keyframes are replaced. Every one-shot returns to the running idle pose. */
(() => {
    'use strict';
    const mascot = document.querySelector('svg');
    if (!mascot) return;
    mascot.pauseAnimations();
    mascot.setCurrentTime(0);

    const ns = mascot.namespaceURI;
    const tracks = [];
    const wrappers = new Map();
    let running = false;
    let active = false;
    let pending = null;
    let finishTimer = null;

    function track(selector, type, values, duration) {
        const part = mascot.querySelector(selector);
        if (!part) return null; // A missing optional part must never blank Pipo.
        let wrapper = wrappers.get(selector);
        if (!wrapper) {
            wrapper = document.createElementNS(ns, 'g');
            part.parentNode.insertBefore(wrapper, part);
            wrapper.appendChild(part);
            wrappers.set(selector, wrapper);
        }
        const animation = document.createElementNS(ns, 'animateTransform');
        Object.entries({
            attributeName: 'transform', type, begin: 'indefinite', dur: `${duration}s`,
            fill: 'remove', restart: 'always', values,
            keyTimes: '0;0.14;0.38;0.66;1', calcMode: 'spline',
            keySplines: '0.4 0 0.7 1;0.16 0 0.3 1;0.3 0 0.5 1;0.3 0 0.4 1'
        }).forEach(([key, value]) => animation.setAttribute(key, value));
        wrapper.appendChild(animation);
        tracks.push(animation);
        return animation;
    }

    // Anticipation → clear gesture → ear/flower follow-through → settle.
    function performance(duration, definitions) {
        return { duration, tracks: definitions.map(args => track(...args, duration)).filter(Boolean) };
    }
    const reactions = {
        acknowledge: performance(0.96, [
            ['#UpperBody', 'rotate', '0 162 248;-0.8 162 248;2 162 248;1.4 162 248;0 162 248'],
            ['[aria-label="Arm_L"]', 'rotate', '0 99 191;-3 99 191;24 99 191;16 99 191;0 99 191'],
            ['[aria-label="Ear_L"]', 'rotate', '0 145 89;1 145 89;-4 145 89;1.2 145 89;0 145 89'],
            ['[aria-label="FlowerRoot"]', 'rotate', '0 192 84;0 192 84;-1.5 192 84;-3 192 84;0 192 84']
        ]),
        reassure: performance(0.88, [
            ['#UpperBody', 'rotate', '0 162 248;0.4 162 248;-1.7 162 248;-1 162 248;0 162 248'],
            ['[aria-label="HeadFaceRoot"]', 'translate', '0 0;0 -0.4;0 1.5;0 0.5;0 0'],
            ['[aria-label="Ear_L"]', 'rotate', '0 145 89;0 145 89;2.5 145 89;-0.7 145 89;0 145 89'],
            ['[aria-label="FlowerRoot"]', 'rotate', '0 192 84;0 192 84;1.8 192 84;-0.8 192 84;0 192 84']
        ]),
        // Encouragement after a choice; this animation never implies earned XP.
        celebrate: performance(1.08, [
            ['#UpperBody', 'translate', '0 0;0 1.2;0 -3;0 -0.8;0 0'],
            ['[aria-label="Arm_L"]', 'rotate', '0 99 191;-3 99 191;26 99 191;20 99 191;0 99 191'],
            ['[aria-label="Arm_R"]', 'rotate', '0 226 191;2 226 191;-18 226 191;-12 226 191;0 226 191'],
            ['[aria-label="Ear_L"]', 'rotate', '0 145 89;1 145 89;-4 145 89;1.5 145 89;0 145 89'],
            ['[aria-label="FlowerRoot"]', 'rotate', '0 192 84;0 192 84;-3 192 84;2 192 84;0 192 84']
        ])
    };

    function react(name) {
        if (!running || !Object.hasOwn(reactions, name)) return false;
        if (active) {
            pending = name; // Coalesce fast updates into at most one reply.
            return false;
        }
        const reaction = reactions[name];
        active = true;
        reaction.tracks.forEach(animation => animation.beginElement());
        finishTimer = setTimeout(() => {
            finishTimer = null;
            active = false;
            const next = pending;
            pending = null;
            if (next) react(next);
        }, reaction.duration * 1000);
        return true;
    }

    function pause() {
        running = false;
        pending = null;
        if (finishTimer !== null) clearTimeout(finishTimer);
        finishTimer = null;
        tracks.forEach(animation => animation.endElement());
        active = false;
        mascot.pauseAnimations();
    }

    window.pipoMotion = {
        react,
        pause,
        resume() { running = true; mascot.unpauseAnimations(); }
    };
    // Native keeps the approved still visible until SVG has had a paint opportunity.
    requestAnimationFrame(() => requestAnimationFrame(() => {
        window.webkit?.messageHandlers?.pipoReady?.postMessage(true);
    }));
})();
