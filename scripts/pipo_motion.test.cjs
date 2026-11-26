const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(new URL('../Pipo/Core/DesignSystem/PipoV4Motion.js', `file://${__filename}`), 'utf8');

// A controllable clock and SMIL DOM exercise the real bundled controller.
function rig(missing = []) {
    const created = [], events = [], timers = new Map(), frames = [];
    let now = 0, nextTimer = 0, resets = 0, paused = true, paints = 0;
    function element(name) {
        return { name, attrs: {}, parentNode: null, children: [],
            setAttribute(k, v) { this.attrs[k] = v; },
            appendChild(child) { this.children.push(child); child.parentNode = this; },
            insertBefore(child) { this.appendChild(child); },
            beginElement() { events.push({ time: now, element: this }); },
            endElement() { this.ended = true; }
        };
    }
    const root = element('svg'), parts = new Map();
    root.namespaceURI = 'http://www.w3.org/2000/svg';
    root.pauseAnimations = () => { paused = true; };
    root.unpauseAnimations = () => { paused = false; };
    root.setCurrentTime = () => { resets++; };
    root.querySelector = selector => {
        if (missing.includes(selector)) return null;
        if (!parts.has(selector)) { const part = element(selector); root.appendChild(part); parts.set(selector, part); }
        return parts.get(selector);
    };
    const window = { webkit: { messageHandlers: { pipoReady: { postMessage() { paints++; } } } } };
    vm.runInNewContext(source, {
        window, document: { querySelector: () => root, createElementNS: (_, name) => {
            const e = element(name); created.push(e); return e;
        } },
        setTimeout(callback, delay) { const id = ++nextTimer; timers.set(id, { at: now + delay, callback }); return id; },
        clearTimeout(id) { timers.delete(id); },
        requestAnimationFrame(callback) { frames.push(callback); }
    });
    return { api: window.pipoMotion, events, created,
        get paused() { return paused; }, get resets() { return resets; },
        get pendingTimers() { return timers.size; }, get paints() { return paints; },
        paint() { frames.shift()?.(); },
        advance(milliseconds) {
            const end = now + milliseconds;
            while ([...timers.values()].some(t => t.at <= end)) {
                const [id, timer] = [...timers].sort((a, b) => a[1].at - b[1].at)[0];
                timers.delete(id); now = timer.at; timer.callback();
            }
            now = end;
        }
    };
}

test('no playback before visible; paint handshake waits for two frames', () => {
    const r = rig();
    assert.equal(r.api.react('acknowledge'), false);
    assert.equal(r.events.length, 0);
    assert.equal(r.paused, true);
    r.paint(); assert.equal(r.paints, 0);
    r.paint(); assert.equal(r.paints, 1);
});

test('all reactions settle into the current idle without resetting its timeline', () => {
    const r = rig(); r.api.resume();
    for (const name of ['acknowledge', 'reassure', 'celebrate']) {
        assert.equal(r.api.react(name), true);
        r.advance(1100);
        assert.equal(r.pendingTimers, 0);
    }
    assert.equal(r.resets, 1, 'idle must only be initialized once');
    for (const track of r.created.filter(e => e.name === 'animateTransform')) {
        const values = track.attrs.values.split(';');
        assert.equal(values[0], values.at(-1), 'gesture must end at its neutral transform');
        assert.equal(track.attrs.fill, 'remove');
        assert.ok(parseFloat(track.attrs.dur) <= 1.1);
        assert.equal(track.attrs.repeatCount, undefined, 'reactions must not loop');
    }
});

test('rapid events coalesce to the latest response, never parallel performances', () => {
    const r = rig(); r.api.resume(); r.api.react('acknowledge');
    const initialCount = r.events.length;
    for (let i = 0; i < 30; i++) r.api.react('celebrate');
    r.api.react('reassure');
    assert.equal(r.events.length, initialCount);
    assert.equal(r.pendingTimers, 1);
    r.advance(960);
    assert.equal(r.events.length, initialCount + 4);
    assert.ok(r.events.slice(initialCount).every(e => e.element.attrs.dur === '0.88s'));
    r.advance(880);
    assert.equal(r.pendingTimers, 0);
});

test('background cancels both active and queued work; foreground resumes only idle', () => {
    const r = rig(); r.api.resume(); r.api.react('celebrate'); r.api.react('acknowledge');
    const count = r.events.length;
    r.api.pause(); r.advance(5000); r.api.resume();
    assert.equal(r.events.length, count);
    assert.equal(r.pendingTimers, 0);
    assert.ok(r.created.filter(e => e.name === 'animateTransform').every(e => e.ended));
    assert.equal(r.resets, 1);
    assert.equal(r.api.react('reassure'), true);
});

test('unknown input and unavailable optional anatomy degrade safely', () => {
    const r = rig(['[aria-label="Arm_R"]', '[aria-label="FlowerRoot"]']); r.api.resume();
    for (const name of ['constructor', '__proto__', 'missing']) assert.equal(r.api.react(name), false);
    assert.equal(r.api.react('celebrate'), true);
    assert.equal(r.events.length, 3);
    r.api.pause();
    assert.equal(r.pendingTimers, 0);
});
