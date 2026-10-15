{
  description = "mads — NixOS for Apple Silicon (mbp) and x86 (pc), one flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    apple-silicon = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # linear-tui has no flake of its own, so take the source and build it below.
    # Pinned to a tag; `nix flake update` moves it and records the hash in
    # flake.lock, so there is no sha256 to maintain by hand.
    linear-tui-src = {
      url = "github:k1-c/linear-tui/v0.13.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, apple-silicon, home-manager, firefox-addons, zen-browser, linear-tui-src, ... }:
    let
      # linear-tui, built from the pinned source input above. Upstream ships no
      # flake and it is not in nixpkgs, but it has a committed Cargo.lock, so
      # cargoLock.lockFile covers the dependency hashes with nothing to vendor.
      #
      # No OpenSSL/pkg-config needed: the crate selects reqwest's rustls
      # backend on purpose, and takes its trust roots from the OS store.
      linearTui = pkgs: pkgs.rustPlatform.buildRustPackage {
        pname = "linear-tui";
        version = "0.13.0";
        src = linear-tui-src;
        cargoLock.lockFile = "${linear-tui-src}/Cargo.lock";
        # One test (a_worktree_belongs_to_its_repository) shells out to `git`,
        # which the build sandbox lacks -- it panics on NotFound unwrapping
        # Command::new("git"). Supplying git lets all 512 tests run.
        nativeCheckInputs = [ pkgs.git ];

        meta.mainProgram = "linear-tui";
      };

      # ───────────────────── shared home-manager user ─────────────────────
      home = { pkgs, osConfig, ... }: {
        imports = [ zen-browser.homeModules.beta ];
        home.stateVersion = "25.11";

        programs.eww = {
          enable = true;
          package = pkgs.eww;
        };

        # Raw configs that stay files (no good native module).
        # `hypr` is recursive so we can drop a host-specific monitors.conf in
        # alongside the shared files (hyprland.conf `source`s it).
        xdg.configFile = {
          "hypr" = { source = ./config/hypr; recursive = true; };
          "hypr/monitors.conf".text =
            if osConfig.networking.hostName == "mbp"
            then ''
              monitor = , preferred, auto, 2.0

              # Floating TUI panels: 70% wide, full height. Absolute px because
              # Hyprland 0.56 ignores percentages in `size`. 1728x1080 logical.
              windowrule = match:class ^(panel-wifi|panel-bt)$, float on, size 1210 1080, center on
            ''
            else ''
              monitor = desc:Lenovo Group Limited P27q-20 V909LRFR, 2560x1440@60, 0x0, 1.0
              monitor = desc:Lenovo Group Limited P27q-20 V909LPNY, 2560x1440@60, 2560x0, 1.0
              monitor = desc:ASUSTek COMPUTER INC XG32UQWMS W6LMQS013451, 3840x2160@240, 5120x0, 1.333333

              # Each screen's home workspace; SUPER+ALT+h/l can still move it.
              workspace = 1, monitor:desc:Lenovo Group Limited P27q-20 V909LRFR, default:true
              workspace = 2, monitor:desc:Lenovo Group Limited P27q-20 V909LPNY, default:true
              workspace = 3, monitor:desc:ASUSTek COMPUTER INC XG32UQWMS W6LMQS013451, default:true

              # Same panels, sized for 2560x1440 logical.
              windowrule = match:class ^(panel-wifi|panel-bt)$, float on, size 1792 1440, center on
            '';
          # Idle: lock after 10 min everywhere. Only the laptop blanks its
          # panel first; the PC's monitors go to sleep on their own.
          "hypr/hypridle.conf".text = ''
            general {
                lock_cmd = pidof hyprlock || hyprlock
                before_sleep_cmd = loginctl lock-session
                after_sleep_cmd = hyprctl dispatch dpms on
            }
          '' + nixpkgs.lib.optionalString (osConfig.networking.hostName == "mbp") ''

            listener {
                timeout = 300
                on-timeout = hyprctl dispatch dpms off
                on-resume = hyprctl dispatch dpms on
            }
          '' + ''

            listener {
                timeout = 600
                on-timeout = loginctl lock-session
            }
          '';
          "eww".source    = ./config/eww;
          "fuzzel".source = ./config/fuzzel;
        };


        # Launcher hygiene. These .desktop entries ship with packages we do want,
        # but they are noise in fuzzel. A NoDisplay entry in XDG_DATA_HOME
        # shadows the package's own copy, which is the only way to hide one
        # without patching the package.
        #
        # Deliberately home.file and NOT xdg.desktopEntries: that option only
        # emits anything when xdg.enable = true, which we don't set, so it
        # silently produces no files at all.
        #   nvim  - neovim's "Neovim wrapper" entry; we only launch it from a terminal
        #   uuctl - uwsm's systemd-user-unit picker, pulled in by withUWSM
        home.file = {
          ".local/share/applications/nvim.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=Neovim wrapper
            NoDisplay=true
          '';
          ".local/share/applications/uuctl.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=uuctl
            NoDisplay=true
          '';
        };

        # Notification daemon. Nothing owned org.freedesktop.Notifications before
        # this, so notify-send failed outright: hyprshot's "Screenshot saved"
        # toasts went nowhere, and kitty logged a DBus ServiceUnknown error on
        # every launch. Colours match the cyberdream kitty theme above.
        services.mako = {
          enable = true;
          settings = {
            font = "JetBrainsMono Nerd Font 11";
            background-color = "#16181a";
            text-color = "#ffffff";
            border-color = "#5ea1ff";
            border-size = 2;
            border-radius = 8;
            default-timeout = 5000;
            anchor = "top-right";
            margin = "12";
            padding = "12";
            width = 380;
          };
        };

        programs.kitty = {
          enable = true;
          settings = {
            font_size = "11.5";

            # cyberdream theme
            background            = "#16181a";
            foreground            = "#ffffff";
            cursor                = "#ffffff";
            cursor_text_color     = "#16181a";
            selection_background  = "#3c4048";
            selection_foreground  = "#ffffff";
            color0                = "#16181a";
            color8                = "#3c4048";
            color1                = "#ff6e5e";
            color9                = "#ff6e5e";
            color2                = "#5eff6c";
            color10               = "#5eff6c";
            color3                = "#f1ff5e";
            color11               = "#f1ff5e";
            color4                = "#5ea1ff";
            color12               = "#5ea1ff";
            color5                = "#bd5eff";
            color13               = "#bd5eff";
            color6                = "#5ef1ff";
            color14               = "#5ef1ff";
            color7                = "#ffffff";
            color15               = "#ffffff";
            active_tab_foreground   = "#000000";
            active_tab_background   = "#ffbd5e";
            inactive_tab_foreground = "#ffffff";
            inactive_tab_background = "#16181a";
          };
        };

        home.pointerCursor = {
          enable = true;
          package = pkgs.bibata-cursors;
          name = "Bibata-Modern-Ice";
          size = 24;
          gtk.enable = true;
          x11.enable = true;
          hyprcursor.enable = true;
        };

        # Dark GTK apps (file dialogs, etc).
        gtk = {
          enable = true;
          theme = { name = "Adwaita-dark"; package = pkgs.gnome-themes-extra; };
          gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
          gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
          # Adopt the new default: don't force a theme on GTK4/libadwaita apps
          # (dark still applies via prefer-dark-theme above). Silences the
          # stateVersion < 26.05 legacy-default warning.
          gtk4.theme = null;
        };

        # Neovim: init.lua verbatim; plugins + LSP pinned by Nix.
        programs.neovim = {
          enable = true;
          withPython3 = false;
          withRuby = false;
          withNodeJs = false;
          initLua = "vim.g.nix_managed = true\n"
            + builtins.readFile ./config/nvim/init.lua;
          plugins = with pkgs.vimPlugins; [
            nvim-web-devicons cyberdream-nvim oil-nvim nvim-lspconfig
            typst-preview-nvim blink-cmp Navigator-nvim
            snacks-nvim todo-comments-nvim trouble-nvim
            nvim-treesitter.withAllGrammars
            fidget-nvim lualine-nvim
          ];
          extraPackages = with pkgs; [
            lua-language-server rust-analyzer tinymist nixd zls
            yaml-language-server vscode-langservers-extracted
            typescript-language-server svelte-language-server
          ];
        };

        # Zen browser + Tridactyl, extensions pinned (works on aarch64 + x86).
        programs.zen-browser = {
          enable = true;
          setAsDefaultBrowser = true;
          profiles.default = {
            settings = {
              "browser.newtabpage.enabled" = false;
              "privacy.donottrackheader.enabled" = true;
              "signon.rememberSignons" = false;

              # Dark mode
              "browser.theme.toolbar-theme" = 0;
              "browser.theme.content-theme" = 0;
              "layout.css.prefers-color-scheme.content-override" = 0;
              "ui.systemUsesDarkTheme" = 1;
            };
            # Re-instantiate pkgs with the firefox-addons overlay + allowUnfree so
            # the (unfree) 1Password addon evaluates under *our* config.
            extensions.packages = let
              addonsPkgs = import pkgs.path {
                inherit (pkgs.stdenv.hostPlatform) system;
                config.allowUnfree = true;
                overlays = [ firefox-addons.overlays.default ];
              };
            in with addonsPkgs.firefox-addons; [
              tridactyl
              ublock-origin
              onepassword-password-manager
            ];
          };
        };
            
        # zsh + starship, no framework.
        programs.zsh = {
          enable = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          shellAliases = { ll = "ls -alh"; gs = "git status"; };
        };
        programs.starship.enable = true;

      

        # SSH auth via the 1Password agent — private keys stay in the vault,
        # never on disk or in the Nix store.
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings."*".IdentityAgent = "~/.1password/agent.sock";
        };

        # git identity + SSH commit signing through 1Password's op-ssh-sign.
        programs.git = {
          enable = true;
          settings = {
            user.name  = "Mads Fagerlund";
            user.email = "mads@deepvis.ai";
            user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAPlpVGZLhfrJqh2j5q3reyGOPQQ9BgW8syQ28tYjlg2";
            gpg.format = "ssh";
            # NixOS store path — NOT 1Password's suggested /opt/1Password/... which doesn't exist here.
            "gpg \"ssh\"".program =
              "${pkgs._1password-gui}/share/1password/op-ssh-sign";
            commit.gpgsign = true;
            # Transparently use SSH (1Password agent) for the deepvis server,
            # so existing HTTPS remotes need no manual `git remote set-url`.
            url."git@git.deepvis.ai:".insteadOf = "https://git.deepvis.ai/";
          };
        };

        home.packages = with pkgs; [ ripgrep fd tridactyl-native lazygit rustc cargo clippy rustfmt rust-analyzer claude-code gcc bluetui impala postgresql fastfetch remmina unzip (linearTui pkgs) ];
      };

      # ───────────────────── shared system (both hosts) ─────────────────────
      common = { pkgs, ... }: {
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        # Trusted so client-side nix config takes effect — substituters and
        # remote builders are trusted settings, silently ignored for anyone
        # else. A cache that appears to do nothing is the usual symptom.
        nix.settings.trusted-users = [ "mads" ];

        # The deepvis binary cache: the embedded flakes in models/ort-nix
        # (onnxruntime built from source, a CUDA training env) are hours of
        # work to build and seconds to substitute.
        nix.settings.extra-substituters = [ "https://deepvis.cachix.org" ];
        nix.settings.extra-trusted-public-keys = [
          "deepvis.cachix.org-1:UE/H6ERLwqhSqubzh8+pzl9eTm0kpMExGe0ym6fENp8="
        ];
        # Private cache, so reads need a token. nix refuses `netrc-file` on
        # the command line under the daemon, and a token in the substituter
        # URL would land in the process table — a root-owned 0600 netrc is
        # the only form the calling process cannot read.
        nix.settings.netrc-file = "/etc/nix/netrc";

        # x86_64 derivations build off this machine rather than under local
        # qemu emulation, and aarch64 ones go out too when the local
        # machine is busy.
        #
        # The host keys are pinned system-wide because the ssh'ing party is
        # the root daemon, which has no known_hosts and never gets a tty to
        # answer a trust prompt.
        programs.ssh.knownHosts."builder" = {
          extraHostNames = [ "5.9.71.104" "builder.tailf5eaab.ts.net" ];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnKIrxYtlovvYGgkpEZXY8wG/CuSLMGOM/84eIlyeVW";
        };
        programs.ssh.knownHosts."eu.nixbuild.net" = {
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
        };
        nix.distributedBuilds = true;
        nix.buildMachines = [
          {
            hostName = "builder";
            sshUser = "builder";
            # The daemon (root) does the ssh'ing, so it needs an explicit
            # on-disk key — it has no access to a user's agent.
            sshKey = "/home/mads/.ssh/id_ed25519";
            protocol = "ssh-ng";
            system = "x86_64-linux";
            maxJobs = 16;
            supportedFeatures = [ "big-parallel" "kvm" "nixos-test" ];
          }
          # nixbuild.net, for both architectures. Listed after `builder` so
          # the machine we already pay for is preferred.
          #
          # Every feature it supports is advertised, not just the two in the
          # quickstart: nix only sends a derivation to a builder claiming
          # *every* feature that derivation requires, so omitting `kvm` or
          # `nixos-test` would silently route those back to local builds.
          {
            hostName = "eu.nixbuild.net";
            sshUser = "root";
            sshKey = "/home/mads/.ssh/id_ed25519";
            protocol = "ssh-ng";
            system = "x86_64-linux";
            maxJobs = 100;
            supportedFeatures = [ "benchmark" "big-parallel" "ca-derivations" "kvm" "nixos-test" ];
          }
          {
            hostName = "eu.nixbuild.net";
            sshUser = "root";
            sshKey = "/home/mads/.ssh/id_ed25519";
            protocol = "ssh-ng";
            system = "aarch64-linux";
            maxJobs = 100;
            supportedFeatures = [ "benchmark" "big-parallel" "ca-derivations" "kvm" "nixos-test" ];
          }
        ];

        # iwd owns Wi-Fi (driven from impala, which is iwd-only); networkd does
        # DHCP and resolved does DNS. No NetworkManager: running it on top of
        # iwd meant two managers with separate saved networks, which ended in
        # "Secrets were required, but not provided".
        networking.wireless.iwd.enable = true;
        networking.useNetworkd = true; # DHCP on any ethernet/wifi by default
        systemd.network.wait-online.anyInterface = true; # one link up is enough

        # iwd only reads /var/lib/iwd. C = copy once, so a password added to
        # the file later (or via impala) is never overwritten.
        systemd.tmpfiles.rules = [
          "C /var/lib/iwd/eduroam.8021x 0600 root root - ${pkgs.writeText "eduroam.8021x" ''
            [Security]
            EAP-Method=PEAP
            EAP-Identity=447087@net.aau.dk
            EAP-PEAP-Phase2-Method=MSCHAPV2
            EAP-PEAP-Phase2-Identity=447087@net.aau.dk
          ''}"
        ];

        # Secret Service (org.freedesktop.secrets) provider, D-Bus-activated on
        # demand. Without it 1Password can't persist the 2FA device token
        # ("unable to save your two-factor token") and re-prompts every unlock.
        services.gnome.gnome-keyring.enable = true;

        programs._1password.enable = true;
        programs._1password-gui = {
          enable = true;
          polkitPolicyOwners = [ "mads" ];
        };
        # Zen (a Firefox fork) runs as "zen-beta"; 1Password only trusts an
        # allowlist of browser process names, so add it or the extension can't
        # unlock via the desktop app. Manifest already lives in ~/.mozilla.
        environment.etc."1password/custom_allowed_browsers".text = ''
          zen-beta
        '';

        services.tailscale.enable = true;
        # Tailscale SSH: keyless, portless SSH gated by tailnet ACLs.
        # Needs a matching "ssh" rule in the admin console to actually permit access.
        services.tailscale.extraUpFlags = [ "--ssh" ];

        time.timeZone = "Europe/Copenhagen"; # set yours
        i18n.defaultLocale = "en_US.UTF-8";

        programs.hyprland = { enable = true; withUWSM = true; };
        programs.hyprlock.enable = true;

        # Every GUI app lives in the one wayland-wm@hyprland.service cgroup, so
        # with systemd's default OOMPolicy=stop a kernel OOM-kill of ANY process
        # in it stops the whole unit -- compositor included. 1Password was always
        # the victim (highest oom_score_adj), but losing it killed the entire
        # desktop, and uwsm sets Restart=no, so nothing came back. It read as
        # "Hyprland crashed" when the compositor was never at fault.
        #
        # continue: log the kill, lose that one app, keep the session. Merges
        # into the drop-in the uwsm module already generates for this unit.
        systemd.user.services."wayland-wm@".serviceConfig.OOMPolicy = "continue";

        # Autologin means no password reaches PAM at login, so the gnome-keyring
        # login keyring is never created or unlocked -- which is why 1Password
        # could not persist its 2FA device token and re-prompted the YubiKey
        # every unlock. Putting pam_gnome_keyring in hyprlock's stack instead
        # makes the lock screen we already have do that job, so there is still
        # exactly one password prompt and no second login screen.
        security.pam.services.hyprlock.enableGnomeKeyring = true;
        services.hypridle.enable = true;

        xdg.portal = {
          enable = true;
          extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
        };


        # greetd autologins mads straight into Hyprland (via uwsm).
        services.greetd = {
          enable = true;
          settings = {
            initial_session = { user = "mads"; command = "uwsm start hyprland"; };
            default_session = { user = "mads"; command = "uwsm start hyprland"; };
          };
        };

        virtualisation.docker.enable = true;

        hardware.bluetooth.enable = true;
        programs.zsh.enable = true;
        # No NixOS manual: it puts a "NixOS Manual" entry in the launcher and we
        # read the docs on the web. man pages are unaffected.
        documentation.nixos.enable = false;

        fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

        environment.systemPackages = with pkgs; [
          git kitty fuzzel
          wl-clipboard grim slurp swaybg brightnessctl playerctl hyprshot
          hyprpolkitagent xdg-utils
        ];

        users.users.mads = {
          isNormalUser = true;
          extraGroups = [ "wheel" "video" "docker" ];
          shell = pkgs.zsh;
          initialPassword = "changeme"; # CHANGE after first boot (`passwd`)
        };

        system.stateVersion = "25.11";

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        # Back up (don't clobber) any pre-existing files HM wants to manage.
        home-manager.backupFileExtension = "hm-bak";
        home-manager.users.mads = home;
      };

      mkHost = { system, modules }: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ 
          home-manager.nixosModules.home-manager 
          common 
          ({ pkgs, ... }: {
            nixpkgs.config.allowUnfree = true;
          })
        ] ++ modules;
      };

    in
    {
      nixosConfigurations = {
        # ── Apple Silicon MacBook (Asahi) ──
        mbp = mkHost {
          system = "aarch64-linux";
          modules = [
            apple-silicon.nixosModules.apple-silicon-support
            ./hosts/mbp/hardware-configuration.nix # generated on the Mac
            ({ ... }: {
              networking.hostName = "mbp";

              # Wi-Fi/BT firmware, vendored (a pure flake can't read /boot/asahi).
              hardware.asahi.peripheralFirmwareDirectory = ./firmware;
              hardware.asahi.enable = true;

              boot.loader.systemd-boot.enable = true;
              boot.loader.systemd-boot.configurationLimit = 3; # 500M ESP is small
              boot.extraModprobeConfig = "options hid_apple fnmode=1";
              boot.blacklistedKernelModules = [ "pcspkr" ];

              # Root is btrfs (p8). A scrub re-reads every block and verifies its
              # checksum, which is the only way bit rot on this SSD surfaces before
              # something tries to read the damaged file. Metadata is DUP, so a bad
              # metadata block gets repaired from its copy automatically.
              services.btrfs.autoScrub = {
                enable = true;
                interval = "monthly";
                fileSystems = [ "/" ];
              };

              # 15G of RAM and no swap at all: a `nixos-rebuild` forks ~60 nix
              # evaluators, and stacked on a browser and a few editor sessions
              # that was enough to exhaust it. The kernel then OOM-killed a
              # process inside wayland-wm@hyprland.service, and systemd's default
              # OOMPolicy=stop tore the whole graphical session down with it.
              #
              # zram rather than a swapfile, because root is compress=zstd and a
              # btrfs swapfile needs its own nodatacow, uncompressed subvolume.
              zramSwap = {
                enable = true;
                memoryPercent = 50; # 7.6G of backing store, ~a third of that in real RAM
              };

              # Swapping to RAM is cheap, so let the kernel compress anon pages
              # rather than evict page cache. At the OOM above, cache had already
              # been squeezed to 40M while 13G sat in anon and nothing was
              # reclaimable — the default swappiness of 60 gets that backwards here.
              boot.kernel.sysctl = {
                "vm.swappiness" = 180;
                "vm.page-cluster" = 0; # zram has no seek penalty, so no readahead
              };

              # Build x86_64 derivations (packing-station iso/deploys) via qemu.
              boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

              # Resolve .local names, so the packing stations can be reached and
              # deployed to by hostname instead of by address.
              services.avahi = {
                enable = true;
                nssmdns4 = true;
              };
              services.resolved.settings.Resolve.MulticastDNS = false; # avahi owns mDNS

              # Asahi kernel + Mesa cache, and the Raspberry Pi vendor
              # kernel/firmware cache (else both compile from source).
              nix.settings = {
                extra-substituters = [
                  "https://nixos-apple-silicon.cachix.org"
                  "https://nixos-raspberrypi.cachix.org"
                ];
                extra-trusted-public-keys = [
                  "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
                  "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
                ];
              };
            })
          ];
        };

        # ── Arbitrary x86_64 PC ──
        pc = mkHost {
          system = "x86_64-linux";
          modules = [
            ./hosts/pc/hardware-configuration.nix # generated on the PC
            ({ config, pkgs, ... }: {
              networking.hostName = "pc";

              # GigE camera link: static, never a route out. The segment also
              # carries AAU's IPv6 RAs, and taking them made v6 traffic default
              # out this port into a dead end.
              networking.interfaces.enp7s0 = {
                useDHCP = false;
                ipv4.addresses = [ { address = "192.168.12.1"; prefixLength = 24; } ];
              };
              systemd.network.networks."40-enp7s0" = {
                networkConfig.IPv6AcceptRA = false;
                networkConfig.ConfigureWithoutCarrier = true; # camera may be off
                linkConfig.RequiredForOnline = "no";
              };
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true; # normal x86 UEFI

              # Desktop: never suspend or hibernate, even if something asks.
              systemd.sleep.settings.Sleep = {
                AllowSuspend = "no";
                AllowHibernation = "no";
                AllowHybridSleep = "no";
                AllowSuspendThenHibernate = "no";
              };
              # Ignore the keys that would normally trigger sleep.
              services.logind.suspendKey = "ignore";
              services.logind.hibernateKey = "ignore";
              services.logind.lidSwitch = "ignore";

              # NVIDIA (RTX 20-series or newer → open kernel module).
              services.xserver.videoDrivers = [ "nvidia" ];
              hardware.graphics.enable = true; # OpenGL/Vulkan userspace (was hardware.opengl)
              hardware.nvidia = {
                modesetting.enable = true;      # required for Wayland/Hyprland
                open = true;                    # open kernel module (Turing+)
                nvidiaSettings = true;
                package = config.boot.kernelPackages.nvidiaPackages.stable;
              };

              # Steam's client binary is 32-bit; this also turns on
              # hardware.graphics.enable32Bit so it gets 32-bit NVIDIA GL.
              programs.steam.enable = true;

              # ── RGB ──
              # What is in the case (surveyed via /sys/bus/usb, 2026-10-15):
              #   1b1c:0c1a  Corsair Lighting Node CORE  6 fans (3 LL, 3 QL), USB HID
              #   0b05:19af  ASUS AURA LED Controller    the board's own LEDs, USB HID
              #              (the Lian Li case has no controller of its own; its
              #              strips would be on this board's ARGB headers)
              #   10de:2484  Gigabyte RTX 3070 Vision    i2c on the card's own bus
              #   1e71:3008  NZXT Kraken Z53/Z63/Z73     the LCD, USB HID (the
              #              kernel's nzxt_kraken3 does fans/pump)
              #
              # hosts/pc/rgb.py drives all four directly, with the byte
              # layouts taken from OpenRGB and liquidctl; neither is installed.
              # Colours and the list of dead fan LEDs live in the script. It
              # stays resident because the Corsair hub blanks its per-LED mode
              # without a commit every few seconds. Restart=always also covers
              # the devices not being enumerated yet at boot.
              boot.kernelModules = [ "i2c-dev" ]; # /dev/i2c-* for the GPU
              systemd.services.rgb = {
                description = "Case lighting (hosts/pc/rgb.py)";
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  ExecStart = "${pkgs.python3}/bin/python3 -u ${./hosts/pc/rgb.py} mask --keepalive";
                  Restart = "always";
                  RestartSec = 5;
                };
              };
            })
          ];
        };
      };

      # `nix develop` on either arch.
      devShells = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = [ nixpkgs.legacyPackages.${system}.nodejs ];
        };
      });
    };
}
