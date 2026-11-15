const repository = 'smol-ninja/little-brain';
const assetName = 'littlebrain.dmg';
const releasesURL = `https://github.com/${repository}/releases`;
const button = document.querySelector('#download');
const unavailable = document.querySelector('#download-unavailable');

async function showLatestDownload() {
  try {
    const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return;

    const release = await response.json();
    const hasInstaller = release.assets.some(asset => asset.name === assetName && asset.state === 'uploaded' && asset.size > 0);
    if (!hasInstaller) return;

    button.href = `${releasesURL}/download/${encodeURIComponent(release.tag_name)}/${assetName}`;
    unavailable.hidden = true;
    button.hidden = false;
  } catch {
    // Keep the download disabled when GitHub cannot confirm an installer.
  }
}

showLatestDownload();
