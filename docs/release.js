const repository = 'smol-ninja/little-brain';
const releasesURL = `https://github.com/${repository}/releases`;
const button = document.querySelector('#download');
const fallbackTag = new URL(button.href).pathname.split('/').at(-2);

button.addEventListener('click', () => {
  window.umami?.track('download_click');
});

async function showLatestDownload() {
  try {
    const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return;

    const release = await response.json();
    if (release.tag_name.localeCompare(fallbackTag, 'en', { numeric: true }) <= 0) return;
    const version = release.tag_name.replace(/^v/, '');
    const installers = release.assets.filter(asset => asset.state === 'uploaded' && asset.size > 0);
    const installer = installers.find(asset => asset.name === `littlebrain-${version}.dmg`)
      ?? installers.find(asset => asset.name === 'littlebrain.dmg');
    if (!installer) return;

    button.href = `${releasesURL}/download/${encodeURIComponent(release.tag_name)}/${encodeURIComponent(installer.name)}`;
  } catch {
    // Keep the verified download when GitHub cannot confirm a newer installer.
  }
}

showLatestDownload();
