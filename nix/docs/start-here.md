Let's go ahead and install Nix. To do that, we'll use the
**[nix-installer tool]** by Determinate Systems. This works on many platforms,
but most importantly it works on **aarch64 Linux** and **x86_64 Linux**. Use the
following command in your shell, **it should work on any Linux distro of your
choice**:

[nix-installer tool]: https://github.com/DeterminateSystems/nix-installer

```bash
curl \
  --proto '=https' --tlsv1.2 \
  -sSf -L https://install.determinate.systems/nix \
| sh -s -- install
```

After you do this, **you must log in and log back out of your desktop
environment** to get a new login session. This is so that your shell can have
the Nix tools installed on `$PATH` and so that your user shell can see some
extra settings.

You should now be able to do something like the following; try running these
same commands on your machine:

```
$ nix --version
nix (Nix) 2.16.1
```

```
$ nix run nixpkgs#nix-info -- -m
 - system: `"x86_64-linux"`
 - host os: `Linux 5.15.90.1-microsoft-standard-WSL2, Ubuntu, 22.04.2 LTS (Jammy Jellyfish), nobuild`
 - multi-user?: `yes`
 - sandbox: `yes`
 - version: `nix-env (Nix) 2.16.1`
 - channels(root): `"nixpkgs"`
 - nixpkgs: `/nix/var/nix/profiles/per-user/root/channels/nixpkgs`
```

If the above worked, you're now cooking with gas!

> _**NOTE**_: While there is an upstream tool to install Nix, written in Bash,
> we use the Determinate Systems installer — which will hopefully replace the
> original — because it's faster, and takes care of several extra edge cases
> that the original one couldn't handle, and makes several changes to the
> default installed configuration to make things more user friendly. Determinate
> Systems is staffed by many long-time Nix contributors and the creator of Nix,
> and is trustworthy.

## Do some fun stuff

One of the best things about Nix that requires _very little_ knowledge of it is
that it lets you install the latest and greatest versions of many tools _on any
Linux distribution_. We'll explain more about that later on. But just as a few
examples:

- **Q**: I want the latest version of Deno. Can we get that?
- **A**: `nix profile install nixpkgs#deno`, and you're done!

<!-- break bulletpoints -->

- **Q**: What about HTTPie? A nice Python application?
- **A**: Same idea: `nix profile install nixpkgs#httpie`

<!-- break bulletpoints -->

- **Q**: What about my favorite Rust applications, like ripgrep and bat?
- **A.1**: `nix profile install nixpkgs#ripgrep`
- **A.2**: `nix profile install nixpkgs#bat`
- **A.3**: And yes, you also have exa, fd, hyperfine, and more!
