(function (global) {
  "use strict";

  function stored() {
    try { return global.localStorage.getItem("expilot.touch"); } catch (error) { return null; }
  }

  function touch() {
    var forced = new URLSearchParams(global.location.search).get("touch");
    if (forced === "1" || forced === "0") {
      try { global.localStorage.setItem("expilot.touch", forced === "1" ? "on" : "off"); } catch (error) {}
      return forced === "1";
    }
    var kept = stored();
    if (kept === "on") return true;
    if (kept === "off") return false;
    return global.matchMedia && global.matchMedia("(pointer: coarse)").matches;
  }

  function touchTile() {
    return Math.min(global.innerWidth, global.innerHeight) >= 700 ? 32 : 24;
  }

  function touchZones(el) {
    var zones = [];
    var stick = el.querySelector(".stick");
    if (stick) zones.push({ stick: stick, knob: stick.querySelector(".knob"), distance: 8, deadzone: 0.15, push: { action: "thrust", beyond: 0.45, least: 0.3, gain: 1.4 } });
    el.querySelectorAll("[data-action]").forEach(function (button) {
      zones.push({ action: button.dataset.action, element: button });
    });
    return zones;
  }

  function touchPage(el) {
    document.documentElement.classList.add("playing");
    var page = el.closest(".arena-page") || el;
    page.addEventListener("touchmove", function (event) { event.preventDefault(); }, { passive: false });
    page.addEventListener("gesturestart", function (event) { event.preventDefault(); }, { passive: false });
    var more = el.querySelector(".more");
    if (more) more.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      el.classList.toggle("open");
    });
    var swap = el.querySelector(".swap");
    var swapped = function () { try { return global.localStorage.getItem("expilot.touch.side") === "swapped"; } catch (error) { return false; } };
    el.classList.toggle("swapped", swapped());
    if (swap) swap.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      var now = !el.classList.contains("swapped");
      el.classList.toggle("swapped", now);
      try { global.localStorage.setItem("expilot.touch.side", now ? "swapped" : "normal"); } catch (error) {}
    });
    var full = el.querySelector(".full");
    if (full) full.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      var root = document.documentElement;
      if (document.fullscreenElement) {
        if (document.exitFullscreen) document.exitFullscreen();
      } else if (root.requestFullscreen) {
        root.requestFullscreen().catch(function () {});
      }
    });
    if (el.dataset.spectate) el.classList.add("spectating");
  }

  function touchZoom(el, game) {
    var out = el.querySelector(".zoom-out");
    var back = el.querySelector(".zoom-in");
    if (out) out.addEventListener("pointerdown", function (event) { event.preventDefault(); game.zoomBy(0.7); });
    if (back) back.addEventListener("pointerdown", function (event) { event.preventDefault(); game.zoomBy(1 / 0.7); });
  }

  function musicToggles(el, game) {
    var off = function () { try { return global.localStorage.getItem("expilot.music") === "off"; } catch (error) { return false; } };
    var buttons = el.querySelectorAll(".music-toggle");
    var show = function (isOff) { buttons.forEach(function (button) { button.classList.toggle("off", isOff); }); };
    show(off());
    if (off()) game.music(false);
    buttons.forEach(function (button) {
      button.addEventListener("pointerdown", function (event) {
        event.preventDefault();
        var now = !off();
        try { global.localStorage.setItem("expilot.music", now ? "off" : "on"); } catch (error) {}
        show(now);
        game.music(!now);
      });
    });
  }

  function leavePage() {
    document.documentElement.classList.remove("playing");
  }

  global.ExPilot = { touch: touch, touchTile: touchTile, touchZones: touchZones, touchPage: touchPage, touchZoom: touchZoom, musicToggles: musicToggles, leavePage: leavePage };
})(window);
