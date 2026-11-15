const repository = 'smol-ninja/little-brain';
const assetName = 'littlebrain.dmg';
const releasesURL = `https://github.com/${repository}/releases`;
const button = document.querySelector('#download');
const status = document.querySelector('#download-status');
const source = document.querySelector('#source-link');

async function showLatestDownload() {
  try {
    const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
      signal: AbortSignal.timeout(5000),
    });
    if (response.status === 404) return;
    if (!response.ok) throw new Error('GitHub release lookup failed');

    const release = await response.json();
    const installer = release.assets.find(asset => asset.name === assetName && asset.state === 'uploaded' && asset.size > 0);
    if (!installer) return;

    button.href = `${releasesURL}/download/${encodeURIComponent(release.tag_name)}/${assetName}`;
    status.textContent = release.tag_name;
    source.hidden = true;
    button.hidden = false;
  } catch {
    status.textContent = 'Could not check for the Mac installer.';
    source.href = releasesURL;
    source.textContent = 'View releases ↗';
  }
}

showLatestDownload();
