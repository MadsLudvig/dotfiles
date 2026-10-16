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
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, apple-silicon, home-manager, zen-browser, nixvim, ... }:
    let
      # ───────────────────── shared home-manager user ─────────────────────
      home = { pkgs, lib, osConfig, ... }: {
        imports = [ zen-browser.homeModules.beta nixvim.homeModules.nixvim ];
        home.stateVersion = "25.11";

        wayland.windowManager.hyprland = {
          enable = true;
          package = null;
          portalPackage = null;
          configType = "lua";
          systemd.enable = false;

          settings = {
            config = {
              input = {
                kb_layout = "us,dk";
                kb_options = "caps:ctrl_modifier,grp:win_space_toggle";
                repeat_rate = 50;
                repeat_delay = 300;
                accel_profile = "custom";
                scroll_points = "0.5 1.0 1.5 2.0 2.5";
                touchpad = {
                  natural_scroll = true;
                  scroll_factor = 0.9;
                  tap_to_click = false;
                  clickfinger_behavior = true;
                  disable_while_typing = true;
                };
              };
              general = { gaps_in = 0; gaps_out = 0; border_size = 0; };
              animations.enabled = false;
              dwindle = { preserve_split = true; force_split = 2; };
              misc = {
                background_color = "rgb(16181a)";
                disable_hyprland_logo = true;
                disable_splash_rendering = true;
                focus_on_activate = true;
              };
              ecosystem = { no_update_news = true; no_donation_nag = true; };
            };

            monitor = [
              {
                output = "desc:ASUSTek COMPUTER INC XG32UQWMS W6LMQS013451";
                mode = "3840x2160@240"; position = "0x0"; scale = 1.25;
              }
              { output = ""; mode = "preferred"; position = "auto"; scale = 2.0; }
            ];


            window_rule = [ { match.class = ".*"; suppress_event = "maximize"; } ];

            env = [ { _args = [ "HYPRSHOT_DIR" (lib.generators.mkLuaInline ''os.getenv("HOME") .. "/Pictures/Screenshots"'') ]; } ];
          };

          extraConfig = ''
            -- -- Autostart (runs once, like exec-once) --
            hl.on("hyprland.start", function()
                hl.exec_cmd("uwsm finalize")
                hl.exec_cmd("hyprlock")  -- boot lands on the lock screen; see greetd in `common`
                hl.exec_cmd("systemctl --user start hyprpolkitagent")
            end)

            -- -- Core --
            hl.bind("SUPER + Return", hl.dsp.exec_cmd("kitty"))
            hl.bind("SUPER + D", hl.dsp.exec_cmd("fuzzel"))
            hl.bind("SUPER + Q", hl.dsp.window.close())

            -- Battery readout while SUPER+R is held, as a Hyprland notification.
            -- Reads sysfs directly (instant, so fine inside a bind); the names
            -- cover Asahi (macsmc-battery) and x86 (BAT0/BAT1).
            local function battery()
                for _, name in ipairs({ "macsmc-battery", "BAT0", "BAT1" }) do
                    local dir = "/sys/class/power_supply/" .. name
                    local cap = io.open(dir .. "/capacity")
                    if cap then
                        local pct = cap:read("*l"); cap:close()
                        local st = io.open(dir .. "/status")
                        local status = st and st:read("*l") or "?"
                        if st then st:close() end
                        return pct .. "% " .. status
                    end
                end
                return "no battery"
            end
            local batteryPopup
            hl.bind("SUPER + R", function()
                batteryPopup = hl.notification.create({ text = battery(), timeout = 10000 })
            end)
            hl.bind("SUPER + R", function()
                if batteryPopup then batteryPopup:dismiss(); batteryPopup = nil end
            end, { release = true })
            hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
            hl.bind("SUPER + SHIFT + Space", hl.dsp.window.float())
            hl.bind("SUPER + Escape", hl.dsp.exec_cmd("hyprlock"))

            -- -- Floating panels --
            -- Each gets its own app_id so only these float and not every terminal.
            -- Quit with the TUI's own `q`; no toggle wrapper. 70% wide and full
            -- height of the monitor it opens on, worked out at key press, so it
            -- follows scale and screen changes without per-host numbers.
            local function panel(cmd)
                return function()
                    local m = hl.get_active_monitor()
                    local rules = { float = true, center = true }
                    if m then
                        rules.size = { math.floor(m.width / m.scale * 0.7), math.floor(m.height / m.scale) }
                    end
                    hl.dispatch(hl.dsp.exec_cmd(cmd, rules))
                end
            end
            hl.bind("SUPER + W", panel("kitty --class panel-wifi impala"))
            hl.bind("SUPER + E", panel("kitty --class panel-bt bluetui"))

            -- -- Focus / move --
            hl.bind("SUPER + h", hl.dsp.focus({ direction = "left" }))
            hl.bind("SUPER + j", hl.dsp.focus({ direction = "down" }))
            hl.bind("SUPER + k", hl.dsp.focus({ direction = "up" }))
            hl.bind("SUPER + l", hl.dsp.focus({ direction = "right" }))
            hl.bind("SUPER + SHIFT + h", hl.dsp.window.move({ direction = "left" }))
            hl.bind("SUPER + SHIFT + j", hl.dsp.window.move({ direction = "down" }))
            hl.bind("SUPER + SHIFT + k", hl.dsp.window.move({ direction = "up" }))
            hl.bind("SUPER + SHIFT + l", hl.dsp.window.move({ direction = "right" }))

            -- -- Workspaces (AeroSpace-style) --
            -- SUPER+N switches to workspace N; SUPER+SHIFT+N sends the window there
            -- without following it (AeroSpace's move-node-to-workspace).
            for i = 1, 5 do
                hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = i }))
                hl.bind("SUPER + SHIFT + " .. i, hl.dsp.window.move({ workspace = i, follow = false }))
            end
            hl.bind("SUPER + Tab", hl.dsp.focus({ workspace = "previous" }))

            -- -- Resize (hold to repeat) / mouse --
            hl.bind("SUPER + CTRL + h", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
            hl.bind("SUPER + CTRL + j", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })
            hl.bind("SUPER + CTRL + k", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
            hl.bind("SUPER + CTRL + l", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
            hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
            hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

            -- -- Media keys (locked: work on the lock screen; repeating: hold to repeat) --
            hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
            hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { locked = true, repeating = true })
            hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute   @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
            hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute   @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
            hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true, repeating = true })
            hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })
            hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
            hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true })
            hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

            -- -- Screenshots: focused monitor / region (screen frozen) -> file + clipboard --
            hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd("hyprshot -m output"))
            hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("hyprshot -m region -z"))
          '';
        };

        programs.hyprlock = {
          enable = true;
          package = null;
          settings = {
            general = {
              hide_cursor = true;
              disable_loading_bar = true;
              no_fade_in = true;
              no_fade_out = true;
            };
            background = [ { color = "rgb(000000)"; } ];
            input-field = [{
              size = "400, 60";
              outline_thickness = 20;
              rounding = 0;
              outer_color = "rgba(ffffffff)";
              inner_color = "rgba(000000ff)";
              font_color = "rgb(ffffff)";
              font_family = "JetBrainsMono Nerd Font";
              font_size = 16;
              fade_on_empty = false;
              fade_timeout = 0;
              placeholder_text = "";
              hide_input = true;
              fail_color = "rgb(ff5555)";
              fail_text = "";
              capslock_color = "rgb(ffb000)";
            }];
          };
        };

        services.hypridle = {
          enable = true;
          package = null;
          settings = {
            general = {
              lock_cmd = "hyprlock";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl dispatch dpms on";
            };
            listener = lib.optional (osConfig.networking.hostName == "mbp") {
              timeout = 300;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            } ++ [{
              timeout = 600;
              on-timeout = "loginctl lock-session";
            }];
          };
        };

        programs.fuzzel = {
          enable = true;
          settings = {
            main = {
              font = "JetBrainsMono Nerd Font:size=12";
              terminal = "kitty";
              lines = 8;
              width = 40;
              horizontal-pad = 16;
              vertical-pad = 12;
              inner-pad = 4;
            };
            colors = {
              background = "16181aff";
              text = "ffffffff";
              match = "ff6e5eff";
              selection = "3c4048ff";
              selection-text = "ffffffff";
            };
            border = { width = 0; radius = 0; };
          };
        };

        programs.kitty = {
          enable = true;
          settings = {
            font_size = "11.5";
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
          hyprcursor.enable = true;
        };

        gtk = {
          enable = true;
          gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
          gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
        };

        programs.nixvim = {
          nixpkgs.useGlobalPackages = true;
          enable = true;
          withPython3 = false;
          withRuby = false;
          globals.mapleader = " ";
          opts = {
            winborder = "rounded";
            tabstop = 2;
            shiftwidth = 2;
            expandtab = true;
            smartindent = true;
            wrap = false;
            number = true;
            relativenumber = true;
            ignorecase = true;
            undofile = true;
            signcolumn = "yes";
            clipboard = "unnamedplus";
          };
          colorschemes.cyberdream.enable = true;
          plugins = {
            web-devicons.enable = true;
            blink-cmp.enable = true;
            todo-comments.enable = true;
            trouble.enable = true;
            fidget.enable = true;
            typst-preview.enable = true;
            treesitter = {
              enable = true;
              settings.highlight.enable = true;
            };
            lualine = {
              enable = true;
              settings.options = {
                component_separators = { left = "|"; right = "|"; };
                section_separators   = { left = "|"; right = "|"; };
              };
            };
            oil = {
              enable = true;
              settings = {
                default_file_explorer = true;
                delete_to_trash = true;
                skip_confirm_for_simple_edits = true;
                view_options.show_hidden = true;
                use_default_keymaps = false;
                keymaps = {
                  "g?"   = { __unkeyed-1 = "actions.show_help"; mode = "n"; };
                  "<CR>" = "actions.select";
                  "-"    = { __unkeyed-1 = "actions.parent"; mode = "n"; };
                  "_"    = { __unkeyed-1 = "actions.open_cwd"; mode = "n"; };
                  "`"    = { __unkeyed-1 = "actions.cd"; mode = "n"; };
                };
              };
            };
            snacks = {
              enable = true;
              settings.picker.ui_select = true;
            };
            lspconfig.enable = true;
          };
          lsp = {
            servers = {
              lua_ls.enable = true;
              nixd.enable = true;
              rust_analyzer.enable = true;
              ts_ls.enable = true;
              html.enable = true;
              cssls.enable = true;
              jsonls.enable = true;
              tinymist.enable = true;
              zls.enable = true;
              yamlls.enable = true;
              svelte.enable = true;
            };
            keymaps = [
              { key = "gd"; lspBufAction = "definition"; }
              { key = "gD"; lspBufAction = "declaration"; }
              { key = "<leader>ca"; lspBufAction = "code_action"; }
              { key = "<leader>cr"; lspBufAction = "rename"; }
              { key = "gr"; action.__raw = "Snacks.picker.lsp_references"; }
              { key = "gt"; action.__raw = "Snacks.picker.lsp_type_definitions"; }
              { key = "<leader>ss"; action.__raw = "Snacks.picker.lsp_symbols"; }
              { key = "<leader>sS"; action.__raw = "Snacks.picker.lsp_workspace_symbols"; }
            ];
          };
          autoCmd = [{
            event = "TextYankPost";
            callback.__raw = "function() vim.highlight.on_yank() end";
          }];
          keymaps =
            let
              n = key: action: { mode = "n"; inherit key action; };
              nr = key: lua: { mode = "n"; inherit key; action.__raw = lua; };
            in [
              (n "<leader>w" ":write<CR>")
              (n "<leader>q" ":quit<CR>")
              (n "<leader>e" ":Oil<CR>")
              (n "<leader>x" ":Trouble diagnostics toggle filter.buf=0<CR>")
              (n "<leader>X" ":Trouble diagnostics<CR>")
              (n "<leader>|" ":vsplit<CR>")
              (n "<leader>_" ":split<CR>")
              (n "<ESC>" ":noh<CR>")
              (n "<C-h>" "<C-w>h")
              (n "<C-l>" "<C-w>l")
              (n "<C-k>" "<C-w>k")
              (n "<C-j>" "<C-w>j")
              (nr "<leader>f"  "function() Snacks.picker.files() end")
              (nr "<leader>sg" "function() Snacks.picker.grep() end")
              (nr "<leader>g"  "function() Snacks.lazygit() end")
              (nr "<leader>t"  "function() Snacks.picker.todo_comments() end")
              (nr "<leader>lf" "vim.lsp.buf.format")
              { mode = [ "n" "t" ]; key = "<C-t>"; action.__raw = ''function() Snacks.terminal.toggle("zsh") end''; }
              { mode = "v"; key = ">"; action = ">gv"; options = { silent = true; desc = "Indent and reselect"; }; }
              { mode = "v"; key = "<"; action = "<gv"; options = { silent = true; desc = "Unindent and reselect"; }; }
            ];
        };

        programs.zen-browser = {
          enable = true;
          setAsDefaultBrowser = true;
          profiles.default = {
            settings = {
              "browser.newtabpage.enabled" = false;
              "privacy.donottrackheader.enabled" = true;
              "browser.theme.toolbar-theme" = 0;
              "browser.theme.content-theme" = 0;
              "layout.css.prefers-color-scheme.content-override" = 0;
              "ui.systemUsesDarkTheme" = 1;
            };
          };
        };
            
        programs.zsh = {
          enable = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          shellAliases = { ll = "ls -alh"; gs = "git status"; };
        };
        programs.starship.enable = true;
        programs.git = {
          enable = true;
          settings.user = { name = "Mads Fagerlund"; email = "mads@deepvis.ai"; };
        };

        home.packages = with pkgs; [ 
          ripgrep 
          fd 
          lazygit
          gh
          rustc 
          cargo 
          clippy 
          rustfmt 
          rust-analyzer 
          claude-code 
          gcc 
          bluetui 
          impala 
          fastfetch 
          remmina 
          unzip
        ];
      };

      # ───────────────────── shared system (both hosts) ─────────────────────
      common = { pkgs, ... }: {
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        nix.settings.extra-substituters = [ "https://deepvis.cachix.org" ];
        nix.settings.extra-trusted-public-keys = [
          "deepvis.cachix.org-1:UE/H6ERLwqhSqubzh8+pzl9eTm0kpMExGe0ym6fENp8="
        ];
        nix.settings.netrc-file = "/etc/nix/netrc";

        networking.wireless.iwd.enable = true;
        networking.useNetworkd = true;
        systemd.network.wait-online.anyInterface = true;
        services.gnome.gnome-keyring.enable = true;
        programs._1password.enable = true;
        programs._1password-gui = {
          enable = true;
          polkitPolicyOwners = [ "mads" ];
        };

        environment.etc."1password/custom_allowed_browsers".text = ''zen-beta'';

        services.tailscale.enable = true;
        services.tailscale.extraUpFlags = [ "--ssh" ];

        time.timeZone = "Europe/Copenhagen";
        i18n.defaultLocale = "en_US.UTF-8";

        programs.hyprland = { enable = true; withUWSM = true; };
        programs.hyprlock.enable = true;

        systemd.user.services."wayland-wm@".serviceConfig.OOMPolicy = "continue";
        services.hypridle.enable = true;
        security.pam.services.hyprlock.enableGnomeKeyring = true;


        services.greetd = {
          enable = true;
          settings = {
            default_session = { user = "mads"; command = "uwsm start -eD Hyprland hyprland.desktop"; };
          };
        };

        virtualisation.docker.enable = true;

        hardware.bluetooth.enable = true;
        programs.zsh.enable = true;
        documentation.nixos.enable = false;

        fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

        environment.systemPackages = with pkgs; [
          git
          wl-clipboard brightnessctl playerctl hyprshot
          hyprpolkitagent xdg-utils
        ];

        users.users.mads = {
          isNormalUser = true;
          extraGroups = [ "wheel" "video" "docker" ];
          shell = pkgs.zsh;
          initialPassword = "changeme";
        };

        system.stateVersion = "25.11";
        nixpkgs.config.allowUnfree = true;
        hardware.enableRedistributableFirmware = true;

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "hm-bak";
        home-manager.users.mads = home;
      };

      mkHost = { system, modules }: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ 
          home-manager.nixosModules.home-manager 
          common 
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
            ({ pkgs, ... }: {
              networking.hostName = "mbp";

              boot.initrd.availableKernelModules = [ "usb_storage" "sdhci_pci" ];
              fileSystems."/" = {
                device = "/dev/disk/by-uuid/c828c1a0-ce7b-4e27-b8e4-bce032bb30bf";
                fsType = "btrfs";
                options = [ "subvol=@" "compress=zstd" "noatime" ];
              };
              fileSystems."/boot" = {
                device = "/dev/disk/by-uuid/0BB8-A960";
                fsType = "vfat";
                options = [ "fmask=0022" "dmask=0022" ];
              };

              hardware.asahi.peripheralFirmwareDirectory =
                pkgs.linkFarm "mbp-firmware" [ { name = "firmware.cpio"; path = ./mbp-firmware.cpio; } ];
              hardware.asahi.enable = true;

              boot.loader.systemd-boot.enable = true;
              boot.loader.systemd-boot.configurationLimit = 3;
              boot.extraModprobeConfig = "options hid_apple fnmode=1";

              services.btrfs.autoScrub = {
                enable = true;
                interval = "monthly";
                fileSystems = [ "/" ];
              };

              zramSwap = {
                enable = true;
                memoryPercent = 50;
              };

              boot.kernel.sysctl = {
                "vm.swappiness" = 180;
                "vm.page-cluster" = 0;
              };


              services.avahi = {
                enable = true;
                nssmdns4 = true;
              };
              services.resolved.settings.Resolve.MulticastDNS = false;

              nix.settings = {
                extra-substituters = [
                  "https://nixos-apple-silicon.cachix.org"
                ];
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
            ({ pkgs, ... }:
            let
              rgb = pkgs.writers.writePython3Bin "rgb" { flakeIgnore = [ "E401" "E501" ]; } ''
                import fcntl, glob, os, select, sys, time
                
                FAN = (0x80, 0x60, 0x38)
                BOARD = (0x80, 0x70, 0x60)
                LEDS = 150
                DEAD = {58, 69, 80, 97, 99, 110, 121, 124, 142}
                
                hid = {}
                for uevent in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"):
                    for line in open(uevent):
                        if line.startswith("HID_NAME="):
                            hid[line[9:].strip()] = "/dev/" + uevent.split("/")[4]
                
                hub = os.open(next(p for n, p in hid.items() if "Lighting Node CORE" in n), os.O_RDWR)
                colors = [(0, 0, 0) if i + 1 in DEAD else FAN for i in range(LEDS)]
                packets = [[0x38, 0, 0x02]]
                for off in range(0, LEDS, 50):
                    chunk = colors[off:off + 50]
                    for plane in range(3):
                        packets.append([0x32, 0, off, len(chunk), plane, *[c[plane] for c in chunk]])
                packets.append([0x33, 0xFF])
                for p in packets:
                    os.write(hub, bytes([0x00, *p]).ljust(65, b"\0"))
                    if select.select([hub], [], [], 0.5)[0]:
                        os.read(hub, 17)
                
                fd = os.open(next(p for n, p in hid.items() if "AURA LED Controller" in n), os.O_RDWR)
                os.write(fd, bytes([0xEC, 0xB0]).ljust(65, b"\0"))
                table = os.read(fd, 65) if select.select([fd], [], [], 1.0)[0] else b""
                n = table[4 + 0x1B] if len(table) >= 0x20 and table[1] == 0x30 else 3
                mask = (1 << n) - 1
                for p in ([0x52, 0x53, 0x00, 0x01],
                          [0x35, 0x00, 0x00, 0x00, 0x01],
                          [0x36, mask >> 8, mask & 0xFF, 0x00, *(BOARD * n)],
                          [0x3F, 0x55]):
                    os.write(fd, bytes([0xEC, *p]).ljust(65, b"\0"))
                os.close(fd)
                
                for path in glob.glob("/sys/class/i2c-dev/i2c-*"):
                    if "NVIDIA" not in open(path + "/name").read():
                        continue
                    fd = os.open("/dev/" + os.path.basename(path), os.O_RDWR)
                    fcntl.ioctl(fd, 0x0703, 0x63)
                    try:
                        for b in (0xAB, 0, 0, 0):
                            os.write(fd, bytes([b]))
                        ok = os.read(fd, 1)[0] == 0xAB and os.read(fd, 1)[0] in (0x10, 0x11, 0x12, 0x14)
                    except OSError:
                        ok = False
                    if ok:
                        for b in (0x40, *BOARD, 0x88, 0x01, 0x00, 0x63, 0xAA, 0, 0, 0):
                            os.write(fd, bytes([b]))
                    os.close(fd)
                    if ok:
                        break
                else:
                    print("gpu: not found on any NVIDIA i2c bus", file=sys.stderr)
                
                fd = os.open(next(p for n, p in hid.items() if "KrakenZ" in n), os.O_RDWR)
                os.write(fd, bytes([0x30, 0x01]).ljust(64, b"\0"))
                orientation = 0
                for _ in range(12):
                    reply = os.read(fd, 64) if select.select([fd], [], [], 1.0)[0] else b""
                    if reply[:2] == b"\x31\x01":
                        orientation = reply[0x1A]
                        break
                os.write(fd, bytes([0x30, 0x02, 0x01, 0, 0, 0, 1, orientation]).ljust(64, b"\0"))
                os.close(fd)
                
                print("lighting set; committing the hub every 4 s", flush=True)
                while True:
                    time.sleep(4)
                    os.write(hub, bytes([0x00, 0x33, 0xFF]).ljust(65, b"\0"))
                    if select.select([hub], [], [], 0.5)[0]:
                        os.read(hub, 17)
              '';
            in {
              networking.hostName = "pc";

              boot.initrd.availableKernelModules = [
                "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" "sr_mod" "vmd"
              ];
              fileSystems."/" = { device = "/dev/disk/by-label/NIXROOT"; fsType = "ext4"; };
              fileSystems."/boot" = { device = "/dev/disk/by-label/NIXBOOT"; fsType = "vfat"; };

              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;

              systemd.sleep.settings.Sleep = {
                AllowSuspend = "no";
                AllowHibernation = "no";
              };


              services.xserver.videoDrivers = [ "nvidia" ];
              hardware.graphics.enable = true;
              hardware.nvidia = {
                modesetting.enable = true;
                open = true;
                nvidiaSettings = false;
              };

              boot.kernelModules = [ "i2c-dev" ];
              systemd.services.rgb = {
                description = "Case lighting";
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  ExecStart = "${rgb}/bin/rgb";
                  Restart = "always";
                  RestartSec = 5;
                };
              };
            })
          ];
        };
      };
    };
}
