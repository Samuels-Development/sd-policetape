// Browser preview only (npm run dev, never in the build): plays client/nui.lua's part.
// Pick what to look at with the address's hash: #place, #look, #picker, #studio.
import styles from './dev-styles.json';

function send(msg: Record<string, unknown>): void {
  window.postMessage(msg, '*');
}

export function start(): void {
  // A grey-green stand-in for the game behind the page.
  document.body.style.background = "linear-gradient(160deg, #5d6b5a, #3d4a52)";
  send({ action: 'init', styles, canStudio: true });

  const view = location.hash.slice(1) || 'place';
  if (view === 'place') {
    send({
      action: 'hud',
      hud: {
        mode: 'place',
        styleId: 'crime_scene',
        title: 'Crime Scene',
        line: '6.4 m',
        lineKind: 'ok',
        keys: [
          { k: 'LMB', t: 'Tie off here' },
          { k: 'Wheel', t: 'Style' },
          { k: 'G', t: 'All styles' },
          { k: 'RMB', t: 'Done' },
        ],
      },
    });
  } else if (view === 'look') {
    send({
      action: 'hud',
      hud: { mode: 'look', styleId: 'police_line', keys: [{ k: 'G', t: 'Change style' }, { k: 'Alt', t: 'Hold to take down' }] },
    });
    let p = 0;
    window.setInterval(() => {
      p = p >= 1 ? 0 : p + 0.02;
      send({ action: 'progress', value: p });
    }, 40);
  } else if (view === 'picker') {
    send({ action: 'picker', open: true, selected: 'crime_scene' });
  } else if (view === 'studio') {
    send({ action: 'studio', open: true, startFrom: 'police_line' });
  }
}
