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

  function askTilt() {
    var Orientation = global.DeviceOrientationEvent;
    if (!Orientation) return Promise.resolve("unsupported");
    if (typeof Orientation.requestPermission !== "function") return Promise.resolve("granted");
    return Orientation.requestPermission().then(function (state) { return state; }, function () { return "denied"; });
  }

  function touchTilt(el) {
    if (el.dataset.tilt !== "on") return null;
    return { range: 22, deadzone: 0.12, distance: 8, invert: el.dataset.tiltInvert === "on" };
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
    el.classList.toggle("swapped", el.dataset.side === "right");
    el.classList.toggle("tilting", el.dataset.tilt === "on");
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

  function macOnChromeOrFirefox() {
    var ua = global.navigator.userAgent || "";
    var mac = /Mac/.test(global.navigator.platform || "") || /Macintosh/.test(ua);
    var chrome = /Chrome\//.test(ua) && !/Edg\//.test(ua);
    var firefox = /Firefox\//.test(ua);
    return mac && (chrome || firefox);
  }

  function padHelp(found) {
    if (!global.isSecureContext) return "The browser hands controllers only to pages on https or localhost — this page is on neither, so none can be seen.";
    if (!global.Gamepad || !global.Gamepad.available()) return "This browser has no controller support.";
    if (found) return "Click a row below and press a control on it to bind.";
    var lines = ["Nothing seen yet: browsers keep a controller hidden until a button is pressed on it while this page is in front."];
    if (macOnChromeOrFirefox()) lines.push("On a Mac, Chrome and Firefox see only controllers that show up as plain HID devices; the steps below get most of them seen.");
    return lines.join(" ");
  }

  function padCapture(form) {
    var status = form.querySelector("[data-pad-status]");
    var help = form.querySelector("[data-pad-help]");
    var macHelp = form.querySelector("[data-pad-mac]");
    if (macHelp) macHelp.hidden = !macOnChromeOrFirefox();

    var names = {};
    var show = function () {
      var seen = Object.keys(names).map(function (id) { return names[id]; });
      if (status) status.textContent = seen.length ? "controller: " + seen.join(", ") : "looking for a controller — press a button on it with this page in front";
      if (help) help.textContent = padHelp(seen.length > 0);
    };
    show();
    if (!global.Gamepad || !global.Gamepad.available()) return null;
    var focused = null;
    var axes = {};
    form.addEventListener("focusin", function (event) { if (event.target.tagName === "INPUT") focused = event.target; });
    form.addEventListener("focusout", function () { focused = null; });
    var add = function (word) {
      if (!focused) return;
      var words = focused.value.split(/\s+/).filter(function (w) { return w; });
      if (words.indexOf(word) < 0) words.push(word);
      focused.value = words.join(" ");
    };
    return global.Gamepad.watch(function (line) {
      var words = line.split(" ");
      if (words[0] === "device") { names[words[1]] = words.slice(2).join(" "); show(); }
      if (words[0] === "gone") { delete names[words[1]]; show(); }
      if (words[0] === "button" && words[3] === "1") add(words[2]);

      if (words[0] === "axis") {
        var value = parseFloat(words[3]);
        var was = axes[words[2]] || 0;
        axes[words[2]] = value;
        if (Math.abs(value) >= 0.6 && Math.abs(was) < 0.6) add(words[2] + (value < 0 ? "-" : "+"));
      }
    });
  }

  function leavePage() {
    document.documentElement.classList.remove("playing");
  }

  global.ExPilot = { touch: touch, touchTile: touchTile, touchZones: touchZones, touchTilt: touchTilt, askTilt: askTilt, touchPage: touchPage, touchZoom: touchZoom, musicToggles: musicToggles, padCapture: padCapture, leavePage: leavePage };
})(window);
