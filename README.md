# .pwsh.d

A simple init.d style execution pattern for `$profile`

clone this repo to `~/.pwsh.d` on windows and move `Microsoft.PowerShell_profile.ps1.copy_to_profile` to `$profile`.

Add your init scripts using the naming pattern `<name>.pwsh.ps1` to `~/.pwsh.d`

```
git clone git@gitcodo.hub:ocodo/.pwsh.d ~/.pwsh.d
mv ~/.pwsh.d/Microsoft.PowerShell_profile.ps1.copy_to_profile $profile
```

The default `profile.pwsh.ps1` is in place, and will use the oh-my-posh prompt in `ocodo.pwsh.yaml`.

Fork and do as you will.