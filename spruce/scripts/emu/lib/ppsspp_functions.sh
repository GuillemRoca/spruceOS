#!/bin/sh

# Requires globals:
#   PLATFORM
#   EMU_DIR
#   ROM_FILE
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Requires functions:
#   log_message
#
# Provides:
#   move_dotconfig_into_place
#   run_ppsspp
#   load_ppsspp_configs
#   save_ppsspp_configs
#   move_screenshots_if_present

SS_DIR="/mnt/SDCARD/Saves/screenshots/PPSSPP"
PSP_SS_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SCREENSHOT"
PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"

set_up_default_configs_if_needed() {
	if [ ! -d "/mnt/SDCARD/Saves/.config/ppsspp/PSP" ]; then
		mkdir -p "/mnt/SDCARD/Saves/.config/ppsspp/"
		cp -rf "/mnt/SDCARD/Emu/PSP/default_configs" "/mnt/SDCARD/Saves/.config/ppsspp/PSP" && log_message "Copied .config folder into Saves folder."
	else
		log_message "WARNING!!! No .config folder found!"
	fi
}

move_screenshots_if_present() {
	if [ -n "$(ls -A $PSP_SS_DIR/*.png 2>/dev/null)" ]; then
		mv $PSP_SS_DIR/*.png "$SS_DIR" 2>/dev/null
	fi
}

run_ppsspp() {

	set_up_default_configs_if_needed
	load_ppsspp_configs
	configure_retroachievements
	configure_language

	export HOME=/mnt/SDCARD/Saves
	cd $EMU_DIR

	mkdir -p "$PSP_SS_DIR"
	mkdir -p "$SS_DIR"

	move_screenshots_if_present
	mount -o bind "$SS_DIR" "$PSP_SS_DIR"

	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR"

	case "$PLATFORM" in
		# PowerVR devices need mali-fbdev SDL video driver and global alpha mode
		"Brick"|"SmartPro"|"BrickPro"|"Zero28"|"Zero40"|"XU20")
			export SDL_VIDEODRIVER=mali
			"$EMU_DIR/setalpha" 0
			rm -f "$PSP_DIR/FailedGraphicsBackends.txt"
			;;
		# The Anbernic pad has no SDL gamecontroller mapping on this rootfs, so
		# PPSSPP falls back to raw joystick indices and every button lands wrong
		# (the same reason RetroArch needed an sdl2 autoconfig). Registering the
		# mapping makes SDL_IsGameController true, so PPSSPP maps by SDL button
		# name and the shipped controls-*.ini works unchanged. POSITIONAL, like
		# every other arm64 device (the Flip and the TrimUI line run on SDL's
		# built-in X360 map): PPSSPP puts Cross on SDL A, and SDL A must be the
		# bottom button for Cross to sit where the PSP has it, and for the
		# controls-*.ini hotkeys to read SELECT+B exit / SELECT+A screenshot /
		# SELECT+X pause as they do fleet-wide. The label-named map put Cross
		# on the right-hand A button instead. Video also needs the mali driver,
		# as on the PowerVR devices. Mapping GUID/indices verified on CubeXX;
		# matches MustardOS.
		"Anbernic"*)
			export SDL_VIDEODRIVER=mali
			export_sdl_gamecontroller_map positional
			;;
	esac

	# accommodate both relative and absolute paths for PPSSPP bin location
	case "$PSP_BIN" in
		"/"*) PPSSPPSDL="$PSP_BIN" ;;
		*)    PPSSPPSDL="./$PSP_BIN" ;;
	esac

	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	if [ -z "$ROM_FILE" ]; then
		LD_PRELOAD="$(vk_display_preload)" "$PPSSPPSDL" --fullscreen > "$(emu_log_file)" 2>&1
	else
		LD_PRELOAD="$(vk_display_preload)" "$PPSSPPSDL" "$ROM_FILE" --fullscreen --pause-menu-exit > "$(emu_log_file)" 2>&1
	fi

	umount "$PSP_SS_DIR"
	save_ppsspp_configs
}

configure_retroachievements() {
	rac_mode="$(get_config_value '.menuOptions."RetroAchievements Settings".modeToggle.selected' "Manual")"
	rac_user="$(get_config_value '.menuOptions."RetroAchievements Settings".username.selected' "")"
	log_message "Cheevos mode is $rac_mode" -v

	case "$rac_mode" in
		"Disabled")
			# disable cheevos but leave everything else alone
			TMP_CFG="$(mktemp)"
			if sed -e "s|^AchievementsEnable.*|AchievementsEnable = False|" "$PSP_DIR/ppsspp.ini" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PSP_DIR/ppsspp.ini"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		"Casual"|"Softcore")
			TMP_CFG="$(mktemp)"
			if sed \
				-e "s|^AchievementsEnable.*|AchievementsEnable = True|" \
				-e "s|^AchievementsChallengeMode.*|AchievementsChallengeMode = False|" \
				-e "s|^AchievementsUserName.*|AchievementsUserName = \"$rac_user\"|" \
			"$PSP_DIR/ppsspp.ini" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PSP_DIR/ppsspp.ini"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		"Hardcore")
			TMP_CFG="$(mktemp)"
			if sed \
				-e "s|^AchievementsEnable.*|AchievementsEnable = True|" \
				-e "s|^AchievementsChallengeMode.*|AchievementsChallengeMode = True|" \
				-e "s|^AchievementsUserName.*|AchievementsUserName = \"$rac_user\"|" \
			"$PSP_DIR/ppsspp.ini" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PSP_DIR/ppsspp.ini"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		*) return 0 ;; # case for Auto - do nothing
	esac

	# update auth token if spruce rac username different from what was in ppsspp.ini
	# or just create it if it's missing
	case "$rac_mode" in
		Casual|Softcore|Hardcore)
			ini_user="$(grep '^AchievementsUserName' "$PSP_DIR/ppsspp.ini" | sed 's/.*= *"\(.*\)".*/\1/')"
			if [ "$ini_user" != "$rac_user" ] || [ ! -f "$PSP_DIR/ppsspp_retroachievements.dat" ]; then
				rac_pass="$(get_config_value '.menuOptions."RetroAchievements Settings".password.selected' "")"
				/mnt/SDCARD/spruce/scripts/emu/psp_rac_auth.sh "$rac_user" "$rac_pass"
			fi
			;;
	esac
}

