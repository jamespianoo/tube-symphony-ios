#!/usr/bin/env node
'use strict';
// Export the web app's geometry and look into the data files the iOS app bundles.
//
// The website builds its route curves at boot, in the browser, from the station
// lists and waypoints (buildSmoothPath and friends in js/map/map.js). The app must
// place a train at exactly the point the website does, so rather than port that
// code this script runs it: it loads the same scripts the Schedule service loads
// (services/schedule/sim-host.js, jsdom, simulation off) and writes down the
// result. The phone then does nothing at boot but read a few files.
//
//   npm install
//   node export.js --app-root ../../../tube-symphony
//
// Writes to ../../TubeSymphony/Resources/TubeData/ (override with --out):
//   lines.json     line colours, names, carriage sizes
//   routes.json    per route: station ids/distances/coords, and where its points sit in routes.bin
//   routes.bin     the route curves: little-endian Float32 triplets
//                  (lng − ORIGIN_LNG, lat − ORIGIN_LAT, cumulative metres)
//   tracks.json    the drawn track: each line's routes deduplicated, [[line, [[lng, lat], …]], …]
//   stations.json  station groups as the map draws them (name, coord, line colours)
//   scale.json     the phone view profile and the zoom-scale constants trains/blips size by
//   basemap-style.json  the self-hosted basemap style, with {ORIGIN} filled in
//
// Run it again whenever lines, stations or waypoints change on the website.

const fs = require('fs');
const path = require('path');
const http = require('http');
const Module = require('module');

const arg = (n, d) => { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; };
// Default: a checkout of the website beside this repo (tube-symphony, formerly labs-tube-map).
const APP_ROOT = path.resolve(arg('app-root', ['tube-symphony', 'labs-tube-map']
    .map((d) => path.join(__dirname, '../../..', d))
    .find((d) => fs.existsSync(path.join(d, 'services/schedule/sim-host.js'))) || path.join(__dirname, '../../../tube-symphony')));
const OUT = path.resolve(arg('out', path.join(__dirname, '../../TubeSymphony/Resources/TubeData')));
const ORIGIN = arg('origin', 'https://tubesymphony.com');
// Simplification tolerance for the route curves, metres. The website's curves
// carry a point every ~7 m; most of them are on straight track.
const TOLERANCE_M = Number(arg('tolerance', 0.3));
const ORIGIN_LNG = -0.1275, ORIGIN_LAT = 51.5072;

// sim-host.js requires jsdom from its own folder; point module resolution here.
process.env.NODE_PATH = [path.join(__dirname, 'node_modules'), process.env.NODE_PATH || ''].filter(Boolean).join(path.delimiter);
Module._initPaths();

const MIME = { '.json': 'application/json', '.js': 'text/javascript' };
function serveStatic(root) {
    // sim-host's fetch shim talks HTTP to an origin; boot only needs static files.
    const server = http.createServer((req, res) => {
        const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '');
        const file = path.join(root, rel);
        if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
        res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' });
        fs.createReadStream(file).pipe(res);
    });
    return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

/** Ramer–Douglas–Peucker over one route; returns the indices kept. */
function simplify(coords, tol) {
    const n = coords.length;
    if (n <= 2) return coords.map((_, i) => i);
    const kx = 111320 * Math.cos(ORIGIN_LAT * Math.PI / 180), ky = 110540;
    const xy = coords.map(([lng, lat]) => [lng * kx, lat * ky]);
    const keep = new Uint8Array(n); keep[0] = keep[n - 1] = 1;
    const stack = [[0, n - 1]];
    while (stack.length) {
        const [a, b] = stack.pop();
        const [ax, ay] = xy[a], [bx, by] = xy[b];
        const dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
        let worst = -1, worstD = tol;
        for (let i = a + 1; i < b; i++) {
            const [px, py] = xy[i];
            let t = len2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / len2 : 0;
            t = Math.max(0, Math.min(1, t));
            const ex = ax + dx * t - px, ey = ay + dy * t - py;
            const d = Math.sqrt(ex * ex + ey * ey);
            if (d > worstD) { worstD = d; worst = i; }
        }
        if (worst > 0) { keep[worst] = 1; stack.push([a, worst], [worst, b]); }
    }
    const out = []; for (let i = 0; i < n; i++) if (keep[i]) out.push(i);
    return out;
}

