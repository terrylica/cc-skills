# The live age marker

A self-contained snippet: no library, no CDN. Put the CSS in the page's `<style>`, a marker beside each page's exact time, the legend on an index, and the script once before `</body>`.

## Markup

```html
<!-- one marker per page; data-ts is the Unix time (seconds) of the last change to the page's inputs -->
<span class="age" data-ts="1794700000"
  ><i class="age-dot" aria-hidden="true"></i
  ><span class="age-txt">changed</span></span
>
· 2026-11-14 14:18 (zone) · v1.2.3 · commit abc1234 · source
path/to/page_builder.py

<!-- the legend, once per index -->
<p class="age-key">
  Age of each page's last change: <span class="end">just now</span
  ><span class="sw" style="background:#d23f18"></span
  ><span class="sw" style="background:#d55403"></span
  ><span class="sw" style="background:#d56701"></span
  ><span class="sw" style="background:#d67807"></span
  ><span class="sw" style="background:#d78707"></span
  ><span class="sw" style="background:#cd944a"></span
  ><span class="sw" style="background:#c49f6e"></span
  ><span class="sw" style="background:#bba98e"></span
  ><span class="sw" style="background:#b3b1ad"></span
  ><span class="end">a month or more</span>
</p>
```

The text inside `.age-txt` is what a reader sees without JavaScript; the exact moment beside it carries the information then.

Where the time comes from: the commit time of the last commit that changed the page's source file, or its builder and the files the builder reads (`git log -1 --format=%ct -- <paths>`). Not the deploy time: redeploying an unchanged page must not make it look new.

## CSS

```css
.age {
  white-space: nowrap;
  font-weight: 600;
}
.age-dot {
  display: inline-block;
  width: 9px;
  height: 9px;
  border-radius: 50%;
  margin-right: 0.4em;
  vertical-align: 0.05em;
  visibility: hidden;
}
.age-key {
  font-size: 0.85em;
  color: #666;
}
.age-key .sw {
  display: inline-block;
  width: 14px;
  height: 9px;
  margin-right: 2px;
  border-radius: 2px;
  vertical-align: middle;
}
.age-key .end {
  margin: 0 0.4em;
}
```

## Script

Set `LOCALE`, `NOW` (shown under a minute), `WRAP` (where the relative phrase goes) and the fallback `UNITS` (largest first: years, months, weeks, days, hours, minutes) for the page's language. Examples: English `"en"`, `"changed just now"`, `"changed {}"`, `["years","months","weeks","days","hours","minutes"]`, `"{n} {u} ago"`; Chinese `"zh-CN"`, `"刚刚更新"`, `"{}更新"`, `["年","个月","周","天","小时","分钟"]`, `"{n} {u}前"`.

```html
<script>
  (function () {
    var C = {
      locale: "en",
      now: "changed just now",
      wrap: "changed {}",
      units: ["years", "months", "weeks", "days", "hours", "minutes"],
      ago: "{n} {u} ago",
      full: 720, // hours at which the scale reaches its grey end (a month)
      heat: [
        "#d23f18",
        "#d55403",
        "#d56701",
        "#d67807",
        "#d78707",
        "#cd944a",
        "#c49f6e",
        "#bba98e",
        "#b3b1ad",
      ],
    };
    var U = [
      [31536000, "year"],
      [2592000, "month"],
      [604800, "week"],
      [86400, "day"],
      [3600, "hour"],
      [60, "minute"],
    ];
    var rtf = null;
    try {
      rtf = new Intl.RelativeTimeFormat(C.locale, { numeric: "auto" });
    } catch (e) {
      rtf = null;
    }
    function words(s) {
      if (s < 60) return C.now;
      for (var i = 0; i < U.length; i++) {
        if (s >= U[i][0]) {
          var n = Math.floor(s / U[i][0]);
          var w = rtf
            ? rtf.format(-n, U[i][1])
            : C.ago.replace("{n}", n).replace("{u}", C.units[i]);
          return C.wrap.replace("{}", w);
        }
      }
    }
    function step(s) {
      var t = Math.log(1 + s / 3600) / Math.log(1 + C.full);
      return C.heat[
        Math.round(Math.min(1, Math.max(0, t)) * (C.heat.length - 1))
      ];
    }
    function tick() {
      var now = Date.now() / 1000,
        els = document.querySelectorAll(".age[data-ts]");
      for (var i = 0; i < els.length; i++) {
        var s = Math.max(0, now - +els[i].getAttribute("data-ts"));
        var dot = els[i].querySelector(".age-dot"),
          txt = els[i].querySelector(".age-txt");
        if (txt) txt.textContent = words(s);
        if (dot) {
          dot.style.background = step(s);
          dot.style.visibility = "visible";
        }
      }
    }
    tick();
    setInterval(tick, 60000);
  })();
</script>
```

`numeric: "auto"` gives natural words where the language has them ("yesterday", "last week", 昨天, 上个月). Without `Intl.RelativeTimeFormat` the fallback units are used.

## The heat steps

Nine steps along two straight segments in OKLCH: red-orange (L 0.58, C 0.19, h 35), amber (L 0.69, C 0.15, h 68), neutral grey (L 0.76, C 0.006, h 80). Lightness rises monotonically from step to step; a step outside the sRGB gamut keeps its lightness and hue and loses chroma until it fits (no clipping). Every step has at least 2:1 contrast on a white surface. They are written as hex, not `color-mix()`, so older browser engines show them too.

| step | hex       | OKLCH L | C     |
| ---- | --------- | ------- | ----- |
| 0    | `#d23f18` | 0.580   | 0.190 |
| 1    | `#d55403` | 0.607   | 0.178 |
| 2    | `#d56701` | 0.635   | 0.164 |
| 3    | `#d67807` | 0.662   | 0.154 |
| 4    | `#d78707` | 0.690   | 0.150 |
| 5    | `#cd944a` | 0.708   | 0.114 |
| 6    | `#c49f6e` | 0.725   | 0.078 |
| 7    | `#bba98e` | 0.742   | 0.042 |
| 8    | `#b3b1ad` | 0.760   | 0.006 |

The step for an age of `h` hours is `round(clamp(log(1 + h) / log(1 + 720), 0, 1) × 8)`: about a day lands on step 4 (amber), a week on step 6, a month on step 8. On a dark surface, re-derive the steps against that surface rather than reuse these.
