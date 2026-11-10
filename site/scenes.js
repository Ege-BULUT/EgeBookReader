// Silhouettes that stand on the lower arm of the E (y = 286), drawn like pop-up book cut-outs.
// Each scene is a list of [path, opacity]; each figure folds down on its own, so a scene leaves and arrives in a wave.
const SCENES = {
  fantasy: [
    // castle, behind everything
    [`M44 286V176h8v-12h9v12h9v-12h9v12h9v-12h9v12h6v-58l-7-7 19-38 19 38-7 7v58h6v-12h9v12h9v-12h9v12h8v110h-34v-30c0-12-8-20-18-20s-18 8-18 20v30z`, .55],
    // dragon overhead, wings up, long neck and tail
    [`M58 96c10-2 20-8 30-16 8-7 15-10 24-11l10-16c4-16 2-30-8-44 16 8 26 20 30 36 4-22 18-36 44-42-10 12-16 26-16 46 12-8 24-12 36-10l16-10 14 4 18-4-12 12 8 6-18 2-10 10c-8 2-16 2-24 0-8 8-18 14-30 17-6 6-16 10-28 10-12 12-28 16-46 12-14 4-28 2-36-2z`, 1],
    // knight with a lance, on a rearing horse
    [`M196 286l4-36-14-14-6-30-12 4-4-10 16-12 10-30 12 2 6-12-2-10c-2-8 2-14 8-16l4-24 4 0 2 24c6 4 8 10 6 16l-4 12 18 2 20-82 4 1-14 86 20 8 16 22 14 34-10 4-14-26-12-6-2 28 10 50h-14l-12-40-16-6-8 24-2 22z`, 1],
  ],
  scifi: [
    // capital ship, far away
    [`M46 112l50-18 7-22h30l9 18 84 16-26 14h-38l-10 18h-26l-9-16H70z`, .55],
    // fighters
    [`M190 58l30-10 19-14 3 10 19-2-12 14 5 10-17-3-17 10-7-9z`, 1],
    [`M64 46l23-7 14-10 3 9 14-2-9 10 4 9-14-3-12 8-5-7z`, 1],
    // robot soldier
    [`M80 286v-40l-7-4v-38l-12-3 5-30 19-7v-17h-7v-7h7v-16h30v16h7v7h-7v17l19 7 19-9 5 11-21 15-3 9v41l-7 5v38h-14v-40h-14v40z`, 1],
    // alien
    [`M212 286l5-46-14-38-12 16-9-5 19-35 10-5c-12-7-19-19-19-33 0-17 12-29 26-29s26 12 26 29c0 14-7 26-19 33l10 5 19 35-9 5-12-16-14 38 5 46h-11l-5-38h-3l-5 38z`, 1],
  ],
  noir: [
    // the city, far behind
    [`M36 286V170h24v-20h18v42h16V136h30v28h12v-46h26v56h18v-26h24v62h18v-30h28v106z`, .22],
    // street lamp
    [`M84 286V148c0-18 12-26 32-26v10c-12 0-22 7-22 16v138z`, .8],
    // detective, hat and long coat
    [`M170 286l5-66-10-42 2-25 14-14 11-4v-7c-7-2-11-7-11-12h-11v-7l14-2 2-12c0-5 11-9 20-9s20 4 20 9l2 12 14 2v7h-11c0 5-4 10-11 12v7l11 4 14 14 2 25-10 42 5 66h-16l-7-58h-12l-7 58z`, 1],
    // car
    [`M44 286v-20l11-5 14-22h54l20 22 26 5v20h-12a14 14 0 0 0-28 0H83a14 14 0 0 0-28 0z`, 1],
  ],
};
const SCENE_ORDER = ['fantasy', 'scifi', 'noir'];
