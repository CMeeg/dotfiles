# wsl

## wsl setup

These setup instructions are for wsl2.

* Install, or update, wsl (run from admin prompt, or using sudo)
  * `wsl --install` - install wsl
  * `wsl --update` - update wsl kernel and important components
* Check that you have a Linux distro installed, and if not install one (this guide is currently written for `Debian`)
  * `wsl -l -v` - list installed distros
  * `wsl -l -o` - list available distros
  * `wsl.exe --install -d <DistroName>` - install distro
* Set default distro
  * `wsl --status` - check operating status and default distro
  * `wsl --set-default <DistroName>` - set default Distro
* Copy `wsl/.wslconfig` to your Windows home directory
* Add wsl distro as a Windows Terminal profile
  * N.B. If it doesn't show up automatically you may have to
    * Close WT
    * Temporarily move your WT `settings.json`
    * Open WT - this should automatically create profiles incuding for wsl
    * Copy the wsl profile from the generated `settings.json` into your `settings.json`
    * Replace the generated `settings.json` with your updated `settings.json`
* Open the wsl distro profile in Windows Terminal
* Follow [linux](../linux/README.md) setup steps to setup your distro
* Install [WSL UI](https://wsl-ui.octasoft.co.uk/downloads)
  * `winget install "WSL UI" --source msstore`
  * Settings (leave at default if not mentioned)
    * Application
      * Terminal: Windows Terminal
      * Window behaviour: Always minimise to tray
    * Appearance
      * Color theme: Dracula

> N.B. See [wsl tips](#wsl-tips) for some general help with common operations.

## wsl tips

* Open file/folder in Windows VS Code from wsl prompt
  * `code <path>` - e.g. `code .` will open the current folder
* Move in and out of wsl from your Windows shell
  * `wsl` - move into wsl
  * `exit` - exit wsl
* If you need to restart wsl
  * `wsl --shutdown` - shutdown wsl
  * `wsl` - start wsl
* Move wsl distro
  * See [Moving WSL Distributions to Another Drive](https://wsl-ui.octasoft.co.uk/blog/moving-wsl-distributions-to-another-drive)
  * Or use WSL UI