const round = (v, dp) => Math.round(v * 10 ** dp) / 10 ** dp;
const parseRgb = (s) => {
    const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(String(s));
    if (m) return '#' + [m[1], m[2], m[3]].map((v) => Number(v).toString(16).padStart(2, '0')).join('');
    return String(s);
};

(async () => {
    if (!fs.existsSync(path.join(APP_ROOT, 'services/schedule/sim-host.js'))) {
        console.error(`No Tube Symphony checkout at ${APP_ROOT} (pass --app-root)`); process.exit(1);
    }
    const server = await serveStatic(APP_ROOT);
    const { createSimHost } = require(path.join(APP_ROOT, 'services/schedule/sim-host.js'));
    const host = await createSimHost({
        appRoot: APP_ROOT, origin: `http://127.0.0.1:${server.address().port}`, startSim: false,
        log: (...a) => { if (process.env.VERBOSE) console.log(...a); },
    });
    const g = host.g;
    const LINES = g('LINES'), TS = g('TRAIN_STATE');
    const displayColor = g('lineDisplayColor');
    const metrics = g('getTrainCarriageMetrics');
    fs.mkdirSync(OUT, { recursive: true });

    // ---------------------------------------------------------------- lines
    const CENTER_STRIPE = new Set(['elizabeth', 'dlr', 'lioness', 'mildmay', 'windrush', 'weaver', 'suffragette', 'liberty']);
    const WHITE_GLOW = new Set(['northern', 'jubilee']);
    const lines = Object.keys(LINES).filter((k) => !LINES[k].noMap && TS[k]).map((key) => {
        const L = LINES[key], m = metrics(L);
        return {
            key,
            name: L.fullName || L.displayName || key,
            color: parseRgb(displayColor(key)),
            glowColor: WHITE_GLOW.has(key) ? '#ffffff' : parseRgb(displayColor(key)),
            centerStripe: CENTER_STRIPE.has(key),
            trainTemplate: L.trainTemplate || 'deep',
            trackLevel: L.trackLevel || null,
            carriageCount: L.carriageCount || 3,
            carriage: { bodyW: m.bodyW, bodyH: m.bodyH, borderW: m.borderW, outerW: m.outerW, outerH: m.outerH,
                        gapPx: L.carriageGapPx != null ? parseFloat(L.carriageGapPx) : (g('typeof CARRIAGE_GAP_PX !== "undefined" ? CARRIAGE_GAP_PX : 8')) },
        };
    });
    fs.writeFileSync(path.join(OUT, 'lines.json'), JSON.stringify(lines, null, 1));

    // ---------------------------------------------------------------- routes
    const routes = []; const chunks = []; let offset = 0, rawPts = 0;
    for (const { key } of lines) {
        for (const [id, rs] of Object.entries(TS[key].routes || {})) {
            const coords = rs.pathCoords, cum = rs.pathCumDist;
            if (!coords || coords.length < 2) continue;
            rawPts += coords.length;
            const idx = simplify(coords, TOLERANCE_M);
            const buf = new Float32Array(idx.length * 3);
            idx.forEach((i, j) => { buf[j * 3] = coords[i][0] - ORIGIN_LNG; buf[j * 3 + 1] = coords[i][1] - ORIGIN_LAT; buf[j * 3 + 2] = cum[i]; });
            chunks.push(Buffer.from(buf.buffer));
            routes.push({
                line: key, id,
                offset, count: idx.length,
                totalLength: round(rs.totalLength, 3),
                stationIds: (rs.stations || []).map((s) => s.id || null),
                stationDistances: (rs.stationDistances || []).map((d) => round(d, 2)),
                stationCoords: (rs.stationCoords || []).map((c) => [round(c[0], 6), round(c[1], 6)]),
            });
            offset += idx.length;
        }
    }
    fs.writeFileSync(path.join(OUT, 'routes.bin'), Buffer.concat(chunks));
    fs.writeFileSync(path.join(OUT, 'routes.json'), JSON.stringify({ origin: [ORIGIN_LNG, ORIGIN_LAT], format: 'f32le[lngOffset, latOffset, cumMetres]', routes }));

    // ---------------------------------------------------------------- tracks
    // What the map draws under the trains. Branches share their trunk with the
    // main route point for point, so each stretch is kept once (otherwise the glow
    // stacks brighter on shared track). Deduplicated at full resolution, then
    // simplified, so routes that simplified differently still share one line.
    const segKey = (p, q) => {
        const a = `${Math.round(p[0] * 1e7)},${Math.round(p[1] * 1e7)}`, b = `${Math.round(q[0] * 1e7)},${Math.round(q[1] * 1e7)}`;
        return a < b ? a + '|' + b : b + '|' + a;
    };
    const tracks = []; let segTotal = 0, segUnique = 0;
    for (const { key } of lines) {
        const seen = new Set();
        for (const id of Object.keys(TS[key].routes || {}).sort()) {
            const coords = TS[key].routes[id].pathCoords;
            if (!coords || coords.length < 2) continue;
            let run = [];
            const flush = () => { if (run.length >= 2) { const idx = simplify(run, TOLERANCE_M); tracks.push([key, idx.map((i) => [round(run[i][0], 6), round(run[i][1], 6)])]); } run = []; };
            for (let i = 1; i < coords.length; i++) {
                segTotal++;
                const k = segKey(coords[i - 1], coords[i]);
                if (!seen.has(k)) { seen.add(k); segUnique++; if (!run.length) run.push(coords[i - 1]); run.push(coords[i]); }
                else flush();
            }
            flush();
        }
    }
    fs.writeFileSync(path.join(OUT, 'tracks.json'), JSON.stringify(tracks));
    console.log(`track segments ${segTotal} → ${segUnique} unique; ${tracks.length} runs`);

    // ---------------------------------------------------------------- stations
    const SG = g('typeof STATION_GROUPS !== "undefined" ? STATION_GROUPS : null');
    const stations = [];
    if (SG) for (const [id, s] of SG.entries()) {
        stations.push({
            id, name: s.name, coord: [round(s.coord[0], 6), round(s.coord[1], 6)],
            lines: (s.lines || []).map((l) => l.key),
            colors: (s.lineColors || []).map(parseRgb),
            suppressLabel: !!s.suppressLabel,
        });
    }
    fs.writeFileSync(path.join(OUT, 'stations.json'), JSON.stringify(stations));

    // ---------------------------------------------------------------- scale
    // The phone profile (MAP_VIEW_MOBILE) and the constants getMapScale /
    // getTrainScale / getBlipScale read, so the app sizes things as a phone
    // browser does.
    const mobile = g('MAP_VIEW_MOBILE');
    const cssVar = (name) => { const css = fs.readFileSync(path.join(APP_ROOT, 'css/style.css'), 'utf8'); const m = new RegExp(name + ':\\s*([^;]+);').exec(css); return m ? parseFloat(m[1]) : null; };
    const deep = g('TRAIN_TEMPLATES').deep;
    const scale = {
        refZoom: mobile.referenceZoom,
        exponentIn: mobile.zoomScaleExponentIn,
        exponentOut: mobile.zoomScaleExponentOut,
        maxZoom: g('MAP_SCALE_MAX_ZOOM'),
        mapMaxZoom: g('MAP_MAX_ZOOM'),
        train2dScale: g('TRAIN_2D_SCALE'),
        trainZoomOutShrink: g('TRAIN_ZOOM_OUT_SHRINK'),
        deepCarriageWidthPx: parseFloat(deep.carriageWidth),
        blipRetain: cssVar('--blip-zoom-out-retain') ?? 0.2,
        blipShrink: cssVar('--blip-zoom-out-shrink') ?? 0,
        blipRippleDiameterPx: cssVar('--blip-ripple-diameter') ?? 200,
        blipRippleBorderPx: cssVar('--blip-ripple-border') ?? 18,
        trackGlowOpacity: cssVar('--track-glow-opacity') ?? 0.75,
        view: {
            startCenter: mobile.startCenter, startZoom: mobile.startZoom, minZoom: mobile.minZoom,
            maxViewport: mobile.maxViewport, overviewCenter: mobile.overviewCenter,
            lineWidthCore: mobile.lineWidthCore, lineWidthCasing: mobile.lineWidthCasing,
            trackGlowWidth: mobile.trackGlowWidth, trackGlowBlur: mobile.trackGlowBlur,
            stationDotSizePx: mobile.stationDotSizePx, stationDotBorderPx: mobile.stationDotBorderPx,
            stationLabelFontSizePx: mobile.stationLabelFontSizePx,
        },
    };
    fs.writeFileSync(path.join(OUT, 'scale.json'), JSON.stringify(scale, null, 1));

    // ---------------------------------------------------------------- basemap
    const tpl = fs.readFileSync(path.join(APP_ROOT, 'map-assets/style/tube-basemap.template.json'), 'utf8');
    fs.writeFileSync(path.join(OUT, 'basemap-style.json'), tpl.split('{ORIGIN}').join(ORIGIN));

    // ---------------------------------------------------------------- check
    // Place trains from the exported data the way the app does (binary search on
    // cumulative metres, linear between points) and compare with the website's
    // own getPositionAtDistance. Keep a sample as fixtures for the Swift tests.
    const posAt = g('getPositionAtDistance');
    const bin = Buffer.concat(chunks);
    const f32 = new Float32Array(bin.buffer, bin.byteOffset, bin.length / 4);
    const appPos = (r, d) => {
        const at = (i) => [f32[(r.offset + i) * 3] + ORIGIN_LNG, f32[(r.offset + i) * 3 + 1] + ORIGIN_LAT, f32[(r.offset + i) * 3 + 2]];
        if (d <= 0) return at(0).slice(0, 2);
        if (d >= at(r.count - 1)[2]) return at(r.count - 1).slice(0, 2);
        let lo = 0, hi = r.count - 1;
        while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (at(mid)[2] <= d) lo = mid; else hi = mid; }
        const a = at(lo), b = at(hi), t = (d - a[2]) / Math.max(1e-9, b[2] - a[2]);
        return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
    };
    const metres = (p, q) => Math.hypot((p[0] - q[0]) * 111320 * Math.cos(p[1] * Math.PI / 180), (p[1] - q[1]) * 110540);
    let worst = 0, sum = 0, n = 0; const fixtures = [];
    let seed = 12345; const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
    for (let k = 0; k < 5000; k++) {
        const r = routes[Math.floor(rnd() * routes.length)];
        const d = rnd() * r.totalLength;
        const web = posAt(r.line, d, r.id).coord, app = appPos(r, d);
        const e = metres(web, app); worst = Math.max(worst, e); sum += e; n++;
        if (fixtures.length < 60) fixtures.push({ line: r.line, route: r.id, dist: round(d, 3), lng: web[0], lat: web[1] });
    }
    const fixturesDir = path.resolve(arg('fixtures', path.join(__dirname, '../../TubeSymphonyTests/Fixtures')));
    fs.mkdirSync(fixturesDir, { recursive: true });
    fs.writeFileSync(path.join(fixturesDir, 'geometry-fixtures.json'), JSON.stringify(fixtures, null, 1));
    console.log(`placement vs website: mean ${(sum / n).toFixed(3)} m, worst ${worst.toFixed(3)} m over ${n} samples`);
    if (worst > 1.0) { console.error('route export drifted more than 1 m from the website — lower --tolerance'); process.exit(2); }

    const kept = routes.reduce((a, r) => a + r.count, 0);
    console.log(`lines ${lines.length}, routes ${routes.length}, stations ${stations.length}`);
    console.log(`route points ${rawPts} → ${kept} at ${TOLERANCE_M} m (${(kept * 12 / 1048576).toFixed(2)} MB)`);
    console.log(`wrote ${OUT}`);
    server.close();
    process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