# PPSSPP's menu language (a file in Emu/PSP/assets/lang) for a PyUI language
# file name; empty when PPSSPP has no such language or none is set.
ppsspp_language_for_ui_language() {
	case "$1" in
		"Azerbaijani") echo az_AZ ;;
		"Catalan") echo ca_ES ;;
		"Chinese (S)") echo zh_CN ;;
		"Chinese (T)") echo zh_TW ;;
		"Croatian") echo hr_HR ;;
		"English") echo en_US ;;
		"French") echo fr_FR ;;
		"German") echo de_DE ;;
		"Greek") echo gr_EL ;;
		"Italian") echo it_IT ;;
		"Japanese") echo ja_JP ;;
		"Korean") echo ko_KR ;;
		"Lao") echo lo_LA ;;
		"Polish") echo pl_PL ;;
		"Portuguese (BR)") echo pt_BR ;;
		"Portuguese (Eur)") echo pt_PT ;;
		"Romanian") echo ro_RO ;;
		"Russian") echo ru_RU ;;
		"Spanish") echo es_ES ;;
		"Tagalog") echo tg_PH ;;
		"Thai") echo th_TH ;;
		"Turkish") echo tr_TR ;;
		"Ukrainian") echo uk_UA ;;
		"Vietnamese") echo vi_VN ;;
	esac
}

# Show PPSSPP's menus in the UI language. Only the [General] locale line
# (Language = xx_YY) changes; [SystemParam] Language is the PSP's own setting.
configure_language() {
	ppsspp_language="$(ppsspp_language_for_ui_language "$(get_ui_language)")"
	[ -z "$ppsspp_language" ] && return
	[ -f "$EMU_DIR/assets/lang/$ppsspp_language.ini" ] || return
	TMP_CFG="$(mktemp)"
	if sed -e "s|^Language = [a-z][a-z]_[A-Z][A-Z]|Language = $ppsspp_language|" "$PSP_DIR/ppsspp.ini" > "$TMP_CFG"; then
		mv "$TMP_CFG" "$PSP_DIR/ppsspp.ini"
	else
		rm -f "$TMP_CFG"
	fi
}

load_ppsspp_configs() {
	cp -f "$PSP_DIR/controls-$PLATFORM.ini" "$PSP_DIR/controls.ini"
	cp -f "$PSP_DIR/ppsspp-$PLATFORM.ini" "$PSP_DIR/ppsspp.ini"
}

save_ppsspp_configs() {
	cp -f "$PSP_DIR/controls.ini" "$PSP_DIR/controls-$PLATFORM.ini"
	cp -f "$PSP_DIR/ppsspp.ini" "$PSP_DIR/ppsspp-$PLATFORM.ini"
}
