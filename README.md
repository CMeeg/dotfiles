# dotfiles

dotfiles and setup instructions and scripts for:

* [windows](./windows/README.md)
  * [wsl](./wsl/README.md)
* [linux](./linux/README.md)
* [tailscale](./tailscale/README.md) (optional): reach herdr-core and dev servers on these machines from your phone or other computers

## How the dotfiles are managed

* [`dotfiles.json`](./dotfiles.json) lists the files this repo manages and where each one goes. [`sync.ps1`](./sync.ps1) copies them into place as real files, merges changes from both sides and offers to copy local changes back into the repo (see [Syncing dotfiles](./linux/README.md#syncing-dotfiles)).
* On Linux, [`bootstrap.sh`](./bootstrap.sh) installs PowerShell 7 and runs [`install.ps1`](./install.ps1); [`update.ps1`](./update.ps1) keeps the tools and dotfiles up to date. Both run [`retire.ps1`](./retire.ps1)'s steps first, which remove tools the repo no longer installs.
* Windows is set up by hand for now (see [windows](./windows/README.md)).
