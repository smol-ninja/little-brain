const demo = document.querySelector('.demo');
const demoButton = demo.querySelector('button');
const still = demo.querySelector('source');
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
let paused;

function setPaused(value) {
  paused = value;
  still.media = paused ? 'all' : 'not all';
  demoButton.setAttribute('aria-label', paused ? 'Play demo' : 'Pause demo');
  demoButton.querySelector('path').setAttribute('d', paused
    ? 'M4 2l10 6-10 6z'
    : 'M4 3h3v10H4zm5 0h3v10H9z');
}

setPaused(motionPreference.matches);
demoButton.hidden = false;
demoButton.addEventListener('click', () => setPaused(!paused));
motionPreference.addEventListener('change', event => setPaused(event.matches));
