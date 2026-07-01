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
      home = { pkgs, ... }: {
        imports = [ zen-browser.homeModules.beta ];
        home.stateVersion = "25.11";

        # Raw configs that stay files (no good native module).
        xdg.configFile = {
          "hypr".source   = ./config/hypr;
          "eww".source    = ./config/eww;
          "fuzzel".source = ./config/fuzzel;
        };

        # Dark GTK apps (gimp, file dialogs).
        gtk = {
          enable = true;
          theme = { name = "Adwaita-dark"; package = pkgs.gnome-themes-extra; };
          gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
          gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
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
            };
            extensions.packages = with firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
              tridactyl
              ublock-origin
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

        home.packages = with pkgs; [ ripgrep fd tridactyl-native ];
      };

      # ───────────────────── shared system (both hosts) ─────────────────────
      common = { pkgs, ... }: {
        nix.settings.experimental-features = [ "nix-command" "flakes" ];

        networking.networkmanager.enable = true;
        networking.networkmanager.wifi.backend = "iwd";

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
        home-manager.users.mads = home;
      };

      mkHost = { system, modules }: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ home-manager.nixosModules.home-manager common ] ++ modules;
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
            ({ ... }: {
              networking.hostName = "pc";
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true; # normal x86 UEFI
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
