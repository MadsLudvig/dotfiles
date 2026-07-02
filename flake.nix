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
  };

  outputs = { self, nixpkgs, apple-silicon, home-manager, firefox-addons, zen-browser, ... }:
    let
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
            ''
            else ''
              monitor = desc:Lenovo Group Limited P27q-20 V909LRFR, 2560x1440@60, 0x0, 1.25
              monitor = desc:Lenovo Group Limited P27q-20 V909LPNY, 2560x1440@60, 2048x0, 1.25
              monitor = desc:Lenovo Group Limited P27q-20 V909LRDD, 2560x1440@60, 4096x0, 1.25
              workspace = 1, monitor:desc:Lenovo Group Limited P27q-20 V909LRFR, default:true
              workspace = 2, monitor:desc:Lenovo Group Limited P27q-20 V909LPNY, default:true
              workspace = 3, monitor:desc:Lenovo Group Limited P27q-20 V909LRDD, default:true
            '';
          "eww".source    = ./config/eww;
          "fuzzel".source = ./config/fuzzel;
        };

        home.pointerCursor = {
          package = pkgs.bibata-cursors;
          name = "Bibata-Modern-Ice";
          size = 24;
          gtk.enable = true;
          x11.enable = true;
          hyprcursor.enable = true;
        };

        # Dark GTK apps (gimp, file dialogs).
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

        home.packages = with pkgs; [ ripgrep fd tridactyl-native lazygit rustc cargo clippy rustfmt rust-analyzer claude-code gcc bluetui impala];
      };

      # ───────────────────── shared system (both hosts) ─────────────────────
      common = { pkgs, ... }: {
        nix.settings.experimental-features = [ "nix-command" "flakes" ];

        networking.networkmanager.enable = true;
        networking.networkmanager.wifi.backend = "iwd";

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

        hardware.bluetooth.enable = true;
        programs.zsh.enable = true;
        fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

        environment.systemPackages = with pkgs; [
          git kitty fuzzel gimp
          wl-clipboard grim slurp swaybg brightnessctl playerctl grimblast
          hyprpolkitagent xdg-utils
        ];

        users.users.mads = {
          isNormalUser = true;
          extraGroups = [ "wheel" "networkmanager" "video" ];
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

              boot.loader.systemd-boot.enable = true;
              boot.loader.systemd-boot.configurationLimit = 3; # 500M ESP is small
              boot.extraModprobeConfig = "options hid_apple fnmode=1";
              boot.blacklistedKernelModules = [ "pcspkr" ];

              # Asahi kernel + Mesa cache (else compile from source).
              nix.settings = {
                extra-substituters = [ "https://nixos-apple-silicon.cachix.org" ];
                extra-trusted-public-keys = [
                  "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
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
            ({ config, ... }: {
              networking.hostName = "pc";
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true; # normal x86 UEFI

              # NVIDIA (RTX 20-series or newer → open kernel module).
              services.xserver.videoDrivers = [ "nvidia" ];
              hardware.graphics.enable = true; # OpenGL/Vulkan userspace (was hardware.opengl)
              hardware.nvidia = {
                modesetting.enable = true;      # required for Wayland/Hyprland
                open = true;                    # open kernel module (Turing+)
                nvidiaSettings = true;
                package = config.boot.kernelPackages.nvidiaPackages.stable;
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
