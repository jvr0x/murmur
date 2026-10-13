/* Progressive enhancement only: the page is fully readable without JS. */
(function () {
  "use strict";

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Scroll reveal. Elements stay visible if IntersectionObserver is unavailable.
  var revealables = [].slice.call(document.querySelectorAll(
    ".step, .card, .arch-row, .ms, .table-card, .code, .quote, .stat"
  ));
  revealables.forEach(function (el) { el.classList.add("reveal"); });

  if (!reduce && "IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          e.target.classList.add("in");
          io.unobserve(e.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.05 });
    revealables.forEach(function (el) { io.observe(el); });
  } else {
    revealables.forEach(function (el) { el.classList.add("in"); });
  }

  // Hero mock: walk the dictation states, typing the final text on the way.
  var hud = document.querySelector(".hud");
  var status = hud && hud.querySelector(".status");
  var bars = hud && hud.querySelector(".bars");
  var typed = document.querySelector("[data-typing]");
  if (!hud || !status || !typed) return;

  var SENTENCE = "Deploy it tonight, and write the runbook tomorrow morning.";
  var CYCLE = [
    { label: "Listening\u2026", bars: true, text: null },
    { label: "Transcribing\u2026", bars: false, text: null },
    { label: "Polishing\u2026", bars: false, text: null },
    { label: "Inserting\u2026", bars: false, text: "full" },
    { label: "Ready", bars: false, text: "keep" }
  ];

  if (reduce) {
    status.textContent = "Listening\u2026";
    typed.textContent = SENTENCE;
    return;
  }

  var i = 0;
  var charTimer = null;

  function typeOut() {
    var n = 0;
    typed.textContent = "";
    clearInterval(charTimer);
    charTimer = setInterval(function () {
      n += 1;
      typed.textContent = SENTENCE.slice(0, n);
      if (n >= SENTENCE.length) clearInterval(charTimer);
    }, 22);
  }

  function step() {
    var s = CYCLE[i];
    status.textContent = s.label;
    hud.classList.toggle("is-idle", !s.bars);

    if (s.text === "full") {
      typeOut();
    } else if (s.text === "keep") {
      // Leave the finished sentence on screen during the pause before looping.
    } else {
      typed.textContent = "";
    }

    var hold = s.bars ? 2400 : (s.text === "full" ? 3400 : (s.text === "keep" ? 2600 : 1700));
    i = (i + 1) % CYCLE.length;
    setTimeout(step, hold);
  }

  step();
})();
