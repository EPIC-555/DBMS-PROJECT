/* TripNest interface effects.
 *
 * Dependency-free, build-free. Drop in static/ and add
 *     <script src="/static/fx.js?v=1" defer></script>
 * before </body>, next to snow.js.
 *
 * Six effects, all injected from this one file so the pages need no markup change:
 *   1. scroll reveal  - cards and rows fade and rise as they enter the viewport
 *   2. count up       - integers in stat tiles roll from 0 to their value
 *   3. tilt           - cards lean slightly toward the pointer
 *   4. cursor glow    - a soft light that follows the pointer over cards
 *   5. press          - instant scale-down while a button is held
 *   6. magnetic       - buttons drift a few px toward the pointer
 *
 * Click ripple is deliberately NOT included: index.html, app.html and
 * login.html already install their own, so adding a second would double it.
 *
 * Two safety properties matter more than the effects themselves:
 *   - nothing is hidden unless the observer has already seen the element, and a
 *     watchdog reveals everything after 3s, so a failure cannot blank the page;
 *   - prefers-reduced-motion returns before any style is added.
 *
 * Tune the CONFIG block. Set window.TN_UX = false before this script loads to
 * switch the effects off.
 */
(function () {
  "use strict";

  var CONFIG = {
    reveal: true,      // fade/slide elements in on scroll
    countUp: true,     // roll integer stat values up from zero
    tilt: true,        // subtle 3D lean toward the pointer
    glow: true,        // pointer-following glow on cards
    press: true,       // scale-down while a button is held
    magnetic: true,    // buttons drift toward the pointer
    revealY: 18,       // px an element travels as it appears
    revealMs: 620,     // reveal duration, matches the CSS below
    tiltMax: 5,        // degrees at the far corner
    magnetMax: 4,      // px a button may drift
    countMs: 900       // count-up duration
  };

  if (window.TN_UX === false) return;
  if (document.querySelector(".tn-ux")) return;

  var root = document.documentElement;
  var reduced = window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  // Reduced motion: no animation at all. The page is already usable without us.
  if (reduced) {
    root.classList.add("tn-ux-static");
    return;
  }

  var coarse = window.matchMedia && window.matchMedia("(hover: none)").matches;
  root.classList.add("tn-ux-on");

  var style = document.createElement("style");
  style.className = "tn-ux";
  style.textContent = [
    /* ---- 1. scroll reveal ---- */
    ".tn-reveal{opacity:0;transform:translateY(" + CONFIG.revealY + "px)}",
    ".tn-in{opacity:1;transform:none;",
    "transition:opacity " + CONFIG.revealMs + "ms cubic-bezier(.2,.8,.2,1),",
    "transform " + CONFIG.revealMs + "ms cubic-bezier(.2,.8,.2,1)}",
    /* a grid staggers its own children instead of moving as one block */
    ".tn-stagger>*{opacity:0;transform:translateY(" + (CONFIG.revealY - 4) + "px)}",
    ".tn-stagger.tn-in>*{opacity:1;transform:none;",
    "transition:opacity .5s ease,transform .5s cubic-bezier(.2,.8,.2,1)}",
    ".tn-stagger.tn-in>*:nth-child(1){transition-delay:0s}",
    ".tn-stagger.tn-in>*:nth-child(2){transition-delay:.06s}",
    ".tn-stagger.tn-in>*:nth-child(3){transition-delay:.12s}",
    ".tn-stagger.tn-in>*:nth-child(4){transition-delay:.18s}",
    ".tn-stagger.tn-in>*:nth-child(5){transition-delay:.24s}",
    ".tn-stagger.tn-in>*:nth-child(6){transition-delay:.3s}",

    /* ---- 3. tilt ---- */
    /* shorter transition than the page's .24s so the lean tracks the pointer
       instead of rubber-banding behind it */
    ".tn-tilt{transform-style:preserve-3d;will-change:transform;",
    "transition:transform .12s ease-out!important}",

    /* ---- 4. cursor glow ---- */
    /* isolation makes the card a stacking context, so a z-index:-1 pseudo paints
       above the card's own background but BEHIND its text. Without it the glow
       would sit on top of the copy and tint it. */
    ".tn-glow{position:relative;isolation:isolate}",
    ".tn-glow::after{content:'';position:absolute;inset:0;border-radius:inherit;",
    "pointer-events:none;opacity:0;transition:opacity .3s ease;z-index:-1;",
    "background:radial-gradient(320px circle at var(--tn-x,50%) var(--tn-y,50%),",
    "rgba(88,166,255,.16),transparent 62%)}",
    ".tn-glow:hover::after{opacity:1}",

    /* ---- 5. pressed ---- */
    /* `scale`, not `transform`, so a press does not wipe out the page's own
       hover transform while the button is held */
    ".tn-press{scale:.965!important;transition:scale .07s ease!important}",

    /* ---- 6. magnetic ---- */
    ".tn-magnet{transition:translate .18s cubic-bezier(.2,.8,.2,1)}"
  ].join("");

  /* ------------------------------------------------------------ 1. reveal */

  var GRID = ".grid";

  function setupReveal() {
    if (!CONFIG.reveal || !("IntersectionObserver" in window)) return;

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        var el = e.target;
        io.unobserve(el);
        // rAF so the transition runs rather than being coalesced with the class add.
        requestAnimationFrame(function () { el.classList.add("tn-in"); });
        // Once it has arrived, drop every class we added. The element then falls
        // back to the page's own CSS, so its hover lift and .24s transition are
        // not stuck behind our 620ms reveal transition.
        setTimeout(function () {
          el.classList.remove("tn-reveal", "tn-stagger", "tn-in");
          // Mark it done so a later rescan never hides it again, which would
          // make content the user has already scrolled past flicker.
          el.dataset.tnDone = "1";
        }, CONFIG.revealMs + 60);
      });
    }, { rootMargin: "0px 0px -6% 0px", threshold: 0.06 });

    var hidden = [];

    function hide(el, stagger) {
      if (el.dataset.tnDone) return;
      if (el.classList.contains("tn-reveal") || el.classList.contains("tn-stagger")) return;
      // Never touch overlays, toasts or the snow layer.
      if (el.closest("#toasts, .modal, .tn-fx")) return;
      // Anything already on screen just stays put; no flash on first paint.
      if (el.getBoundingClientRect().top < window.innerHeight * 0.92) return;
      el.classList.add(stagger ? "tn-stagger" : "tn-reveal");
      hidden.push(el);
      io.observe(el);
    }

    function scan() {
      var grids = document.querySelectorAll(GRID);
      for (var i = 0; i < grids.length; i++) hide(grids[i], true);

      // Individual blocks outside a grid reveal on their own.
      var solo = document.querySelectorAll(
        ".card, .hero, .banner, .stat, .accessrow, .dest, .hotel, " +
        ".query, .result, .empty, .section-head, tbody tr, section.view>*"
      );
      for (var j = 0; j < solo.length; j++) {
        var el = solo[j];
        if (el.closest(GRID)) continue; // its grid already staggers it
        hide(el, false);
      }
    }

    scan();

    // Watchdog for the elements that are ALREADY in view at load. Those are the
    // ones a stuck observer would leave invisible on first paint, which is the
    // only outcome worth guarding against. Off-screen elements are left to the
    // observer so the scroll reveal still works further down a long page.
    setTimeout(function () {
      for (var i = 0; i < hidden.length; i++) {
        var el = hidden[i];
        if (el.classList.contains("tn-in")) continue;
        if (el.getBoundingClientRect().top < window.innerHeight) {
          el.classList.add("tn-in");
          el.dataset.tnDone = "1";
          io.unobserve(el);
        }
      }
    }, 2500);

    // Dynamic content (tab switches, filters, fresh API data) arrives later.
    var pending = false;
    new MutationObserver(function () {
      if (pending) return;
      pending = true;
      setTimeout(function () { pending = false; scan(); }, 140);
    }).observe(document.body, { childList: true, subtree: true });
  }

  /* --------------------------------------------------------- 2. count up */

  function setupCountUp() {
    if (!CONFIG.countUp || !("IntersectionObserver" in window)) return;

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        io.unobserve(e.target);
        run(e.target);
      });
    }, { threshold: 0.5 });

    function run(el) {
      if (el.dataset.tnCounted) return;
      var raw = el.textContent.trim();
      // Plain integers only. Money, dates, percentages and labels are left alone.
      if (!/^\d{1,6}$/.test(raw)) return;
      var target = parseInt(raw, 10);
      if (target === 0) return;
      el.dataset.tnCounted = "1";

      var start = performance.now();
      var ease = function (t) { return 1 - Math.pow(1 - t, 3); };
      function step(now) {
        var t = Math.min(1, (now - start) / CONFIG.countMs);
        el.textContent = Math.round(target * ease(t)).toLocaleString();
        if (t < 1) requestAnimationFrame(step);
        else el.textContent = target.toLocaleString();
      }
      requestAnimationFrame(step);
    }

    function scan() {
      var nodes = document.querySelectorAll(".stat .v, .stat b, .kv b");
      for (var i = 0; i < nodes.length; i++) {
        if (!nodes[i].dataset.tnCounted) io.observe(nodes[i]);
      }
    }

    scan();
    var pending = false;
    new MutationObserver(function () {
      if (pending) return;
      pending = true;
      setTimeout(function () { pending = false; scan(); }, 160);
    }).observe(document.body, { childList: true, subtree: true });
  }

  /* ------------------------------------------------- 3/4/6. pointer effects */

  // Cards that are safe to lean and glow: not forms, and not containers of form
  // controls. The login page's card IS the sign-in form, and tilting a form
  // while someone types a password is actively hostile.
  var CARD_SEL = ".card, .dest, .hotel";
  var MAG_SEL = ".act, .btn, .link-btn, .pill, button[type=submit]";

  function isInteractive(card) {
    return card.matches("form") ||
      !!card.querySelector("input, select, textarea, button[type=submit]");
  }

  // Tilt, glow and magnetic all follow the pointer, so they share one listener
  // and one getBoundingClientRect per move rather than three of each.
  function setupPointer() {
    if (coarse) return;

    var tiltCard = null;
    var magBtn = null;

    function resetTilt() {
      if (!tiltCard) return;
      tiltCard.style.transform = "";
      tiltCard.classList.remove("tn-tilt");
      tiltCard = null;
    }

    function resetMag() {
      if (!magBtn) return;
      magBtn.style.translate = "";
      magBtn.classList.remove("tn-magnet");
      magBtn = null;
    }

    function attachGlow() {
      var cards = document.querySelectorAll(CARD_SEL);
      for (var i = 0; i < cards.length; i++) {
        if (!isInteractive(cards[i])) cards[i].classList.add("tn-glow");
      }
    }
    if (CONFIG.glow) attachGlow();

    document.addEventListener("pointermove", function (e) {
      var t = e.target;
      var card = t.closest && t.closest(CARD_SEL);
      if (card && isInteractive(card)) card = null;

      /* ---- tilt ---- */
      if (CONFIG.tilt) {
        if (card !== tiltCard) resetTilt();
        if (card) {
          tiltCard = card;
          card.classList.add("tn-tilt");
          var r = card.getBoundingClientRect();
          var px = (e.clientX - r.left) / r.width;
          var py = (e.clientY - r.top) / r.height;
          var rx = (0.5 - py) * CONFIG.tiltMax * 2;
          var ry = (px - 0.5) * CONFIG.tiltMax * 2;
          card.style.transform = "perspective(900px) rotateX(" +
            rx.toFixed(2) + "deg) rotateY(" + ry.toFixed(2) + "deg)";
        }
      }

      /* ---- cursor glow ---- */
      if (CONFIG.glow && card && card.classList.contains("tn-glow")) {
        var gr = card.getBoundingClientRect();
        card.style.setProperty("--tn-x", (e.clientX - gr.left) + "px");
        card.style.setProperty("--tn-y", (e.clientY - gr.top) + "px");
      }

      /* ---- magnetic ---- */
      if (CONFIG.magnetic) {
        var b = t.closest && t.closest(MAG_SEL);
        if (b !== magBtn) resetMag();
        if (b && !b.classList.contains("tn-press")) {
          var br = b.getBoundingClientRect();
          // Zero width means the control is in a hidden tab; leave it alone.
          if (br.width) {
            magBtn = b;
            b.classList.add("tn-magnet");
            var dx = (e.clientX - (br.left + br.width / 2)) / (br.width / 2);
            var dy = (e.clientY - (br.top + br.height / 2)) / (br.height / 2);
            // The independent `translate` property, not `transform`, so this
            // composes with the page's own hover lift instead of overriding it.
            b.style.translate = (dx * CONFIG.magnetMax).toFixed(2) + "px " +
              (dy * CONFIG.magnetMax).toFixed(2) + "px";
          }
        }
      }
    }, { passive: true });

    document.addEventListener("pointerleave", function () {
      resetTilt();
      resetMag();
    });

    if (CONFIG.glow) {
      var pending = false;
      new MutationObserver(function () {
        if (pending) return;
        pending = true;
        setTimeout(function () { pending = false; attachGlow(); }, 220);
      }).observe(document.body, { childList: true, subtree: true });
    }
  }

  /* ----------------------------------------------------------- 5. pressed */

  function setupPress() {
    if (!CONFIG.press) return;
    var sel = "button, .btn, .link-btn, .heart, .pill";
    document.addEventListener("pointerdown", function (e) {
      var b = e.target.closest && e.target.closest(sel);
      if (!b || b.disabled) return;
      b.classList.add("tn-press");
    });
    ["pointerup", "pointercancel", "pointerleave"].forEach(function (ev) {
      document.addEventListener(ev, function (e) {
        var b = e.target.closest && e.target.closest(sel);
        if (b) b.classList.remove("tn-press");
      });
    });
  }

  function init() {
    if (document.head) document.head.appendChild(style);
    // One effect failing must never take the others, or the page, down with it.
    [setupReveal, setupCountUp, setupPointer, setupPress]
      .forEach(function (fn) { try { fn(); } catch (err) {} });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
