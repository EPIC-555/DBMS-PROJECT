/* TripNest winter ambience.
 *
 * Dependency-free, build-free. Drop in static/ and add
 *     <script src="/static/snow.js?v=5" defer></script>
 * before </body>.
 *
 * Two kinds of falling thing:
 *   - snowflakes: real six-armed crystals, drawn as inline SVG so they stay
 *     crisp at any size. They fall, sway, and slowly spin.
 *   - snowballs: soft round blobs, larger and faster, for depth.
 *
 * Everything renders in one fixed layer at z-index -1, so it paints over the
 * page background but stays BEHIND all content. Text and controls are never
 * covered, and pointer-events:none means clicks always reach the page.
 *
 * Tune the CONFIG block below. Set window.TN_WINTER = false before this
 * script loads to switch the effects off entirely.
 */
(function () {
  "use strict";

  var CONFIG = {
    flakes: 30,      // six-armed crystal snowflakes
    balls: 14,       // round snowballs
    stars: 26,       // twinkling background stars
    vignette: true,  // soft frosted glow around the edges
    speedMin: 9,     // slowest fall, seconds to cross the screen
    speedMax: 20,    // fastest fall
    maxOpacity: 0.9  // ceiling for brightness
  };

  if (window.TN_WINTER === false) return;
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  if (document.querySelector(".tn-fx")) return;

  var rand = function (a, b) { return a + Math.random() * (b - a); };
  var pick = function (arr) { return arr[Math.floor(Math.random() * arr.length)]; };

  // Build a six-armed crystal as an SVG data URI. Arms radiate from the
  // centre at 60 degrees apart, each with two pairs of side branches.
  function flakeSVG(R, strokeW) {
    var arms = [];
    for (var i = 0; i < 6; i++) {
      arms.push(
        '<g transform="rotate(' + (i * 60) + ' 12 12)">' +
        '<line x1="12" y1="12" x2="12" y2="' + (12 - R).toFixed(2) + '"/>' +
        '<line x1="12" y1="' + (12 - R * 0.55).toFixed(2) + '" x2="' + (12 - R * 0.34).toFixed(2) + '" y2="' + (12 - R * 0.76).toFixed(2) + '"/>' +
        '<line x1="12" y1="' + (12 - R * 0.55).toFixed(2) + '" x2="' + (12 + R * 0.34).toFixed(2) + '" y2="' + (12 - R * 0.76).toFixed(2) + '"/>' +
        '<line x1="12" y1="' + (12 - R * 0.26).toFixed(2) + '" x2="' + (12 - R * 0.20).toFixed(2) + '" y2="' + (12 - R * 0.44).toFixed(2) + '"/>' +
        '<line x1="12" y1="' + (12 - R * 0.26).toFixed(2) + '" x2="' + (12 + R * 0.20).toFixed(2) + '" y2="' + (12 - R * 0.44).toFixed(2) + '"/>' +
        '</g>'
      );
    }
    var svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">' +
      '<g stroke="#ffffff" stroke-width="' + strokeW + '" stroke-linecap="round" fill="none">' +
      arms.join('') + '</g></svg>';
    return 'url("data:image/svg+xml,' + encodeURIComponent(svg) + '")';
  }

  // Three crystal shapes so the snow does not look stamped from one mould.
  var FLAKES = [
    flakeSVG(10.0, 1.5),  // full six-armed star
    flakeSVG(9.2, 1.8),   // slightly stubbier, thicker arms
    flakeSVG(10.4, 1.2)   // longer, finer arms
  ];

  var css = [
    ".tn-fx{position:fixed;inset:0;overflow:hidden;pointer-events:none;z-index:-1}",
    ".tn-fx i{position:absolute;display:block}",

    // Outer element falls straight down; the middle one sways and tilts; the
    // inner one spins. Three transforms compose into a natural drift.
    ".tn-snow i{top:-18vh;",
    "animation-name:tn-fall;animation-timing-function:linear;animation-iteration-count:infinite}",
    ".tn-snow i b{display:block;width:100%;height:100%;",
    "animation-name:tn-sway;animation-timing-function:ease-in-out;",
    "animation-iteration-count:infinite;animation-direction:alternate}",
    ".tn-snow i u{display:block;width:100%;height:100%;background-repeat:no-repeat;",
    "background-position:center;background-size:contain;",
    "animation-name:tn-spin;animation-timing-function:linear;animation-iteration-count:infinite}",

    // crystals: crisp SVG, faint glow so they read against the dark page
    ".tn-flake u{filter:drop-shadow(0 0 3px rgba(255,255,255,.55))}",
    ".tn-flake.far u{filter:drop-shadow(0 0 2px rgba(255,255,255,.35)) blur(.5px)}",

    // snowballs: soft round blobs
    ".tn-ball b{animation-name:tn-sway}",
    ".tn-ball u{border-radius:50%;",
    "background:radial-gradient(circle at 36% 32%,#fff 0%,#fff 46%,rgba(255,255,255,.34) 100%);",
    "box-shadow:0 0 10px rgba(255,255,255,.7)}",
    ".tn-ball.far u{filter:blur(1.5px)}",
    ".tn-ball.mid u{filter:blur(.6px)}",

    "@keyframes tn-fall{",
    "0%{transform:translate3d(0,-18vh,0)}",
    "100%{transform:translate3d(0,118vh,0)}}",
    "@keyframes tn-sway{",
    "from{transform:translateX(calc(var(--amp,10px) * -1)) rotate(-12deg)}",
    "to{transform:translateX(var(--amp,10px)) rotate(12deg)}}",
    "@keyframes tn-spin{",
    "from{transform:rotate(0deg)}",
    "to{transform:rotate(var(--spin,360deg))}}",

    // twinkling stars
    ".tn-stars i{border-radius:50%;background:#cfe4ff;",
    "animation:tn-twinkle var(--dur,5s) ease-in-out infinite}",
    "@keyframes tn-twinkle{",
    "0%,100%{opacity:var(--o-min,.05);transform:scale(.75)}",
    "50%{opacity:var(--o-max,.4);transform:scale(1.15)}}",

    // frosted edge: transparent in the middle, faintly lit at the rim
    ".tn-vignette{position:absolute;inset:0;",
    "background:radial-gradient(125% 95% at 50% 8%,",
    "transparent 58%,rgba(190,220,255,.075) 100%)}"
  ].join("");

  var layer = document.createElement("div");
  layer.className = "tn-fx";
  layer.setAttribute("aria-hidden", "true");

  var snow = document.createElement("div");
  snow.className = "tn-snow";

  // Far particles are small and dim, near ones larger and brighter, which
  // reads as depth. Sizes are px at 1920px wide.
  function spawn(kind, depth, count, sizes, ops) {
    for (var i = 0; i < count; i++) {
      var el = document.createElement("i");
      var mid = document.createElement("b");
      var inner = document.createElement("u");
      el.className = kind + " " + depth;

      var size = rand(sizes[0], sizes[1]);
      el.style.left = rand(0, 100).toFixed(2) + "vw";
      el.style.width = size.toFixed(2) + "px";
      el.style.height = size.toFixed(2) + "px";
      el.style.opacity = rand(ops[0], ops[1]).toFixed(2);
      el.style.animationDuration = rand(CONFIG.speedMin, CONFIG.speedMax).toFixed(2) + "s";
      // Negative delay starts particles mid-fall so the sky is never empty.
      el.style.animationDelay = (-Math.random() * CONFIG.speedMax).toFixed(2) + "s";

      if (kind === "tn-flake") {
        inner.style.backgroundImage = pick(FLAKES);
        // Some crystals spin the other way, which avoids a uniform look.
        var turns = Math.random() < 0.5 ? 360 : -360;
        inner.style.setProperty("--spin", turns + "deg");
        inner.style.animationDuration = rand(9, 22).toFixed(2) + "s";
      }

      // Bigger particles sway further, keeping the motion in proportion.
      mid.style.setProperty("--amp", rand(size * 0.8, size * 1.9).toFixed(1) + "px");
      mid.style.animationDuration = rand(3, 7.5).toFixed(2) + "s";
      mid.style.animationDelay = (-Math.random() * 6).toFixed(2) + "s";

      mid.appendChild(inner);
      el.appendChild(mid);
      snow.appendChild(el);
    }
  }

  spawn("tn-flake", "far",  Math.round(CONFIG.flakes * 0.34), [9, 16],   [0.22, 0.42]);
  spawn("tn-flake", "mid",  Math.round(CONFIG.flakes * 0.36), [15, 24],  [0.36, 0.60]);
  spawn("tn-flake", "near", Math.round(CONFIG.flakes * 0.30), [23, 34],  [0.55, CONFIG.maxOpacity]);

  spawn("tn-ball", "far",  Math.round(CONFIG.balls * 0.34), [5, 8],   [0.20, 0.36]);
  spawn("tn-ball", "mid",  Math.round(CONFIG.balls * 0.36), [8, 13],  [0.30, 0.52]);
  spawn("tn-ball", "near", Math.round(CONFIG.balls * 0.30), [13, 22], [0.45, CONFIG.maxOpacity]);

  var stars = document.createElement("div");
  stars.className = "tn-stars";
  for (var s = 0; s < CONFIG.stars; s++) {
    var st = document.createElement("i");
    var ss = rand(1, 2).toFixed(2);
    st.style.left = rand(0, 100).toFixed(2) + "vw";
    st.style.top = rand(0, 100).toFixed(2) + "vh";
    st.style.width = ss + "px";
    st.style.height = ss + "px";
    st.style.setProperty("--dur", rand(3.5, 8).toFixed(2) + "s");
    st.style.setProperty("--o-min", rand(0.03, 0.09).toFixed(2));
    st.style.setProperty("--o-max", rand(0.22, 0.45).toFixed(2));
    st.style.animationDelay = (-Math.random() * 8).toFixed(2) + "s";
    stars.appendChild(st);
  }

  var style = document.createElement("style");
  style.textContent = css;

  layer.appendChild(stars);
  layer.appendChild(snow);
  if (CONFIG.vignette) {
    var v = document.createElement("div");
    v.className = "tn-vignette";
    layer.appendChild(v);
  }

  document.head.appendChild(style);
  document.body.appendChild(layer);
})();
