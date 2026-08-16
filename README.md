# aicommit

GitHub Copilot commit messages for lazygit using OAuth device flow.

## Nix

Add the flake input:

```nix
inputs.aicommit.url = "github:HMegh/lazygit-commit";
```

Import the Home Manager module:

```nix
{ inputs, ... }:
{
  imports = [ inputs.aicommit.homeManagerModules.default ];
  programs.aicommit.enable = true;
}
```

This installs `aicommit`, enables lazygit, and adds:

- `Ctrl+U` in the files view: generate and select a commit message
- `Ctrl+G` globally: log in, log out, or check authentication status

## Usage

Start authentication from lazygit with `Ctrl+G`, or run:

```sh
aicommit login
```

Stage changes in lazygit, then press `Ctrl+U` to generate a Conventional
Commits message with GitHub Copilot.

Authentication data is stored under `${XDG_STATE_HOME:-$HOME/.local/state}`.

## Requirements

- GitHub Copilot access
- `curl`, `git`, and `jq`
- `lazygit`

The script uses GitHub's device flow and Copilot API directly; it does not use
the Copilot CLI.
