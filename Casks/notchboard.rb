# Cask definition for a personal tap, not for homebrew/cask.
#
# Notchboard does not meet the homebrew/cask acceptance criteria yet (the thresholds and
# what is missing are written out in docs/RELEASING.md), so this file exists to be copied
# into a tap repository as Casks/notchboard.rb:
#
#   brew tap thepearl/tap
#   brew install --cask notchboard
#
# or in one line: brew install --cask thepearl/tap/notchboard
#
# The zap paths below are read out of the source, not guessed:
#   ~/Library/Application Support/Notchboard  Persistence/AppStateStore.swift
#   ~/.notchboard/snapshots                   Persistence/SnapshotStore.swift
#
# The three Keychain services cannot be cleared by a cask (there is no zap directive for
# Keychain items, and deleting the login keychain would take everything else with it).
# They are listed under the zap stanza with the commands that clear them by hand.
#
# The sha256 is the checksum of the final zip attached to the GitHub release: signed,
# notarised, stapled, then zipped one last time (every re-zip changes it, so only the
# last one counts). Homebrew checks the download against that line, so a stale value
# fails the install loudly instead of installing the wrong build. It cannot carry a
# comment of its own, because rubocop's Cask/StanzaGrouping cop treats a comment as a
# group break and then demands blank lines that the same cop rejects.
cask "notchboard" do
  version "1.0"
  sha256 "08b20ab802fb8cd5e83fe05b7c2481ded051b3b4f64772bc5e1c4d1102ab873d"

  url "https://github.com/thepearl/notchboard/releases/download/v#{version}/notchboard-#{version}.zip"
  name "Notchboard"
  desc "Docks a shared catalogue of test accounts to the iOS Simulator window"
  homepage "https://github.com/thepearl/notchboard"

  livecheck do
    url :url
    strategy :github_latest
  end

  # A bare symbol is the minimum, not an exact match: this resolves to macOS >= 14, which
  # is MACOSX_DEPLOYMENT_TARGET. The ">= :sonoma" string spelling means the same thing but
  # Homebrew now deprecates it and warns on every load.
  depends_on macos: :sonoma

  app "notchboard.app"

  # Notchboard runs as an accessory agent with no Dock icon, so an upgrade has to quit it
  # explicitly. The login item is registered by SMAppService under the app's own name
  # (Persistence/LaunchAtLogin.swift), and survives a plain uninstall without this.
  uninstall quit:       "flourix.notchboard",
            login_item: "notchboard"

  # ~/.notchboard holds the encrypted snapshots. Application Support/Notchboard holds
  # state.json and, if a launch ever found the file unreadable, state.json.corrupt.
  # The remaining three are written by AppKit for any bundle id and may not exist.
  zap trash: [
    "~/.notchboard",
    "~/Library/Application Support/Notchboard",
    "~/Library/Caches/flourix.notchboard",
    "~/Library/Preferences/flourix.notchboard.plist",
    "~/Library/Saved Application State/flourix.notchboard.savedState",
  ]

  # Not reachable from a cask. Every secret value, room password and snapshot key lives
  # in the login keychain under one of three services, and clearing them is manual:
  #
  #   security delete-generic-password -s flourix.notchboard.secrets
  #   security delete-generic-password -s flourix.notchboard.rooms
  #   security delete-generic-password -s flourix.notchboard.device
  #
  # Each call removes one matching item, so repeat until it reports nothing left to find.

  caveats <<~EOS
    Notchboard needs Accessibility permission to find the Simulator window. Grant it in
    System Settings, Privacy & Security, Accessibility on first launch.
  EOS
end
